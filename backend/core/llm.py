import os
from openai import OpenAI
from dotenv import load_dotenv
from typing import List, Dict, Optional, Any

load_dotenv()

class LLM:
    def __init__(self, model: Optional[str] = None, api_key: Optional[str] = None, base_url: Optional[str] = None, timeout: Optional[int] = None, **kwargs):
        self.provider = self._auto_detect_provider(api_key, base_url)
        self.model = model or os.getenv("LLM_MODEL_ID")
        self.apikey, self.baseurl = self._resolve_credentials(api_key, base_url)

        # 1. 保留超时，默认 30 秒
        self.timeout = timeout if timeout is not None else int(os.getenv("LLM_TIMEOUT", "30"))
        
        # 2. 【提速核心】严格限制输出长度，500 足够聊天了，太长说明模型在废话
        self.max_tokens = kwargs.get('max_tokens', 500)

        # 3. 关闭 SDK 重试，断网立刻抛出异常走本地兜底
        self.client = OpenAI(
            api_key=self.apikey,
            base_url=self.baseurl,
            timeout=self.timeout,
            max_retries=0
        )

    def _auto_detect_provider(self, api_key: Optional[str], base_url: Optional[str]) -> str:
        if os.getenv("MODELSCOPE_API_KEY"): return "modelscope"
        if os.getenv("OPENAI_API_KEY"): return "openai"
        if os.getenv("ZHIPU_API_KEY"): return "zhipu"
        actual_api_key = api_key or os.getenv("LLM_API_KEY")
        actual_base_url = base_url or os.getenv("LLM_BASE_URL")
        if actual_base_url:
            base_url_lower = actual_base_url.lower()
            if "api-inference.modelscope.cn" in base_url_lower: return "modelscope"
            if "open.bigmodel.cn" in base_url_lower: return "zhipu"
            if "localhost" in base_url_lower or "127.0.0.1" in base_url_lower:
                if ":11434" in base_url_lower: return "ollama"
                if ":8000" in base_url_lower: return "vllm"
                return "local"
        if actual_api_key:
            if actual_api_key.startswith("ms-"): return "modelscope"
        return "auto"

    def _resolve_credentials(self, api_key: Optional[str], base_url: Optional[str]) -> tuple[str, str]:
        if self.provider == "openai":
            return api_key or os.getenv("OPENAI_API_KEY") or os.getenv("LLM_API_KEY"), base_url or os.getenv("LLM_BASE_URL") or "https://api.openai.com/v1"
        elif self.provider == "modelscope":
            return api_key or os.getenv("MODELSCOPE_API_KEY") or os.getenv("LLM_API_KEY"), base_url or os.getenv("LLM_BASE_URL") or "https://api-inference.modelscope.cn/v1/"
        else:
            return api_key or os.getenv("LLM_API_KEY"), base_url or os.getenv("LLM_BASE_URL")

    def think(self, messages: List[Dict[str, str]], temperature: float = 0.6) -> str:
        """普通流式对话（保留思考，温度稍降）"""
        try:
            response = self.client.chat.completions.create(
                model=self.model,
                messages=messages,
                temperature=temperature,
                max_tokens=self.max_tokens,
                # ⭐ 这里没有传 enable_thinking=False，默认开启思考
                stream=True,
            )
            collected_content = []
            for chunk in response:
                if not chunk.choices: continue
                content = chunk.choices[0].delta.content or ""
                print(content, end="", flush=True)
                collected_content.append(content)
            print()
            return "".join(collected_content)
        except Exception as e:
            print(f"❌ 调用LLM API时发生错误: {e}")
            return None

    def chat_with_tools(self, messages: List[Dict[str, str]], tools: List[Dict] = None, temperature: float = 0.6) -> Any:
        """
        供 ReAct 循环使用的非流式接口。
        """
        try:
            kwargs = {
                "model": self.model,
                "messages": messages,
                "temperature": temperature,
                "max_tokens": self.max_tokens,
                # ⭐ 这里没有传 enable_thinking=False，默认开启思考
            }
            if tools:
                kwargs["tools"] = tools
                kwargs["tool_choice"] = "auto"

            response = self.client.chat.completions.create(**kwargs)
            return response.choices[0].message
        except Exception as e:
            print(f"\n❌ 工具调用请求失败: {e}")
            return None