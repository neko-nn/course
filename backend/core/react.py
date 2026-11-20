import json
import re
from typing import List, Dict
from core.agent import Agent      # 引入父类
from core.context import ContextBuilder # 引入上下文构建器
from core.llm import LLM
from tool.base import ToolRegistry
from core.memory import MemoryManager

class ReActAgent(Agent):
    def __init__(self, llm: LLM, tool_registry: ToolRegistry, memory: MemoryManager, name: str = "", system_prompt: str = ""):
        # 调用父类初始化（父类会保存 name, llm, system_prompt 并初始化 _history）
        super().__init__(name=name, llm=llm, system_prompt=system_prompt)
        
        self.tool_registry = tool_registry
        self.memory = memory
        self.max_steps = 5
        
        # 实例化上下文构建器
        self.context_builder = ContextBuilder(memory=self.memory)

    def run(self, user_input: str, **kwargs) -> str:
        # 1. 交给 ContextBuilder 拼装 messages（不再在 react.py 里手写拼接逻辑）
        messages = self.context_builder.build(agent=self, user_input=user_input)

        tools_schema = self.tool_registry.to_openai_schema()

        for step in range(self.max_steps):
            print(f"\n--- [{self.name}] 思考轮次 {step + 1} ---")
            response_message = self.llm.chat_with_tools(messages, tools=tools_schema)
            
            if not response_message:
                return self._fallback(user_input, "哎呀，我走神了。能再说一次吗？")

            messages.append(response_message)

            if response_message.tool_calls:
                print(f"[{self.name}] 决定调用工具: {len(response_message.tool_calls)} 个")
                for tool_call in response_message.tool_calls:
                    tool_name = tool_call.function.name
                    tool_args = json.loads(tool_call.function.arguments)
                    print(f"   -> 正在执行: {tool_name}，参数: {tool_args}")
                    
                    result = self.tool_registry.execute(tool_name, tool_args)
                    print(f"   <- 工具返回: {result}")

                    messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "name": tool_name,
                        "content": result
                    })
            else:
                print(f"[{self.name}] 输出了最终回答。")
                final_answer = self._clean_reply(response_message.content)
                
                # 2. 用父类的方法添加历史，而不是直接操作 self.history
                self.add_message("user", user_input)
                self.add_message("assistant", final_answer)
                
                # 长期记忆依然在这里存（或者在父类封装一个统一的方法）
                if self.memory:
                    self.memory.add_vector_memory(f"玩家说：{user_input}。{self.name}回复：{final_answer}")
                return final_answer

        return self._fallback(user_input, "抱歉，我有点头晕。")

    def _fallback(self, user_input: str, msg: str) -> str:
        # 同样使用父类方法添加历史
        self.add_message("user", user_input)
        self.add_message("assistant", msg)
        return msg

    # ==================== 【新增】清理模型输出里的 Markdown 痕迹 ====================
    # 模型偶尔会把回答写成 "### 小标题" / "**重点**"，前端是纯文本气泡，会原样显示成乱码。
    # 只去掉排版符号，不改任何文字内容；专家经 MessageBus 回给导游的答案也会走这里。
    _RE_HEADING = re.compile(r"(?m)^[ \t]{0,3}#{1,6}[ \t]*")
    _RE_FENCE = re.compile(r"```[a-zA-Z0-9_+-]*")
    _RE_QUOTE = re.compile(r"(?m)^[ \t]*>[ \t]?")
    _RE_BULLET = re.compile(r"(?m)^[ \t]*[-*+][ \t]+")
    _RE_MULTI_NL = re.compile(r"\n{3,}")

    @classmethod
    def _clean_reply(cls, text: str) -> str:
        if not text:
            return ""
        t = cls._RE_FENCE.sub("", text)
        t = cls._RE_HEADING.sub("", t)
        t = t.replace("**", "").replace("__", "").replace("`", "")
        t = cls._RE_QUOTE.sub("", t)
        t = cls._RE_BULLET.sub("· ", t)
        t = cls._RE_MULTI_NL.sub("\n\n", t)
        return t.strip()