"""导游 ask_npc 工具
【新增】多智能体协作事件流：把「梓涵问了谁、问了什么、对方答了什么」实时暴露给前端，
        玩家才能在等待回复时看到真实的协作过程，而不是一行「等待回复...」。
        原有的 state_manager 表演缓存接口完全保留，不破坏任何已有逻辑。
"""
import threading
import time
from typing import Dict, Any, List, Optional

from .base import Tool, ToolParameter
from core.bus import MessageBus
from core.message import Message

# ========= 旧的全局事件缓存：state_manager 每 30 秒的表演逻辑仍在用，原样保留 =========
_npc_interact_event: Optional[dict] = None


def set_npc_interact_event(sender: str, target: str, ask_text: str, reply_text: str):
    global _npc_interact_event
    _npc_interact_event = {
        "sender": sender,
        "target": target,
        "ask_text": ask_text,
        "reply_text": reply_text,
    }


def pop_npc_interact_event():
    global _npc_interact_event
    e = _npc_interact_event
    _npc_interact_event = None
    return e


# ========= 【新增】追加式协作事件日志（线程安全，前端按 seq 增量拉取） =========
_lock = threading.Lock()
_events: List[dict] = []
_seq: int = 0
MAX_EVENTS = 240


def _push(phase: str, target: str, question: str, reply: str = "",
          step: int = 0, ok: bool = True) -> int:
    """写入一条协作事件。phase: asking(已发起) / answered(已回复)"""
    global _seq
    with _lock:
        _seq += 1
        _events.append({
            "seq": _seq,
            "phase": phase,
            "guide": "梓涵",
            "target": target,
            "question": question,
            "reply": reply,
            "step": step,
            "ok": ok,
            "ts": time.time(),
        })
        if len(_events) > MAX_EVENTS:
            del _events[:len(_events) - MAX_EVENTS]
        return _seq


def get_events_since(since: int = 0) -> Dict[str, Any]:
    """前端轮询入口：只返回 seq > since 的新事件"""
    with _lock:
        out = [e for e in _events if e["seq"] > since]
        return {"events": out, "last_seq": _seq}


# ========= 【新增】推诿检测：专家把球踢回导游时的兜底 =========
_DEFLECT_WORDS = ("找导游", "找梓涵", "问梓涵", "去引导台", "咨询导游")


def _looks_like_deflect(reply: str) -> bool:
    """专家明明是被导游咨询，却回「你去找导游/去引导台」。"""
    r = (reply or "").strip()
    if len(r) > 80:  # 长回复里顺带提一句不算推诿
        return False
    return any(w in r for w in _DEFLECT_WORDS)


# =============================================================
class AskNPCTool(Tool):
    def __init__(self, bus):
        # name 必须是 ask_npc：agents.py 的导游提示词里写的就是这个名字
        super().__init__(name="ask_npc", description="导游npc询问其他npc的工具")
        self.bus = bus

    def run(self, parameters: Dict[str, Any]) -> str:
        name = parameters.get("npc_name") or ""
        question = parameters.get("question") or ""

        # 【新增·关键】在真正发起通信「之前」就推事件，
        # 这样前端能立刻看到「梓涵正在前往子涵」，而不是等专家想完才知道。
        step = _push("asking", name, question)

        # 【新增】给问题加上身份标注：专家此前不知道提问者就是导游，
        # 会照着"让游客去找导游"的规则把问题踢回来，形成"导游让导游找导游"。
        framed = f"【导游梓涵现场咨询】{question}。请直接给出你专业范围内的一句话结论，不要让提问者去找导游。"
        msg = Message(sender="梓涵", receiver=name, msg_type="query", content=framed)
        reply = self.bus.send(msg)

        # 【新增】兜底：真的被推诿了就带上强硬指令再问一次，只重试一次
        if _looks_like_deflect(reply):
            print(f"  [推诿检测] {name} 让导游去找导游，重问一次")
            retry_msg = Message(
                sender="梓涵", receiver=name, msg_type="query",
                content=(
                    f"【导游梓涵现场咨询·第二次】{question}。"
                    "注意：提问者就是导游梓涵本人，你不能让他去找导游。"
                    "只回答你专业内的一句话结论。"
                )
            )
            retry_reply = self.bus.send(retry_msg)
            if retry_reply and not _looks_like_deflect(retry_reply):
                reply = retry_reply

        ok = not str(reply).startswith(("权限拒绝", "接收方不在线", "错误", "执行工具失败"))
        # 【新增】回复落地，前端把该专家标记为已回复并弹出真实答案
        _push("answered", name, question, reply, step, ok)

        # 旧逻辑保留：给 30 秒批量表演用
        set_npc_interact_event(sender="梓涵", target=name,
                               ask_text=question, reply_text=reply)
        return reply

    def get_parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="npc_name",
                type="string",
                description="npc名字，例如：子涵",
                required=True
            ),
            ToolParameter(
                name="question",
                type="string",
                description="需要询问的问题",
                required=True
            ),
        ]