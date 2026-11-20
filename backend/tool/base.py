from abc import ABC, abstractmethod
from typing import Dict, Any, List
from pydantic import BaseModel

class ToolParameter(BaseModel):
    """工具参数定义"""
    name: str
    type: str
    description: str
    required: bool = True
    default: Any = None

class Tool(ABC):
    """工具基类"""

    def __init__(self, name: str, description: str):
        self.name = name
        self.description = description

    @abstractmethod
    def run(self, parameters: Dict[str, Any]) -> str:
        """执行工具"""
        pass

    @abstractmethod
    def get_parameters(self) -> List[ToolParameter]:
        """获取工具参数定义"""
        pass

class ToolRegistry:
    """HelloAgents工具注册表"""

    def __init__(self):
        self._tools: dict[str, Tool] = {}
        self._functions: dict[str, dict[str, Any]] = {}

    def register_tool(self, tool: Tool):
        """注册Tool对象"""
        if tool.name in self._tools:
            print(f" 警告:工具 '{tool.name}' 已存在，将被覆盖。")
        self._tools[tool.name] = tool
        print(f" 工具 '{tool.name}' 已注册。")
        
    def get_tools_description(self) -> str:
        """获取所有可用工具的格式化描述字符串"""
        descriptions = []

        # Tool对象描述
        for tool in self._tools.values():
            descriptions.append(f"- {tool.name}: {tool.description}")

    # 函数工具描述
        for name, info in self._functions.items():
            descriptions.append(f"- {name}: {info['description']}")

        return "\n".join(descriptions) if descriptions else "暂无可用工具"
    
    def to_openai_schema(self) -> List[Dict[str, Any]]:
        """转换为 OpenAI function calling schema 格式"""
        schemas = []
        
        for tool in self._tools.values():
            parameters = tool.get_parameters()
            properties = {}
            required = []

            for param in parameters:
                prop = {
                    "type": param.type,
                    "description": param.description
                }
                if param.default is not None:
                    prop["description"] = f"{param.description} (默认: {param.default})"
                if param.type == "array":
                    prop["items"] = {"type": "string"}

                properties[param.name] = prop
                if param.required:
                    required.append(param.name)

            schemas.append({
                "type": "function",
                "function": {
                    "name": tool.name,              
                    "description": tool.description,
                    "parameters": {
                        "type": "object",
                        "properties": properties,
                        "required": required
                    }
                }
            })
            
        return schemas
    def execute(self, tool_name: str, arguments: Dict[str, Any]) -> str:
        if tool_name not in self._tools:
            return f"错误：找不到工具 '{tool_name}'"
        try:
            return self._tools[tool_name].run(arguments)
        except Exception as e:
            return f"执行工具失败: {e}"