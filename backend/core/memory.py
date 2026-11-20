import os
import json
import requests
import uuid
from typing import Dict, List, Any
from dotenv import load_dotenv
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

# 读取 .env 文件
load_dotenv()


class MemoryManager:
    def __init__(self, npc_name: str = ""):
        self.npc_name = npc_name
        self.base_dir = os.path.join("memory_data", self.npc_name)
        os.makedirs(self.base_dir, exist_ok=True)
        self.profile_path = os.path.join(self.base_dir, "profile.json")
        self.profile = self._load_profile()

        self.qdrant_url = os.getenv("QDRANT_URL")
        self.qdrant_api = os.getenv("QDRANT_API_KEY")
        try:
            # 【改动】加 timeout=8。
            # 原因：Qdrant 云在境外，默认超时很长；启动时要连 5 个 NPC 的集合，
            #      网络一抽风就把整个服务启动拖住几十秒。
            self.qdrant = QdrantClient(url=self.qdrant_url, api_key=self.qdrant_api, timeout=8)
            self.hasqdrant = True
            self.collection_name = f"memory_{self.npc_name}"
            if not self.qdrant.collection_exists(self.collection_name):
                self.qdrant.create_collection(
                    collection_name=self.collection_name,
                    vectors_config=VectorParams(size=1024, distance=Distance.COSINE)
                )
        except Exception as e:
            self.hasqdrant = False
            print(f"[{self.npc_name}] 连接失败，降级为纯本地模式: {e}")

    def _load_profile(self) -> Dict:
        # 【改动】加了"缺字段自动补默认值"的保护。
        # 原因：老档案如果缺 facts / birthday，后面 self.profile["facts"] 会直接 KeyError 崩掉。
        #      这里只补缺失的键，已有的名字/生日/好感/喜好一个都不会被覆盖。
        defaults = {"player_name": "未知", "birthday": "未知", "affinity": 0, "facts": []}
        if os.path.exists(self.profile_path):
            try:
                with open(self.profile_path, "r", encoding="utf-8") as file:
                    saved = json.load(file)
                if isinstance(saved, dict):
                    defaults.update(saved)
            except Exception as e:
                print(f"[{self.npc_name}] 档案读取失败，使用默认档案: {e}")
        return defaults

    def save_profile(self):
        with open(self.profile_path, "w", encoding="utf-8") as file:
            json.dump(self.profile, file, ensure_ascii=False, indent=2)

    def update_fact(self, key: str, content):
        """名字/生日/喜好/好感 —— 每次调用立刻落盘，退出重进依然在（逻辑未改）"""
        if key == "affinity":
            self.profile[key] += int(content)
        elif key == "facts":
            self.profile[key].append(content)
        else:
            self.profile[key] = content
        self.save_profile()

    def _get_embedding(self, text: str) -> List[float]:
        """调用阿里云 DashScope 把文字变成向量"""
        api_key = os.getenv("EMBED_API_KEY")
        url = "https://dashscope.aliyuncs.com/api/v1/services/embeddings/text-embedding/text-embedding"

        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": "text-embedding-v3",
            "input": {"texts": [text]}
        }

        # 【改动】加 timeout=10。
        # 原因：原来 requests.post 没有超时，网络一卡就是无限期挂起，
        #      而它在每次 NPC 回复之后都会执行，会把整条对话链吊死。
        response = requests.post(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.json()["output"]["embeddings"][0]["embedding"]

    def add_vector_memory(self, text: str):
        if not self.hasqdrant:
            print("网络错误")
            return
        try:
            vector = self._get_embedding(text)
            self.qdrant.upsert(
                collection_name=self.collection_name,
                points=[PointStruct(id=str(uuid.uuid4()), vector=vector, payload={"text": text})]
            )
        except Exception as e:
            print(f"存入失败{e}")

    def search_vector_memory(self, query: str, limit: int = 3) -> List:
        if not self.hasqdrant:
            return []
        # 【改动】空查询直接返回，不发网络请求。
        # 原因：agents.py 的 get_npc_memories 传的就是空字符串 ""，
        #      DashScope 对空文本会报错，白白等一次网络往返。
        if not query or not query.strip():
            return []
        try:
            query_q = self._get_embedding(query)
            hits = self.qdrant.query_points(
                collection_name=self.collection_name, query=query_q, limit=limit
            ).points
            r = []
            for i in hits:
                r.append(i.payload["text"])
            return r
        except Exception as e:
            print(f"查找失败{e}")
            return []

    def get_context_prompt(self) -> str:
        """把画像转为文本，供 ContextBuilder 注入到 System Prompt"""
        affinity = self.profile["affinity"]
        facts = "；".join(self.profile["facts"]) if self.profile["facts"] else "无"
        # 【改动】把 birthday 加进提示词，并说明这是已持久保存的已知信息。
        # 原因：生日一直有写进 profile.json，但原来的提示词里根本没有它，
        #      模型看不到 → 你问"我生日几号"它照样想不起来。
        #      这行直接关系到你要的"退出再进还记得名字和生日"。
        return (
            f"【玩家长期档案(已持久保存，以下已知信息不要再追问)】"
            f"名字：{self.profile['player_name']} | "
            f"生日：{self.profile.get('birthday', '未知')} | "
            f"当前好感度分数：{affinity}/100 | "
            f"喜好记录：{facts}"
        )