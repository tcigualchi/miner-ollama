"""Headless GrabCraft blueprint inspector for CC:Tweaked terminals."""
from __future__ import annotations

import html
import json
import os
import re
import secrets
from functools import lru_cache
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

TOKEN = os.environ.get("GRABCRAFT_TOKEN", "")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA_CLIENT = os.path.join(ROOT, "turtle", "grabcraft.lua")
LUA_INSTALLER = os.path.join(ROOT, "turtle", "grabcraft-install.lua")
AE2_SUPPLY_CLIENT = os.path.join(ROOT, "central", "ae2-supply.lua")
app = FastAPI(title="GrabCraft terminal bridge", docs_url=None, redoc_url=None, openapi_url=None)

# Skip model entries with no usable survival item for this builder. The filter
# is shared by the material preflight and layer feed so ignored voxels never
# stop construction later.
IGNORED_BLOCKS = {
    "grass", "grass block", "barrier", "bedrock", "spawner",
    "end portal frame", "end portal", "nether portal",
    "command block", "chain command block", "repeating command block",
    "structure block", "structure void", "jigsaw block", "light block",
    "reinforced deepslate", "debug block",
}


def is_ignored_block(name: str) -> bool:
    base = re.sub(r"\s*\([^)]*\)", "", str(name)).strip().lower()
    return re.sub(r"\s+", " ", base) in IGNORED_BLOCKS


class InspectRequest(BaseModel):
    url: str = Field(min_length=20, max_length=500)


class LayerRequest(BaseModel):
    model_id: str = Field(pattern=r"^\d{1,10}$")
    y: int = Field(ge=1, le=512)


class PageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title = ""
        self.in_h1 = False
        self.material_rows: list[dict[str, str]] = []
        self.dimensions: dict[str, str] = {}
        self.table_id = ""
        self.row: dict[str, str] | None = None
        self.cell_class = ""
        self.cell_text = ""
        self.cell_title = ""
        self.in_cell = False
        self.in_b = False
        self.in_material_list = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "h1":
            self.in_h1 = True
        if tag == "table":
            self.table_id = a.get("id", "")
        if tag == "tr":
            self.row = {}
        if tag == "td" and self.row is not None:
            self.cell_class = a.get("class", "")
            self.cell_text = ""
            self.cell_title = ""
            self.in_cell = True
        if tag == "b" and self.in_cell:
            self.in_b = True
        if tag == "div" and "material-list" in a.get("class", "").split():
            self.in_material_list = True
            self.cell_title = a.get("title", "")

    def handle_endtag(self, tag):
        if tag == "h1":
            self.in_h1 = False
        if tag == "b":
            self.in_b = False
        if tag == "div" and self.in_material_list:
            self.in_material_list = False
        if tag == "td" and self.in_cell:
            key = next((part for part in self.cell_class.split() if part in ("name", "count", "parameter", "value")), "")
            text = " ".join(self.cell_text.split())
            if key:
                self.row[key] = text
            if self.cell_title:
                self.row["icon_title"] = self.cell_title
            self.in_cell = False
        if tag == "tr" and self.row is not None:
            row = self.row
            if self.table_id == "materials_list":
                count = row.get("count", "")
                if count.isdigit():
                    label = row.get("name") or row.get("icon_title") or "Material não identificado"
                    self.material_rows.append({"name": label, "count": count})
            elif row.get("parameter", "").lower() in ("width", "height", "depth"):
                self.dimensions[row["parameter"].lower()] = row.get("value", "")
            self.row = None
        if tag == "table":
            self.table_id = ""

    def handle_data(self, data):
        if self.in_h1:
            self.title += data
        if self.in_cell:
            self.cell_text += data


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def validate_url(url: str) -> urllib.parse.ParseResult:
    try:
        parsed = urllib.parse.urlparse(url)
    except ValueError as exc:
        raise HTTPException(400, "Link inválido") from exc
    if parsed.scheme != "https" or parsed.hostname not in {"www.grabcraft.com", "grabcraft.com"}:
        raise HTTPException(400, "Use um link HTTPS de www.grabcraft.com")
    if parsed.username or parsed.password or not parsed.path.startswith("/minecraft/"):
        raise HTTPException(400, "O link precisa apontar para uma construção do GrabCraft")
    return parsed


def inspect_page(url: str) -> dict:
    validate_url(url)
    opener = urllib.request.build_opener(SafeRedirect())
    request = urllib.request.Request(url, headers={"User-Agent": "CC-Tweaked-Blueprint-Inspector/1.0"})
    try:
        with opener.open(request, timeout=18) as response:
            final_url = response.geturl()
            validate_url(final_url)
            raw = response.read(2_000_001)
    except HTTPException:
        raise
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise HTTPException(502, f"Não foi possível abrir o GrabCraft: {exc}") from exc
    if len(raw) > 2_000_000:
        raise HTTPException(502, "A página excedeu o limite de 2 MB")
    parser = PageParser()
    try:
        parser.feed(raw.decode("utf-8", errors="replace"))
    except Exception as exc:
        raise HTTPException(502, "Não consegui interpretar o HTML desta página") from exc
    if not parser.title.strip():
        raise HTTPException(422, "A página não contém uma lista de materiais reconhecida; envie o link direto de Blueprints da construção")
    model_match = re.search(r"assets\.grabcraft\.com/files/products/3dmodel/(\d+)\.json", raw.decode("utf-8", errors="replace"), re.I)
    if not model_match:
        model_match = re.search(r"blueprints\.grabcraft\.com/(\d+)/Y/combined/", raw.decode("utf-8", errors="replace"), re.I)
    if not model_match:
        raise HTTPException(422, "Esta página não publica um modelo 3D voxelizado compatível; não dá para construir automaticamente a partir dela")
    model_id = model_match.group(1)
    model = fetch_model(model_id)
    material_counts: dict[str, int] = {}
    ignored_counts: dict[str, int] = {}
    total = 0
    max_x = max_y = max_z = 0
    for y_key, columns in model.items():
        try:
            y = int(y_key)
        except (ValueError, TypeError):
            continue
        max_y = max(max_y, y)
        for x_key, depths in columns.items():
            try:
                max_x = max(max_x, int(x_key))
            except (ValueError, TypeError):
                continue
            for z_key, block in depths.items():
                try:
                    max_z = max(max_z, int(z_key))
                except (ValueError, TypeError):
                    continue
                name = str(block.get("name", "")).strip()
                if name and not is_ignored_block(name):
                    material_counts[name] = material_counts.get(name, 0) + 1
                    total += 1
                elif name:
                    ignored_counts[name] = ignored_counts.get(name, 0) + 1
    if total == 0:
        raise HTTPException(422, "O modelo 3D está vazio ou usa um formato não reconhecido")
    materials = [{"name": name, "count": str(count)} for name, count in sorted(material_counts.items())]
    match = re.search(r"Block count:\s*([^<]+)", raw.decode("utf-8", errors="replace"), re.I)
    block_count = html.unescape(match.group(1)).strip() if match else ""
    return {
        "title": " ".join(parser.title.split()),
        "url": final_url,
        "model_id": model_id,
        "block_count": total,
        "ignored_block_count": sum(ignored_counts.values()),
        "ignored_materials": [{"name": name, "count": count} for name, count in sorted(ignored_counts.items())],
        "dimensions": {"width": max_x, "height": max_y, "depth": max_z},
        "materials": materials,
        "note": "Este blueprint contém voxels com coordenadas e pode ser enviado à Turtle para construção.",
    }


@lru_cache(maxsize=4)
def fetch_model(model_id: str) -> dict:
    if not re.fullmatch(r"\d{1,10}", model_id):
        raise HTTPException(400, "ID de modelo inválido")
    asset_url = f"https://assets.grabcraft.com/files/products/3dmodel/{model_id}.json"
    request = urllib.request.Request(asset_url, headers={
        "User-Agent": "Mozilla/5.0 (compatible; CC-Tweaked-Blueprint-Inspector/1.0)",
        "Referer": "https://www.grabcraft.com/",
    })
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read(5_000_001)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise HTTPException(502, f"Não foi possível baixar os dados do modelo: {exc}") from exc
    if len(raw) > 5_000_000:
        raise HTTPException(413, "O modelo é grande demais para o modo automático (limite 5 MB)")
    try:
        parsed = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise HTTPException(502, "O GrabCraft retornou JSON de modelo inválido") from exc
    if not isinstance(parsed, dict):
        raise HTTPException(422, "Estrutura do modelo 3D incompatível")
    return parsed


def get_layer(model_id: str, y: int) -> list[dict]:
    model = fetch_model(model_id)
    layer = model.get(str(y), {})
    blocks = []
    for x_key, depths in layer.items():
        for z_key, block in depths.items():
            try:
                x, z = int(x_key), int(z_key)
            except (TypeError, ValueError):
                continue
            name = str(block.get("name", "")).strip()
            if name and not is_ignored_block(name):
                blocks.append({"x": x - 1, "z": z - 1, "name": name})
    blocks.sort(key=lambda item: (item["z"], item["x"]))
    return blocks


def authorize(x_grabcraft_token: str | None):
    if not TOKEN:
        raise HTTPException(503, "Configure GRABCRAFT_TOKEN no processo do serviço")
    if not secrets.compare_digest(x_grabcraft_token or "", TOKEN):
        raise HTTPException(401, "Token do inspetor inválido")


@app.get("/health")
def health():
    return {"ok": True, "service": "grabcraft-terminal"}


@app.get("/install.lua")
def installer():
    return FileResponse(LUA_INSTALLER, media_type="text/plain; charset=utf-8")


@app.get("/grabcraft.lua")
def client_program():
    return FileResponse(LUA_CLIENT, media_type="text/plain; charset=utf-8")


@app.get("/ae2-supply.lua")
def ae2_supply_program():
    return FileResponse(AE2_SUPPLY_CLIENT, media_type="text/plain; charset=utf-8")


@app.post("/inspect")
def inspect(body: InspectRequest, x_grabcraft_token: str | None = Header(default=None)):
    authorize(x_grabcraft_token)
    return inspect_page(body.url)


@app.post("/layer")
def layer(body: LayerRequest, x_grabcraft_token: str | None = Header(default=None)):
    authorize(x_grabcraft_token)
    blocks = get_layer(body.model_id, body.y)
    return {"y": body.y, "blocks": blocks}
