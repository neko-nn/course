import sys
import os

sys.stdout.reconfigure(encoding='utf-8')

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html
from fastapi.openapi.utils import get_openapi
from contextlib import asynccontextmanager
import uvicorn

from config import settings
from models import (
    ChatRequest, ChatResponse,
    NPCStatusResponse, NPCListResponse, NPCInfo
)
from agents import get_npc_manager, NPC_ROLES
from state_manager import get_state_manager
from tool.asktool import get_events_since   # 【新增】协作事件流


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("\n" + "=" * 60)
    print("🎮 赛博小镇后端服务启动中...")
    print("=" * 60)
    settings.validate()
    get_npc_manager()
    state_manager = get_state_manager(settings.NPC_UPDATE_INTERVAL)
    await state_manager.start()
    print("\n✅ 所有服务已启动!")
    print(f"📡 API地址: http://127.0.0.1:{settings.API_PORT}")
    print(f"📚 API文档: http://127.0.0.1:{settings.API_PORT}/docs")
    print("=" * 60 + "\n")
    yield
    print("\n🛑 正在关闭服务...")
    await state_manager.stop()


app = FastAPI(
    title=settings.API_TITLE,
    version=settings.API_VERSION,
    description="赛博小镇 - 自研多智能体内核",
    lifespan=lifespan,
    docs_url=None
)


def custom_openapi():
    if app.openapi_schema:
        return app.openapi_schema
    openapi_schema = get_openapi(
        title=app.title, version=app.version,
        description=app.description, routes=app.routes,
    )
    openapi_schema["openapi"] = "3.0.2"
    app.openapi_schema = openapi_schema
    return app.openapi_schema


app.openapi = custom_openapi


@app.get("/docs", include_in_schema=False)
async def custom_swagger_ui_html():
    return get_swagger_ui_html(
        openapi_url=app.openapi_url,
        title=app.title + " - Swagger UI",
        oauth2_redirect_url=app.swagger_ui_oauth2_redirect_url,
        swagger_js_url="https://cdn.bootcdn.net/ajax/libs/swagger-ui/4.15.5/swagger-ui-bundle.min.js",
        swagger_css_url="https://cdn.bootcdn.net/ajax/libs/swagger-ui/4.15.5/swagger-ui.min.css",
    )


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

npc_manager = None
state_manager = None


def get_managers():
    global npc_manager, state_manager
    if npc_manager is None: npc_manager = get_npc_manager()
    if state_manager is None: state_manager = get_state_manager()
    return npc_manager, state_manager


@app.get("/")
async def root():
    return {"service": settings.API_TITLE, "status": "running", "docs": "/docs"}


@app.get("/health")
async def health():
    return {"ok": True}


# ==================== 核心对话接口 ====================
# 【改动】async def -> def。这是可视化能成立的前提：
# 原来的 async def 里跑同步 LLM，会独占事件循环，
# 导游思考的这几十秒内前端轮询 /npcs/interactions 根本得不到响应，
# 改成 def 后 FastAPI 丢进线程池，协作事件才能被实时拉走。
@app.post("/chat", response_model=ChatResponse)
def chat_with_npc(request: ChatRequest):
    npc_mgr, _ = get_managers()
    try:
        response_text = npc_mgr.chat(request.npc_name, request.message)
        npc_title = NPC_ROLES.get(request.npc_name, {}).get("title", "NPC")
        return ChatResponse(
            npc_name=request.npc_name,
            npc_title=npc_title,
            message=response_text,
            success=True
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/npcs", response_model=NPCListResponse)
def list_npcs():   # 【改动】async def -> def
    npc_mgr, _ = get_managers()
    npcs_data = npc_mgr.get_all_npcs()
    npcs = [NPCInfo(**npc, activity="", available=True) for npc in npcs_data]
    return NPCListResponse(npcs=npcs, total=len(npcs))


@app.get("/npcs/status", response_model=NPCStatusResponse)
def get_npcs_status():   # 【改动】async def -> def
    _, state_mgr = get_managers()
    state = state_mgr.get_current_state()
    return NPCStatusResponse(
        dialogues=state["dialogues"],
        last_update=state["last_update"],
        next_update_in=state["next_update_in"]
    )


# 【新增】协作事件流。必须声明在 /npcs/{npc_name} 之前，否则会被路径参数吞掉。
@app.get("/npcs/interactions")
def get_npc_interactions(since: int = 0):
    """导游咨询其他 NPC 的实时事件（asking / answered），前端增量轮询"""
    return get_events_since(since)


@app.post("/npcs/status/refresh")
async def refresh_npcs_status():
    _, state_mgr = get_managers()
    await state_mgr.force_update()
    return {"message": "NPC状态已刷新", "dialogues": state_mgr.get_current_state()["dialogues"]}


@app.get("/npcs/{npc_name}")
def get_npc_info(npc_name: str):   # 【改动】async def -> def
    npc_mgr, _ = get_managers()
    info = npc_mgr.get_npc_info(npc_name)
    if not info:
        raise HTTPException(status_code=404, detail="NPC 不存在")
    return info


@app.get("/npcs/{npc_name}/affinity")
def get_npc_affinity(npc_name: str):   # 【改动】async def -> def
    npc_mgr, _ = get_managers()
    return npc_mgr.get_affinity(npc_name)


@app.get("/affinities")
def get_all_affinities():   # 【改动】async def -> def
    npc_mgr, _ = get_managers()
    return npc_mgr.get_all_affinities()


@app.put("/npcs/{npc_name}/affinity")
def set_npc_affinity(npc_name: str, affinity: float):   # 【改动】async def -> def
    npc_mgr, _ = get_managers()
    npc_mgr.set_npc_affinity(npc_name, affinity)
    return {"message": f"已设置 {npc_name} 好感度为 {affinity}"}


@app.get("/npcs/{npc_name}/memories")
def get_npc_memories(npc_name: str, limit: int = 10):   # 【改动】async def -> def
    npc_mgr, _ = get_managers()
    return {"npc_name": npc_name, "memories": npc_mgr.get_npc_memories(npc_name, limit)}


@app.delete("/npcs/{npc_name}/memories")
def clear_npc_memories(npc_name: str):   # 【改动】async def -> def
    npc_mgr, _ = get_managers()
    npc_mgr.clear_npc_memory(npc_name)
    return {"message": f"已清空 {npc_name} 的记忆"}


if __name__ == "__main__":
    print("\n🚀 启动赛博小镇后端服务...")
    # 【改动】关掉热重载：改 .gd 文件会重启后端，正在飞的请求直接断成 HTTP 0
    uvicorn.run("main:app", host=settings.API_HOST, port=settings.API_PORT, reload=False)