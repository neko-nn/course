from dataclasses import dataclass
from typing import Optional, Dict, Any, List
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class ContextConfig:
    """独立的上下文配置器"""
    max_tokens: int = 3000          # 上下文总预算
    reserve_ratio: float = 0.2      # 给模型输出预留的比例 (20%)
    history_max_keep: int = 10      # 最多保留几条历史

class ContextBuilder:
    def __init__(self, config: ContextConfig = None, memory=None):
        self.config = config or ContextConfig()
        self.memory = memory

    def _count_tokens(self, text: str) -> int:
        """中文/英文自适应 Token 估算器"""
        if not text: return 0
        chinese_chars = sum(1 for ch in text if '\u4e00' <= ch <= '\u9fff')
        english_words = len([w for w in text.split() if w])
        return int(chinese_chars + english_words * 1.3)

    def _truncate_text(self, text: str, max_tokens: int) -> str:
        """安全截断文本"""
        total_tok = self._count_tokens(text)
        if total_tok <= max_tokens: return text
        if total_tok <= 0: return ""
        char_per_token = len(text) / total_tok
        max_chars = int(max_tokens * char_per_token)
        return text[:max_chars]

    def build(self, agent: Any, user_input: str) -> List[Dict[str, str]]:
        """
        主入口：构建发给大模型的 messages。
        返回标准 OpenAI 格式的 List[Dict]。
        """
        cfg = self.config
        messages = []
        
        # ================= 1. Gather：收集人设与输入 =================
        system_content = agent.system_prompt or ""
        if self.memory:
            system_content += "\n\n" + self.memory.get_context_prompt()
            
        system_tokens = self._count_tokens(system_content)
        user_tokens = self._count_tokens(user_input)

        # ================= 2. Select：Token 预算与动态滑窗 =================
        # 计算系统指令和用户输入占用的预算，防止超长
        max_system_tokens = int(cfg.max_tokens * (1 - cfg.reserve_ratio))
        if system_tokens > max_system_tokens:
            logger.warning(f"[ContextBuilder] 系统人设超长({system_tokens})，执行截断")
            system_content = self._truncate_text(system_content, max_system_tokens) + "\n[系统指令已截断]"
            system_tokens = self._count_tokens(system_content)

        # 计算剩余可供历史记录使用的 Token
        remaining_tokens = cfg.max_tokens - system_tokens - user_tokens - int(cfg.max_tokens * cfg.reserve_ratio)
        
        # 获取 Agent 的历史
        history = agent.get_history()
        
        selected_history = []
        # 倒序遍历历史，塞满 Token 预算（这就是滑动窗口）
        for msg in reversed(history[-cfg.history_max_keep:]):
            msg_tokens = self._count_tokens(msg.get("content", ""))
            if remaining_tokens - msg_tokens >= 0:
                selected_history.insert(0, msg)
                remaining_tokens -= msg_tokens
            else:
                # Token 满了，舍弃更早的历史
                break

        # ================= 3. Structure：拼装为标准 Messages =================
        if system_content:
            messages.append({"role": "system", "content": system_content})
            
        for msg in selected_history:
            messages.append(msg)
            
        messages.append({"role": "user", "content": user_input})
        
        logger.info(f"[ContextBuilder] 历史滑窗保留 {len(selected_history)} 条 | 剩余 Token 空间: {remaining_tokens}")
        
        return messages