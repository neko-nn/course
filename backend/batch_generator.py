"""批量NPC对话生成器"""
import json
from datetime import datetime
from typing import Dict, Optional
from core.llm import LLM
from agents import NPC_ROLES


class NPCBatchGenerator:
    def __init__(self):
        print("🎨 正在初始化批量对话生成器...")
        self.llm = LLM()
        self.npc_configs = NPC_ROLES

        # 预设兜底对话（断网时使用）
        self.preset_dialogues = {
            "morning": {
                "子涵": "早上好，今天看天气预报了吗。",
                "芷涵": "早！准备去断桥边晨跑。",
                "子晗": "早安，刚烤好一炉桂花糕。",
                "子寒": "（小声拉二胡中...）",
                "梓涵": "各位早，今天游客应该挺多的。"
            },
            "noon": {
                "子涵": "中午紫外线有点强，大家注意防晒。",
                "芷涵": "吃个饭继续逛西湖！",
                "子晗": "今天的咖啡很醇厚。",
                "子寒": "（创作音乐中...）",
                "梓涵": "中午休息一下，下午继续工作。"
            },
            "afternoon": {
                "子涵": "下午云层变厚了，可能会下雨。",
                "芷涵": "在苏堤看日落，太美了！",
                "子晗": "下午茶时间，尝尝这个新甜品！",
                "子寒": "（拉着一首悲伤的曲子...）",
                "梓涵": "下午的导游工作告一段落。"
            },
            "evening": {
                "子涵": "傍晚降温了，大家记得添衣服。",
                "芷涵": "回学校啦，西湖晚安。",
                "子晗": "今天非常愉快，明天见。",
                "子寒": "这里应该这样写...",
                "梓涵": "下班了，明天见。"
            }
        }

    def generate_batch_dialogues(self, context: Optional[str] = None) -> Dict[str, str]:
        try:
            prompt = self._build_batch_prompt(context)
            # 使用你写的 LLM 发送请求（不用带工具）
            response_msg = self.llm.chat_with_tools([{"role": "user", "content": prompt}])
            response = response_msg.content

            # 解析 JSON
            dialogues = json.loads(response)
            if isinstance(dialogues, dict):
                return dialogues
            return self._get_preset_dialogues()
        except Exception as e:
            print(f"⚠️ 批量生成失败: {e}，使用预设对话")
            return self._get_preset_dialogues()

    def _build_batch_prompt(self, context: Optional[str] = None) -> str:
        if context is None:
            context = self._get_current_context()

        npc_descriptions = []
        for name, cfg in self.npc_configs.items():
            desc = f"- {name}({cfg['title']}): 在{cfg['location']}{cfg['activity']},性格{cfg['personality']}"
            npc_descriptions.append(desc)

        npc_desc_text = "\n".join(npc_descriptions)

        return f"""请为西湖景区的5个NPC生成当前的对话或行为描述。
【场景】{context}
【NPC信息】
{npc_desc_text}
【生成要求】
1. 每个NPC生成1句话(20‑40字)
2. 必须符合角色设定，注意【子寒】性格内向，只会自言自语。
3. **必须严格按照JSON格式返回**
输出格式示例：{{"子涵": "...", "芷涵": "...", "子晗": "...", "子寒": "...", "梓涵": "..."}}
请生成(只返回JSON):
"""

    def _get_current_context(self) -> str:
        hour = datetime.now().hour
        if 6 <= hour < 12:
            return "上午工作时间，西湖边空气清新"
        elif 12 <= hour < 14:
            return "午餐时间，大家在休息"
        elif 14 <= hour < 18:
            return "下午时间，阳光不错"
        else:
            return "夜晚时分，西湖渐渐安静"

    def _get_preset_dialogues(self) -> Dict[str, str]:
        hour = datetime.now().hour
        if 6 <= hour < 12:
            period = "morning"
        elif 12 <= hour < 14:
            period = "noon"
        elif 14 <= hour < 18:
            period = "afternoon"
        else:
            period = "evening"
        return self.preset_dialogues.get(period, self.preset_dialogues["morning"])


_batch_generator = None


def get_batch_generator() -> NPCBatchGenerator:
    global _batch_generator
    if _batch_generator is None:
        _batch_generator = NPCBatchGenerator()
    return _batch_generator
