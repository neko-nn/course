import os
from tavily import TavilyClient
from typing import Dict, Any, List
from .base import Tool, ToolParameter
from dotenv import load_dotenv

load_dotenv()

class BaseSearchTool(Tool):
    def __init__(self, name: str, description: str):
        super().__init__(name=name, description=description)
        # 从环境变量读取并初始化 Tavily
        api_key = os.environ.get("TAVILY_API_KEY")
        if not api_key:
            print("警告: 未配置 TAVILY_API_KEY 环境变量。")
        self.tavily = TavilyClient(api_key=api_key.strip() if api_key else "")

    def _do_search(self, query: str) -> str:
        """封装了 Tavily 的高级搜索逻辑（带 include_answer）"""
        try:
            # include_answer=True 会返回综合性的回答
            response = self.tavily.search(query=query, search_depth="basic", include_answer=True)
            
            # 优先返回综合性回答（极大降低大模型的幻觉）
            if response.get("answer"):
                return response["answer"]
            
            # 如果没有综合性回答，则格式化原始结果
            formatted_results = []
            for result in response.get("results", []):
                formatted_results.append(f"- {result['title']}: {result['content']}")
            
            return "根据搜索，为您找到以下信息:\n" + "\n".join(formatted_results) if formatted_results else "抱歉，没有找到相关推荐。"
        except Exception as e:
            return f"错误: 执行Tavily搜索时出现问题 - {e}"

class AttractionSearchTool(BaseSearchTool):
    def __init__(self):
        super().__init__(
            name="search_attractions",
            description="根据城市，搜索最值得去的旅游景点推荐及理由"
        )

    def run(self, parameters: Dict[str, Any]) -> str:
        city = parameters.get("city", "杭州")
        # 融合了你写的高级查询词逻辑
        query = f"'{city}' 最值得去的旅游景点推荐及理由"
        return self._do_search(query)

    def get_parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(name="city", type="string", description="城市名称，例如：杭州", required=True),
        ]


class FoodSearchTool(BaseSearchTool):
    def __init__(self):
        super().__init__(
            name="search_food",
            description="搜索指定城市的特色美食、菜谱做法、餐厅推荐"
        )

    def run(self, parameters: Dict[str, Any]) -> str:
        city = parameters.get("city", "杭州")
        query = f"'{city}'最出名的特色美食推荐及做法介绍"
        return self._do_search(query)

    def get_parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(name="city", type="string", description="城市名称，例如：杭州", required=True)
        ]


class MusicSearchTool(BaseSearchTool):
    def __init__(self):
        super().__init__(
            name="search_music",
            description="搜索适合特定场景的音乐、民乐、歌曲推荐"
        )

    def run(self, parameters: Dict[str, Any]) -> str:
        scene = parameters.get("scene", "西湖风景")
        query = f"适合'{scene}'场景的背景音乐、民乐或歌曲推荐"
        return self._do_search(query)

    def get_parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(name="scene", type="string", description="场景描述，例如：西湖边散步、杭州专属音乐", required=True)
        ]