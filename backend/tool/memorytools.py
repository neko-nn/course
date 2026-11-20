from typing import Dict, Any, List
from .base import Tool, ToolParameter
from core.memory import MemoryManager

class UpdateProfileTool(Tool):
    def __init__(self, memory_m):
        super().__init__(name="update_profile", description="当玩家名字、生日、好感、重要事件变化时，更新档案")
        self.memory_m=memory_m
    def run(self, parameters: Dict[str, Any]) -> str:
        key= parameters.get("key")
        content=parameters.get("content")
        self.memory_m.update_fact(key, content)
        return "done"
    def get_parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="key",
                type="string",
                description="要更新的字段名，必须是以下四个之一：'player_name'(名字), 'birthday'(生日), 'affinity'(好感度), 'facts'(喜好)",
                required=True
            ),
            ToolParameter(
                name="content",
                type="string",
                description="更新的内容，例如：张三",
                required=True
            )
        ]
class SearchMemoryTool(Tool):
    def __init__(self, memory_m):
        super().__init__(name="search_memory", description="回忆过去的事情")
        self.memory_m=memory_m
    def run(self, parameters: Dict[str, Any]) -> str:
        query= parameters.get("query")
        if not self.memory_m.search_vector_memory(query):
            return "没有找到相关的记忆。"
        return "回忆起了以下内容：\n" + "\n".join(self.memory_m.search_vector_memory(query))
    def get_parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="query",
                type="string",
                description="回忆的事情，例如：玩家要去广西玩",
                required=True
            )
        ]