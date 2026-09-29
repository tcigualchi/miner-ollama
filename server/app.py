"""CC Fleet OS - API, task coordinator and real-time dashboard."""
from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Literal

from fastapi import Cookie, FastAPI, Header, HTTPException, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field, field_validator

BASE = Path(__file__).resolve().parent
ROOT = BASE.parent
DATA = BASE / "data"
DATA.mkdir(exist_ok=True)
DB = DATA / "fleet.db"
WEB_PASSWORD = os.getenv("WEB_PASSWORD")
ENROLLMENT_TOKEN = os.getenv("FLEET_ENROLLMENT_TOKEN", os.getenv("FLEET_TOKEN"))
PLAYER_BEACON_TOKEN = os.getenv("PLAYER_BEACON_TOKEN", ENROLLMENT_TOKEN)
OFFLINE_AFTER = int(os.getenv("OFFLINE_AFTER_SECONDS", "20"))
BEACON_STALE_AFTER = int(os.getenv("BEACON_STALE_AFTER_SECONDS", "30"))
if not WEB_PASSWORD or WEB_PASSWORD == "CHANGE-ME":
    raise RuntimeError("Defina WEB_PASSWORD com uma senha forte antes de iniciar o servidor.")
if not ENROLLMENT_TOKEN or ENROLLMENT_TOKEN == "CHANGE-ME":
    raise RuntimeError("Defina FLEET_ENROLLMENT_TOKEN com um token forte antes de iniciar o servidor.")
if not PLAYER_BEACON_TOKEN or PLAYER_BEACON_TOKEN == "CHANGE-ME" or PLAYER_BEACON_TOKEN == ENROLLMENT_TOKEN:
    raise RuntimeError("Defina PLAYER_BEACON_TOKEN diferente do token de cadastro.")

app = FastAPI(title="CC Fleet OS", version="3.0.3")
templates = Jinja2Templates(directory=str(BASE / "templates"))
app.mount("/agent", StaticFiles(directory=str(ROOT / "turtle")), name="agent")


@contextmanager
def db():
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    try:
        yield con
        con.commit()
    finally:
        con.close()


def now() -> int:
    return int(time.time())


def dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def loads(value: str | None, default: Any) -> Any:
    try:
        return json.loads(value or "")
    except (TypeError, json.JSONDecodeError):
        return default


def init_db():
    with db() as con:
        con.executescript("""
        CREATE TABLE IF NOT EXISTS agents (
          id TEXT PRIMARY KEY, computer_id INTEGER, name TEXT NOT NULL,
          token_hash TEXT NOT NULL, dimension TEXT NOT NULL DEFAULT 'minecraft:overworld',
          heading TEXT NOT NULL DEFAULT 'unknown', state TEXT NOT NULL DEFAULT 'OFFLINE',
          x REAL, y REAL, z REAL, fuel TEXT, inventory TEXT NOT NULL DEFAULT '{}',
          capabilities TEXT NOT NULL DEFAULT '[]', current_task_id TEXT,
          base TEXT NOT NULL DEFAULT '{}', last_seen INTEGER NOT NULL, created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS tasks (
          id TEXT PRIMARY KEY, parent_id TEXT, title TEXT NOT NULL, kind TEXT NOT NULL,
          payload TEXT NOT NULL, state TEXT NOT NULL, assigned_agent_id TEXT,
          progress INTEGER NOT NULL DEFAULT 0, message TEXT, checkpoint TEXT NOT NULL DEFAULT '{}',
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, completed_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT, agent_id TEXT, task_id TEXT,
          level TEXT NOT NULL, message TEXT NOT NULL, data TEXT NOT NULL DEFAULT '{}', created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS players (
          name TEXT PRIMARY KEY, x REAL NOT NULL, y REAL NOT NULL, z REAL NOT NULL,
          dimension TEXT NOT NULL DEFAULT 'minecraft:overworld', updated_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY, expires_at INTEGER NOT NULL
        );
        """)


init_db()


class Hub:
    def __init__(self):
        self.clients: set[WebSocket] = set()

    async def publish(self, event: str, data: dict[str, Any]):
        message = dumps({"event": event, "data": data, "at": now()})
        for client in list(self.clients):
            try:
                await client.send_text(message)
            except Exception:
                self.clients.discard(client)


hub = Hub()


def log(agent_id: str | None, level: str, message: str, task_id: str | None = None, data: dict[str, Any] | None = None):
    with db() as con:
        con.execute(
            "INSERT INTO logs(agent_id,task_id,level,message,data,created_at) VALUES(?,?,?,?,?,?)",
            (agent_id, task_id, level, message[:500], dumps(data or {}), now()),
        )


def agent_row(row: sqlite3.Row) -> dict[str, Any]:
    item = dict(row)
    item["inventory"] = loads(item.pop("inventory"), {})
    item["capabilities"] = loads(item.pop("capabilities"), [])
    item["base"] = loads(item.pop("base"), {})
    item["online"] = now() - item["last_seen"] <= OFFLINE_AFTER
    if not item["online"]:
        item["state"] = "OFFLINE"
    return item


def task_row(row: sqlite3.Row) -> dict[str, Any]:
    item = dict(row)
    item["payload"] = loads(item["payload"], {})
    item["checkpoint"] = loads(item["checkpoint"], {})
    return item


def require_web(session_id: str | None):
    if not session_id:
        raise HTTPException(401, "autenticação necessária")
    with db() as con:
        valid = con.execute("SELECT 1 FROM sessions WHERE id=? AND expires_at>?", (session_id, now())).fetchone()
    if not valid:
        raise HTTPException(401, "sessão expirada")


def require_agent(agent_id: str, token: str | None):
    if not token:
        raise HTTPException(401, "token do agente ausente")
    with db() as con:
        row = con.execute("SELECT token_hash FROM agents WHERE id=?", (agent_id,)).fetchone()
    if not row or not secrets.compare_digest(row["token_hash"], hashlib.sha256(token.encode()).hexdigest()):
        raise HTTPException(401, "token do agente inválido")


class Register(BaseModel):
    computer_id: int
    name: str = Field(min_length=1, max_length=64)
    dimension: str = "minecraft:overworld"
    capabilities: list[str] = Field(default_factory=list)
    base: dict[str, Any] = Field(default_factory=dict)

    @field_validator("base", mode="before")
    @classmethod
    def empty_base(cls, value: Any):
        return {} if value == [] else value


class Heartbeat(BaseModel):
    state: str = "IDLE"
    x: float | None = None
    y: float | None = None
    z: float | None = None
    dimension: str = "minecraft:overworld"
    heading: Literal["north", "east", "south", "west", "unknown"] = "unknown"
    fuel: int | str | None = None
    inventory: dict[str, int] = Field(default_factory=dict)
    current_task_id: str | None = None
    capabilities: list[str] = Field(default_factory=list)
    base: dict[str, Any] = Field(default_factory=dict)

    @field_validator("inventory", mode="before")
    @classmethod
    def lua_empty_table(cls, value: Any):
        return {} if value == [] else value

    @field_validator("base", mode="before")
    @classmethod
    def lua_empty_base(cls, value: Any):
        return {} if value == [] else value


class TaskCreate(BaseModel):
    prompt: str = Field(min_length=3, max_length=500)
    agent_ids: list[str] = Field(default_factory=list)
    origin: dict[str, float] | None = None


class Progress(BaseModel):
    state: Literal["RUNNING", "PAUSED", "DONE", "FAILED", "BLOCKED"]
    progress: int = Field(ge=0, le=100)
    message: str = Field(max_length=500)
    checkpoint: dict[str, Any] = Field(default_factory=dict)
    log_level: Literal["INFO", "WARN", "ERROR"] = "INFO"

    @field_validator("checkpoint", mode="before")
    @classmethod
    def lua_empty_checkpoint(cls, value: Any):
        return {} if value == [] else value


class PlayerLocation(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    x: float
    y: float
    z: float
    dimension: str = "minecraft:overworld"


class LegacyStatus(BaseModel):
    controller_id: int
    turtle_id: int
    name: str | None = None
    label: str | None = None
    state: str = "IDLE"
    x: float | None = None
    y: float | None = None
    z: float | None = None
    fuel: int | str | None = None
    inventory: dict[str, int] = Field(default_factory=dict)
    extra: Any = Field(default_factory=dict)
    timestamp: int | None = None

    @field_validator("inventory", mode="before")
    @classmethod
    def legacy_empty_inventory(cls, value: Any):
        return {} if value == [] else value


def parse_task(prompt: str, origin: dict[str, float] | None) -> tuple[str, str, dict[str, Any]]:
    text = prompt.strip()
    lower = text.lower()
    numbers = [int(value) for value in re.findall(r"(\d+)", lower)]
    if re.search(r"venha|vá?i? até mim|vá até mim|siga[- ]?me|me encontre", lower):
        return "follow_player", "Encontrar o jogador", {"player": None, "recalculate_seconds": 4, "dig": True}
    if "volte" in lower and ("base" in lower or "casa" in lower):
        return "return_base", "Retornar à base", {}
    if "parede" in lower:
        length, height = (numbers + [10, 3])[:2]
        if not 1 <= length <= 128 or not 1 <= height <= 32:
            raise HTTPException(422, "Parede limitada a 128 blocos de comprimento e 32 de altura.")
        material = "minecraft:stone" if "pedra" in lower else "minecraft:oak_planks"
        return "build_wall", f"Construir parede {length}x{height}", {"length": length, "height": height, "material": material, "origin": origin}
    if "casa" in lower:
        width, depth = (numbers + [11, 9])[:2]
        if not 3 <= width <= 64 or not 3 <= depth <= 64:
            raise HTTPException(422, "Casa limitada a dimensões entre 3 e 64 blocos.")
        material = "minecraft:oak_planks" if ("carvalho" in lower or "madeira" in lower) else "minecraft:cobblestone"
        return "build_house", f"Construir casa {width}x{depth}", {"width": width, "depth": depth, "material": material, "origin": origin}
    if "ponte" in lower:
        length = (numbers + [16])[0]
        if not 1 <= length <= 128:
            raise HTTPException(422, "Ponte limitada a 128 blocos.")
        return "build_bridge", f"Construir ponte de {length} blocos", {"length": length, "material": "minecraft:oak_planks", "origin": origin}
    if any(word in lower for word in ("mine", "minere", "minerar", "diamante")):
        width, depth = (numbers + [16, 16])[:2]
        if not 1 <= width <= 128 or not 1 <= depth <= 128:
            raise HTTPException(422, "Área limitada a 128 por 128 blocos.")
        return "mine_area", f"Minerar área {width}x{depth}", {"width": width, "depth": depth, "height": 2, "seek_diamond": "diamante" in lower, "origin": origin}
    if any(word in lower for word in ("quebre", "limpe", "escave", "remova")):
        width, depth = (numbers + [8, 8])[:2]
        if not 1 <= width <= 128 or not 1 <= depth <= 128:
            raise HTTPException(422, "Área limitada a 128 por 128 blocos.")
        return "clear_area", f"Limpar área {width}x{depth}", {"width": width, "depth": depth, "height": 2, "origin": origin}
    if "vá" in lower or "ir " in lower:
        coords = re.findall(r"[-+]?\d+(?:\.\d+)?", text)
        if len(coords) >= 3:
            return "goto", "Navegar até coordenadas", {"x": float(coords[-3]), "y": float(coords[-2]), "z": float(coords[-1]), "dig": True}
    raise HTTPException(422, "Não entendi a tarefa. Use: venha até mim, mine 20x20, parede 30x10, casa 20x20, ponte 15, limpe 10x10 ou vá para X Y Z.")


def choose_agents(requested: list[str], needed: int) -> list[dict[str, Any]]:
    with db() as con:
        rows = [agent_row(row) for row in con.execute("SELECT * FROM agents").fetchall()]
    available = [item for item in rows if item["online"] and not item["current_task_id"]
                 and "move" in item["capabilities"]]
    if requested:
        allowed = set(requested)
        available = [item for item in available if item["id"] in allowed]
    return sorted(available, key=lambda item: (item["fuel"] in (None, 0, "0"), item["id"]))[:needed]


def create_task(prompt: str, requested_agents: list[str], origin: dict[str, float] | None) -> dict[str, Any]:
    kind, title, payload = parse_task(prompt, origin)
    if len(requested_agents) > 1 and kind not in {"mine_area", "clear_area"}:
        raise HTTPException(422, "Distribuição em equipe está disponível para mineração e limpeza de áreas. Escolha uma Turtle para esta tarefa.")
    collaboration = kind in {"mine_area", "clear_area"} and len(requested_agents) != 1
    wanted = len(requested_agents) if requested_agents else (4 if collaboration else 1)
    agents = choose_agents(requested_agents, wanted)
    if not agents:
        raise HTTPException(409, "Nenhuma Turtle online e disponível foi encontrada.")
    if payload.get("origin") is None and agents[0].get("x") is not None:
        payload["origin"] = {"x": agents[0]["x"], "y": agents[0]["y"], "z": agents[0]["z"]}
    if collaboration and payload.get("origin") is None:
        raise HTTPException(409, "A tarefa em equipe precisa de uma posição GPS válida na primeira Turtle selecionada.")
    parent_id = secrets.token_hex(8)
    task_ids: list[str] = []
    with db() as con:
        if len(agents) > 1:
            con.execute("INSERT INTO tasks(id,parent_id,title,kind,payload,state,created_at,updated_at) VALUES(?,?,?,?,?,'GROUP',?,?)",
                        (parent_id, None, title, kind, dumps(payload), now(), now()))
        for index, agent in enumerate(agents):
            task_id = secrets.token_hex(8)
            child = dict(payload)
            if len(agents) > 1 and kind in {"mine_area", "clear_area"}:
                child["partition"] = {"index": index, "total": len(agents), "axis": "x"}
            con.execute("INSERT INTO tasks(id,parent_id,title,kind,payload,state,assigned_agent_id,created_at,updated_at) VALUES(?,?,?,?,?,'QUEUED',?,?,?)",
                        (task_id, parent_id if len(agents) > 1 else None, title, kind, dumps(child), agent["id"], now(), now()))
            task_ids.append(task_id)
    log(None, "INFO", f"Tarefa criada: {title}", parent_id, {"agents": [agent["id"] for agent in agents]})
    return {"id": parent_id if len(agents) > 1 else task_ids[0], "title": title, "kind": kind, "agent_ids": [agent["id"] for agent in agents], "task_ids": task_ids}


@app.get("/health")
def health():
    return {"ok": True, "version": app.version}


@app.get("/", response_class=HTMLResponse)
def index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.post("/api/auth/login")
def login(request: Request, password: str = Header(default="", alias="X-Web-Password")):
    if not secrets.compare_digest(password, WEB_PASSWORD):
        raise HTTPException(401, "senha inválida")
    session_id = secrets.token_urlsafe(32)
    with db() as con:
        con.execute("DELETE FROM sessions WHERE expires_at<?", (now(),))
        con.execute("INSERT INTO sessions(id,expires_at) VALUES(?,?)", (session_id, now() + 8 * 3600))
    response = Response(status_code=204)
    response.set_cookie("ccfleet_session", session_id, max_age=8 * 3600, httponly=True, samesite="strict", secure=request.url.scheme == "https")
    return response


@app.post("/api/status")
async def legacy_status(body: LegacyStatus, x_fleet_token: str | None = Header(default=None)):
    """Accept old central-computer heartbeats during migration to the direct agent."""
    if not secrets.compare_digest(x_fleet_token or "", ENROLLMENT_TOKEN):
        raise HTTPException(401, "token legado inv\u00e1lido")
    agent_id = f"cc-{body.turtle_id}"
    name = (body.name or body.label or f"Turtle {body.turtle_id}")[:64]
    with db() as con:
        con.execute("""INSERT INTO agents(id,computer_id,name,token_hash,dimension,heading,state,x,y,z,fuel,
                       inventory,capabilities,last_seen,created_at)
                       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                       ON CONFLICT(id) DO UPDATE SET name=excluded.name,state=excluded.state,
                       x=excluded.x,y=excluded.y,z=excluded.z,fuel=excluded.fuel,
                       inventory=excluded.inventory,capabilities=excluded.capabilities,last_seen=excluded.last_seen""",
                    (agent_id, body.turtle_id, name, "legacy", "minecraft:overworld", "unknown", body.state,
                     body.x, body.y, body.z, str(body.fuel), dumps(body.inventory),
                     dumps(["legacy-rednet"]), now(), now()))
    await hub.publish("agent_heartbeat", {"id": agent_id, "legacy": True})
    return {"ok": True, "mode": "monitor-only"}


@app.get("/api/commands/next")
def legacy_no_commands(controller_id: int, x_fleet_token: str | None = Header(default=None)):
    """Legacy central computers poll this endpoint; tasks now go to direct agents."""
    if not secrets.compare_digest(x_fleet_token or "", ENROLLMENT_TOKEN):
        raise HTTPException(401, "token legado inv\u00e1lido")
    return Response(status_code=204)


@app.post("/api/auth/logout", status_code=204)
def logout(ccfleet_session: str | None = Cookie(default=None)):
    if ccfleet_session:
        with db() as con:
            con.execute("DELETE FROM sessions WHERE id=?", (ccfleet_session,))
    response = Response(status_code=204)
    response.delete_cookie("ccfleet_session")
    return response


@app.post("/api/agents/register")
async def register_agent(body: Register, x_enrollment_token: str | None = Header(default=None)):
    if not secrets.compare_digest(x_enrollment_token or "", ENROLLMENT_TOKEN):
        raise HTTPException(401, "token de cadastro inválido")
    agent_id = f"cc-{body.computer_id}"
    token = secrets.token_urlsafe(32)
    with db() as con:
        old = con.execute("SELECT id FROM agents WHERE id=?", (agent_id,)).fetchone()
        con.execute("""INSERT INTO agents(id,computer_id,name,token_hash,dimension,capabilities,base,last_seen,created_at)
                       VALUES(?,?,?,?,?,?,?,?,?)
                       ON CONFLICT(id) DO UPDATE SET name=excluded.name,dimension=excluded.dimension,
                       capabilities=excluded.capabilities,base=excluded.base,last_seen=excluded.last_seen""",
                    (agent_id, body.computer_id, body.name, hashlib.sha256(token.encode()).hexdigest(), body.dimension,
                     dumps(body.capabilities), dumps(body.base), now(), now()))
        if old:
            con.execute("UPDATE agents SET token_hash=? WHERE id=?", (hashlib.sha256(token.encode()).hexdigest(), agent_id))
    log(agent_id, "INFO", "Agente registrado", data={"name": body.name})
    await hub.publish("agent_registered", {"id": agent_id, "name": body.name})
    return {"agent_id": agent_id, "agent_token": token, "version": app.version, "poll_seconds": 2}


@app.post("/api/agents/{agent_id}/heartbeat")
async def heartbeat(agent_id: str, body: Heartbeat, x_agent_token: str | None = Header(default=None)):
    require_agent(agent_id, x_agent_token)
    with db() as con:
        con.execute("""UPDATE agents SET state=?,x=?,y=?,z=?,dimension=?,heading=?,fuel=?,inventory=?,
                       current_task_id=?,capabilities=?,base=?,last_seen=? WHERE id=?""",
                    (body.state, body.x, body.y, body.z, body.dimension, body.heading, str(body.fuel),
                     dumps(body.inventory), body.current_task_id, dumps(body.capabilities), dumps(body.base), now(), agent_id))
    await hub.publish("agent_heartbeat", {"id": agent_id})
    return {"ok": True}


@app.get("/api/agents/{agent_id}/tasks/next")
def next_task(agent_id: str, x_agent_token: str | None = Header(default=None)):
    require_agent(agent_id, x_agent_token)
    with db() as con:
        row = con.execute("SELECT * FROM tasks WHERE assigned_agent_id=? AND state='QUEUED' ORDER BY created_at LIMIT 1", (agent_id,)).fetchone()
        if not row:
            return Response(status_code=204)
        con.execute("UPDATE tasks SET state='RUNNING',updated_at=? WHERE id=?", (now(), row["id"]))
        con.execute("UPDATE agents SET current_task_id=?,state='WORKING' WHERE id=?", (row["id"], agent_id))
    return task_row(row)


@app.get("/api/agents/{agent_id}/tasks/{task_id}")
def get_task(agent_id: str, task_id: str, x_agent_token: str | None = Header(default=None)):
    require_agent(agent_id, x_agent_token)
    with db() as con:
        row = con.execute("SELECT * FROM tasks WHERE id=? AND assigned_agent_id=? AND state IN ('RUNNING','PAUSED','BLOCKED')", (task_id, agent_id)).fetchone()
    if not row:
        raise HTTPException(404, "tarefa não encontrada ou já concluída")
    return task_row(row)


@app.post("/api/agents/{agent_id}/tasks/{task_id}/progress")
async def task_progress(agent_id: str, task_id: str, body: Progress, x_agent_token: str | None = Header(default=None)):
    require_agent(agent_id, x_agent_token)
    with db() as con:
        task = con.execute("SELECT assigned_agent_id FROM tasks WHERE id=?", (task_id,)).fetchone()
        if not task or task["assigned_agent_id"] != agent_id:
            raise HTTPException(404, "tarefa não pertence ao agente")
        completed = now() if body.state in {"DONE", "FAILED"} else None
        con.execute("UPDATE tasks SET state=?,progress=?,message=?,checkpoint=?,updated_at=?,completed_at=? WHERE id=?",
                    (body.state, body.progress, body.message, dumps(body.checkpoint), now(), completed, task_id))
        if body.state in {"DONE", "FAILED", "BLOCKED"}:
            state = "IDLE" if body.state == "DONE" else ("ERROR" if body.state == "FAILED" else "BLOCKED")
            con.execute("UPDATE agents SET current_task_id=NULL,state=? WHERE id=?", (state, agent_id))
    log(agent_id, body.log_level, body.message, task_id, {"progress": body.progress, "checkpoint": body.checkpoint})
    await hub.publish("task_progress", {"task_id": task_id, "agent_id": agent_id, "state": body.state, "progress": body.progress})
    return {"ok": True}


@app.get("/api/agents/{agent_id}/player-target")
def player_target(agent_id: str, x_agent_token: str | None = Header(default=None)):
    require_agent(agent_id, x_agent_token)
    with db() as con:
        row = con.execute("SELECT * FROM players ORDER BY updated_at DESC LIMIT 1").fetchone()
    if not row:
        raise HTTPException(404, "nenhum beacon de jogador ativo")
    if now() - row["updated_at"] > BEACON_STALE_AFTER:
        raise HTTPException(409, "beacon do jogador está offline; atualize sua posição no Pocket Computer")
    return dict(row)


@app.post("/api/player/location")
async def player_location(body: PlayerLocation, x_player_token: str | None = Header(default=None)):
    if not secrets.compare_digest(x_player_token or "", PLAYER_BEACON_TOKEN):
        raise HTTPException(401, "token do beacon inválido")
    with db() as con:
        con.execute("""INSERT INTO players(name,x,y,z,dimension,updated_at) VALUES(?,?,?,?,?,?)
                       ON CONFLICT(name) DO UPDATE SET x=excluded.x,y=excluded.y,z=excluded.z,
                       dimension=excluded.dimension,updated_at=excluded.updated_at""",
                    (body.name, body.x, body.y, body.z, body.dimension, now()))
    await hub.publish("player_location", body.model_dump())
    return {"ok": True}


@app.get("/api/dashboard")
def dashboard(ccfleet_session: str | None = Cookie(default=None)):
    require_web(ccfleet_session)
    with db() as con:
        agents = [agent_row(row) for row in con.execute("SELECT * FROM agents ORDER BY name").fetchall()]
        tasks = [task_row(row) for row in con.execute("SELECT * FROM tasks ORDER BY updated_at DESC LIMIT 100").fetchall()]
        logs = [dict(row) | {"data": loads(row["data"], {})} for row in con.execute("SELECT * FROM logs ORDER BY id DESC LIMIT 150").fetchall()]
        players = [dict(row) for row in con.execute("SELECT * FROM players WHERE updated_at>=? ORDER BY updated_at DESC", (now()-BEACON_STALE_AFTER,)).fetchall()]
    return {"agents": agents, "tasks": tasks, "logs": logs, "players": players, "offline_after": OFFLINE_AFTER}


@app.post("/api/tasks")
async def add_task(body: TaskCreate, ccfleet_session: str | None = Cookie(default=None)):
    require_web(ccfleet_session)
    task = create_task(body.prompt, body.agent_ids, body.origin)
    await hub.publish("task_created", task)
    return task


@app.get("/api/tasks")
def list_tasks(ccfleet_session: str | None = Cookie(default=None)):
    require_web(ccfleet_session)
    with db() as con:
        return {"tasks": [task_row(row) for row in con.execute("SELECT * FROM tasks ORDER BY updated_at DESC LIMIT 100").fetchall()]}


@app.websocket("/ws/dashboard")
async def dashboard_ws(websocket: WebSocket):
    session_id = websocket.cookies.get("ccfleet_session")
    try:
        require_web(session_id)
    except HTTPException:
        await websocket.close(code=4401)
        return
    await websocket.accept()
    hub.clients.add(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        hub.clients.discard(websocket)


@app.get("/bootstrap/install.lua", response_class=Response)
def bootstrap_script(request: Request):
    content = (ROOT / "bootstrap" / "install.lua").read_text(encoding="utf-8")
    return Response(content, media_type="text/plain; charset=utf-8")


@app.get("/bootstrap/beacon.lua", response_class=Response)
def beacon_script():
    content = (ROOT / "pocket" / "beacon.lua").read_text(encoding="utf-8")
    return Response(content, media_type="text/plain; charset=utf-8")


@app.get("/api/agent/manifest")
def agent_manifest(agent_id: str, x_agent_token: str | None = Header(default=None)):
    require_agent(agent_id, x_agent_token)
    files = []
    agent_files = [
        "agent.lua", "startup.lua", "lib/state.lua", "lib/net.lua", "lib/gps.lua",
        "lib/movement.lua", "lib/navigation.lua", "lib/inventory.lua", "lib/fuel.lua",
        "lib/tasks.lua", "lib/mining.lua", "lib/building.lua", "lib/update.lua",
    ]
    for relative in agent_files:
        path = ROOT / "turtle" / relative
        files.append({"path": relative})
    return {"version": app.version, "files": files}


@app.get("/api/bootstrap/health")
def bootstrap_health():
    return {"version": app.version, "agent_url": "/agent/"}
