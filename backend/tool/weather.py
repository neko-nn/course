import requests
from typing import Dict, Any, List
from .base import Tool, ToolParameter

class WeatherTool(Tool):
    def __init__(self):
        super().__init__(name="get_weather", description="查询指定城市的真实天气")

    def run(self, parameters: Dict[str, Any]) -> str:
        city = parameters.get("city", "杭州")
        return self.get_weather(city)

    def get_parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="city",
                type="string",
                description="城市名称，例如：杭州",
                required=True
            )
        ]

    def get_weather(self, city: str) -> str:
        """
        通过调用 wttr.in API 查询真实的天气信息。
        """
        url = f"https://wttr.in/{city}?format=j1"

        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            data = response.json()

            current_condition = data['current_condition'][0]
            weather_desc = current_condition['weatherDesc'][0]['value']
            temp_c = current_condition['temp_C']

            return f"{city}当前天气:{weather_desc}，气温{temp_c}摄氏度"

        except requests.exceptions.RequestException as e:
            return f"错误:查询天气时遇到网络问题 - {e}"
        except (KeyError, IndexError) as e:
            return f"错误:解析天气数据失败，可能是城市名称无效 - {e}"