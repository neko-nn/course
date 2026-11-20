# tool/__init__.py
from .base import ToolRegistry
from .weather import WeatherTool
from .search import AttractionSearchTool, FoodSearchTool, MusicSearchTool

registry = ToolRegistry()

def register_all_tools():
    registry.register_tool(WeatherTool())
    registry.register_tool(AttractionSearchTool())
    registry.register_tool(FoodSearchTool())
    registry.register_tool(MusicSearchTool())

register_all_tools()