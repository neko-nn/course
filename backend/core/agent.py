# core/agent.py
from abc import ABC, abstractmethod
from typing import Optional, Any, List, Dict
from core.llm import LLM
from config import Settings

class Agent(ABC):
    """所有智能体的抽象基类"""
    
    def __init__(
        self,
        name: str,
        llm: LLM,
        system_prompt: Optional[str] = None,
        config: Optional[Settings] = None
    ):
        self.name = name
        self.llm = llm
        self.system_prompt = system_prompt
        self.config = config or Settings()
        
        # 历史记录直接用字典列表，直接兼容 OpenAI 接口格式
        self._history: List[Dict[str, str]] = []
    
    @abstractmethod
    def run(self, input_text: str, **kwargs) -> str:
        """运行Agent的核心逻辑（由子类实现，如 ReActAgent）"""
        pass
    
    def add_message(self, role: str, content: str):
        """
        添加消息到历史记录
        :param role: 角色 ('user' 或 'assistant')
        :param content: 消息内容
        """
        self._history.append({"role": role, "content": content})
    
    def clear_history(self):
        """清空历史记录"""
        self._history.clear()
    
    def get_history(self) -> List[Dict[str, str]]:
        """获取历史记录"""
        return self._history.copy()
    
    def __str__(self) -> str:
        return f"Agent(name={self.name}, provider={self.llm.provider})"