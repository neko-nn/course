"""NPC状态管理器 - 定时批量更新NPC对话"""
import asyncio
import time
from datetime import datetime
from typing import Dict, Optional
from batch_generator import get_batch_generator
from tool.asktool import pop_npc_interact_event


class NPCStateManager:
    def __init__(self, update_interval: int = 30):
        self.update_interval = update_interval
        self.batch_generator = get_batch_generator()
        # 【改动】先用预设兜底，服务一起来前端就有碎碎念，不用等第一次 LLM
        self.current_dialogues: Dict[str, str] = self.batch_generator._get_preset_dialogues()
        self.last_update: Optional[datetime] = datetime.now()
        self.next_update_time: Optional[datetime] = None
        self._update_task: Optional[asyncio.Task] = None
        self._running = False
        print(f"📊 NPC状态管理器初始化完成 (更新间隔: {update_interval}秒)")

    async def start(self):
        if self._running:
            return
        self._running = True
        print("🚀 启动NPC状态自动更新...")
        # 【改动】首次更新丢后台，别挡住 uvicorn 绑端口
        asyncio.create_task(self._update_npc_states())
        self._update_task = asyncio.create_task(self._auto_update_loop())

    async def stop(self):
        if not self._running:
            return
        self._running = False
        if self._update_task:
            self._update_task.cancel()
            try:
                await self._update_task
            except asyncio.CancelledError:
                pass
        print("🛑 NPC状态自动更新已停止")

    async def _auto_update_loop(self):
        while self._running:
            try:
                await asyncio.sleep(self.update_interval)
                await self._update_npc_states()
            except asyncio.CancelledError:
                break
            except Exception as e:
                print(f"❌ 自动更新失败: {e}")

    async def _update_npc_states(self):
        try:
            print(f"\n🔄 [{datetime.now().strftime('%H:%M:%S')}] 开始批量更新NPC对话...")
            # 【改动】同步 LLM 丢线程 + 超时。否则每 30 秒冻结一次事件循环，
            # 导游协作可视化会跟着一起卡住。
            new_dialogues = await asyncio.wait_for(
                asyncio.to_thread(self.batch_generator.generate_batch_dialogues),
                timeout=25
            )
            event = pop_npc_interact_event()
            if event is not None:
                print(f"💡检测到NPC交互表演事件: {event}")
                new_dialogues["梓涵"] = (
                    f"[[ASK|target={event['target']}|"
                    f"ask_text={event['ask_text']}|"
                    f"reply_text={event['reply_text']}|"
                    f"ts={int(time.time())}]]"
                )
            self.current_dialogues = new_dialogues
            self.last_update = datetime.now()
            self.next_update_time = datetime.now()
            print("📝 NPC对话已更新:")
            for npc_name, dialogue in new_dialogues.items():
                print(f"   - {npc_name}: {dialogue}")
        except Exception as e:
            print(f"❌ 更新NPC状态失败: {e}")

    def get_current_state(self) -> Dict:
        if self.last_update:
            elapsed = (datetime.now() - self.last_update).total_seconds()
            next_update_in = max(0, int(self.update_interval - elapsed))
        else:
            next_update_in = self.update_interval
        return {
            "dialogues": self.current_dialogues,
            "last_update": self.last_update,
            "next_update_in": next_update_in
        }

    def get_npc_dialogue(self, npc_name: str) -> Optional[str]:
        return self.current_dialogues.get(npc_name)

    async def force_update(self):
        print("⚡ 强制更新NPC状态...")
        await self._update_npc_states()


_state_manager = None


def get_state_manager(update_interval: int = 30) -> NPCStateManager:
    global _state_manager
    if _state_manager is None:
        _state_manager = NPCStateManager(update_interval)
    return _state_manager