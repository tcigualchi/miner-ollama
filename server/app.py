from __future__ import annotations

import json
import os
import re
import secrets
from collections import Counter, deque
from pathlib import Path
from typing import Any

import requests
from fastapi import FastAPI, Header, HTTPException, Request, Form
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field

BASE = Path(__file__).resolve().parent
PLANS = BASE / "plans"
PLANS.mkdir(exist_ok=True)

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434/api/chat")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen3:4b")
FLEET_TOKEN = os.getenv("FLEET_TOKEN", "CHANGE-ME")
WEB_PASSWORD = os.getenv("WEB_PASSWORD", "CHANGE-ME")

app = FastAPI(title="CC Fleet AI")
templates = Jinja2Templates(directory=str(BASE / "templates"))
commands: deque[dict[str, Any]] = deque()
command_results: dict[str, dict[str, Any]] = {}


class Origin(BaseModel):
    x: int
    y: int
    z: int


class PlanRequest(BaseModel):
    prompt: str = Field(min_length=3, max_length=1000)
    origin: Origin


class CommandRequest(BaseModel):
    controller_id: int
    turtle_id: int
    command: str
    plan_id: str | None = None
    x: int | None = None
    y: int | None = None
    z: int | None = None
    dig: bool = False


def require_fleet_token(x_fleet_token: str | None):
    if not secrets.compare_digest(x_fleet_token or "", FLEET_TOKEN):
        raise HTTPException(status_code=401, detail="invalid fleet token")


ALLOWED = {
    "wall": [
        "minecraft:oak_planks", "minecraft:spruce_planks", "minecraft:birch_planks",
        "minecraft:stone_bricks", "minecraft:bricks", "minecraft:cobblestone"
    ],
    "floor": [
        "minecraft:oak_planks", "minecraft:spruce_planks", "minecraft:birch_planks",
        "minecraft:stone_bricks"
    ],
    "roof": [
        "minecraft:spruce_planks", "minecraft:oak_planks", "minecraft:stone_bricks",
        "minecraft:cobblestone"
    ],
    "window": ["minecraft:glass"],
    "door": ["minecraft:oak_door", "minecraft:spruce_door"],
}


def _extract_json(text: str) -> dict[str, Any]:
    try:
        return json.loads(text)
    except Exception:
        m = re.search(r"\{.*\}", text, re.S)
        if not m:
            raise ValueError("A IA nao retornou JSON.")
        return json.loads(m.group(0))


def ai_spec(prompt: str) -> dict[str, Any]:
    system = """
Voce e um arquiteto para Minecraft/CC:Tweaked.
Converta o pedido em JSON, sem texto extra.
Nao gere coordenadas de blocos. Gere apenas parametros.

Schema:
{
  "name": "nome curto",
  "style": "simple|modern|medieval",
  "width": inteiro 7..25,
  "depth": inteiro 7..25,
  "floors": inteiro 1..3,
  "floor_height": inteiro 3..5,
  "materials": {
    "wall": "minecraft:...",
    "floor": "minecraft:...",
    "roof": "minecraft:...",
    "window": "minecraft:glass",
    "door": "minecraft:oak_door"
  },
  "features": {
    "windows": true,
    "door": true,
    "roof": true,
    "interior_floor": true
  }
}

Use somente materiais vanilla comuns. Prefira:
oak_planks, spruce_planks, birch_planks, stone_bricks, bricks, cobblestone, glass.
A geometria sera criada deterministicamente depois.
"""
    payload = {
        "model": OLLAMA_MODEL,
        "stream": False,
        "format": "json",
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        "options": {"temperature": 0.2},
    }
    r = requests.post(OLLAMA_URL, json=payload, timeout=120)
    r.raise_for_status()
    data = r.json()
    content = data.get("message", {}).get("content", "{}")
    spec = _extract_json(content)
    return sanitize_spec(spec)


def choose(value: str | None, category: str, default: str) -> str:
    return value if value in ALLOWED[category] else default


def sanitize_spec(s: dict[str, Any]) -> dict[str, Any]:
    m = s.get("materials") or {}
    f = s.get("features") or {}
    style = str(s.get("style", "simple")).lower()
    if style not in {"simple", "modern", "medieval"}:
        style = "simple"

    width = max(7, min(25, int(s.get("width", 11))))
    depth = max(7, min(25, int(s.get("depth", 9))))
    if width % 2 == 0: width += 1
    if depth % 2 == 0: depth += 1

    return {
        "name": str(s.get("name", "Casa IA"))[:60],
        "style": style,
        "width": width,
        "depth": depth,
        "floors": max(1, min(3, int(s.get("floors", 1)))),
        "floor_height": max(3, min(5, int(s.get("floor_height", 4)))),
        "materials": {
            "wall": choose(m.get("wall"), "wall", "minecraft:oak_planks"),
            "floor": choose(m.get("floor"), "floor", "minecraft:oak_planks"),
            "roof": choose(m.get("roof"), "roof", "minecraft:spruce_planks"),
            "window": "minecraft:glass",
            "door": choose(m.get("door"), "door", "minecraft:oak_door"),
        },
        "features": {
            "windows": bool(f.get("windows", True)),
            "door": bool(f.get("door", True)),
            "roof": bool(f.get("roof", True)),
            "interior_floor": bool(f.get("interior_floor", True)),
        },
    }


def add(out, seen, x, y, z, block):
    key = (x, y, z)
    # Ultima definicao vence (janela substitui parede, por exemplo).
    if key in seen:
        idx = seen[key]
        out[idx] = {"x": x, "y": y, "z": z, "block": block}
    else:
        seen[key] = len(out)
        out.append({"x": x, "y": y, "z": z, "block": block})


def remove_at(out, seen, x, y, z):
    key = (x, y, z)
    if key not in seen:
        return
    idx = seen.pop(key)
    out[idx] = None


def generate_blueprint(spec: dict[str, Any]) -> list[dict[str, Any]]:
    w, d = spec["width"], spec["depth"]
    floors, fh = spec["floors"], spec["floor_height"]
    mat = spec["materials"]
    feat = spec["features"]
    out: list[dict[str, Any] | None] = []
    seen: dict[tuple[int, int, int], int] = {}

    # Piso de cada andar.
    for floor in range(floors):
        base_y = floor * fh
        if floor == 0 or feat["interior_floor"]:
            for x in range(w):
                for z in range(d):
                    add(out, seen, x, base_y, z, mat["floor"])

        # Paredes.
        for yy in range(base_y + 1, base_y + fh):
            for x in range(w):
                add(out, seen, x, yy, 0, mat["wall"])
                add(out, seen, x, yy, d - 1, mat["wall"])
            for z in range(1, d - 1):
                add(out, seen, 0, yy, z, mat["wall"])
                add(out, seen, w - 1, yy, z, mat["wall"])

        # Porta apenas no terreo, frente (z=0), duas alturas.
        if floor == 0 and feat["door"]:
            cx = w // 2
            remove_at(out, seen, cx, base_y + 1, 0)
            remove_at(out, seen, cx, base_y + 2, 0)

        # Janelas simetricas.
        if feat["windows"]:
            wy = base_y + 2
            for x in range(2, w - 2, max(3, (w - 4)//2 or 3)):
                if not (floor == 0 and x == w // 2):
                    add(out, seen, x, wy, 0, mat["window"])
                    add(out, seen, x, wy, d - 1, mat["window"])
            for z in range(2, d - 2, max(3, (d - 4)//2 or 3)):
                add(out, seen, 0, wy, z, mat["window"])
                add(out, seen, w - 1, wy, z, mat["window"])

    # Teto/telhado.
    top = floors * fh
    if feat["roof"]:
        if spec["style"] == "modern":
            for x in range(w):
                for z in range(d):
                    add(out, seen, x, top, z, mat["roof"])
        else:
            # Telhado em camadas simples, tipo duas aguas aproximado por faixas.
            max_inset = min(w, d) // 2
            for inset in range(max_inset + 1):
                x0, x1 = inset, w - 1 - inset
                z0, z1 = inset, d - 1 - inset
                if x0 > x1 or z0 > z1:
                    break
                yy = top + inset
                for x in range(x0, x1 + 1):
                    add(out, seen, x, yy, z0, mat["roof"])
                    add(out, seen, x, yy, z1, mat["roof"])
                for z in range(z0 + 1, z1):
                    add(out, seen, x0, yy, z, mat["roof"])
                    add(out, seen, x1, yy, z, mat["roof"])
    else:
        for x in range(w):
            for z in range(d):
                add(out, seen, x, top, z, mat["roof"])

    clean = [p for p in out if p is not None]
    clean.sort(key=lambda p: (p["y"], p["z"], p["x"]))
    return clean


def create_plan(prompt: str, origin: dict[str, int]) -> dict[str, Any]:
    spec = ai_spec(prompt)
    placements = generate_blueprint(spec)
    plan_id = secrets.token_hex(4)
    materials = Counter(p["block"] for p in placements)
    plan = {
        "id": plan_id,
        "prompt": prompt,
        "origin": origin,
        "spec": spec,
        "materials": dict(materials),
        "placements": placements,
    }
    (PLANS / f"{plan_id}.json").write_text(
        json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return plan


@app.get("/health")
def health():
    return {"ok": True, "model": OLLAMA_MODEL}


@app.post("/api/plan")
def api_plan(req: PlanRequest, x_fleet_token: str | None = Header(default=None)):
    require_fleet_token(x_fleet_token)
    try:
        return create_plan(req.prompt, req.origin.model_dump())
    except requests.RequestException as e:
        raise HTTPException(status_code=502, detail=f"Ollama indisponivel: {e}")
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/api/plans/{plan_id}")
def get_plan(plan_id: str, x_fleet_token: str | None = Header(default=None)):
    require_fleet_token(x_fleet_token)
    if not re.fullmatch(r"[0-9a-f]{8}", plan_id):
        raise HTTPException(status_code=400, detail="plan id invalido")
    p = PLANS / f"{plan_id}.json"
    if not p.exists():
        raise HTTPException(status_code=404, detail="plan nao encontrado")
    return JSONResponse(json.loads(p.read_text(encoding="utf-8")))


@app.post("/api/commands")
def add_command(req: CommandRequest, x_fleet_token: str | None = Header(default=None)):
    require_fleet_token(x_fleet_token)
    c = req.model_dump()
    c["id"] = secrets.token_hex(6)
    commands.append(c)
    return c


@app.get("/api/commands/next")
def next_command(controller_id: int, x_fleet_token: str | None = Header(default=None)):
    require_fleet_token(x_fleet_token)
    for _ in range(len(commands)):
        c = commands.popleft()
        if c["controller_id"] == controller_id:
            return c
        commands.append(c)
    return JSONResponse(status_code=204, content=None)


@app.post("/api/commands/{command_id}/ack")
async def ack(command_id: str, request: Request, x_fleet_token: str | None = Header(default=None)):
    require_fleet_token(x_fleet_token)
    try:
        body = await request.json()
    except Exception:
        body = {}
    command_results[command_id] = body
    return {"ok": True}


def web_auth(password: str):
    if not secrets.compare_digest(password, WEB_PASSWORD):
        raise HTTPException(status_code=401, detail="senha web incorreta")


@app.get("/", response_class=HTMLResponse)
def index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.post("/web/build", response_class=HTMLResponse)
def web_build(
    request: Request,
    password: str = Form(...),
    controller_id: int = Form(...),
    turtle_id: int = Form(...),
    x: int = Form(...),
    y: int = Form(...),
    z: int = Form(...),
    prompt: str = Form(...),
):
    web_auth(password)
    try:
        plan = create_plan(prompt, {"x": x, "y": y, "z": z})
    except Exception as e:
        return templates.TemplateResponse(
            "index.html", {"request": request, "error": str(e)}
        )

    cmd = {
        "id": secrets.token_hex(6),
        "controller_id": controller_id,
        "turtle_id": turtle_id,
        "command": "build",
        "plan_id": plan["id"],
    }
    commands.append(cmd)

    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "result": {
                "plan_id": plan["id"],
                "spec": plan["spec"],
                "materials": plan["materials"],
                "blocks": len(plan["placements"]),
                "turtle_id": turtle_id,
            },
        },
    )
