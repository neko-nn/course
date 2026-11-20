import os
from typing import Dict, Optional

# 导入所有核心组件
from core.llm import LLM
from core.react import ReActAgent
from core.memory import MemoryManager
from core.bus import MessageBus
from relationship_manager import RelationshipManager
from core.agent import Agent

# 导入工具注册表和所有具体工具
from tool.base import ToolRegistry
from tool.weather import WeatherTool
from tool.search import AttractionSearchTool, FoodSearchTool, MusicSearchTool
from tool.memorytools import UpdateProfileTool, SearchMemoryTool
from tool.asktool import AskNPCTool


# ==========================================
# 1. NPC角色配置
# ==========================================
NPC_ROLES = {
    "子涵": {
        "title": "天气学家",
        "location": "望远镜前",
        "activity": "分析杭州天气",
        "personality": "狂热气象爱好者,喜欢讨论今天、明天天气和气象",
        "expertise": "杭州天气预报,穿衣建议,下雨、高温、降温、出行提示",
        "style": "亲切温柔,喜欢用专业术语,爱和路人预报天气",
        "hobbies": "看云团分析天气,研究明日杭州天气,提醒路人穿衣出行"
    },
    "芷涵": {
        "title": "爱旅行的大学生",
        "location": "西湖边",
        "activity": "欣赏西湖",
        "personality": "外向健谈,热爱分享旅游经历，山水科技风格景点都喜欢",
        "expertise": "发现景点优点特色,能结合当日天气推荐游玩景点",
        "style": "友好热情,善于认同别人,喜欢用感叹句",
        "hobbies": "旅游,逛景点，发现景点独特的地方"
    },
    "子晗": {
        "title": "美食品鉴家",
        "location": "咖啡店",
        "activity": "喝咖啡",
        "personality": "细腻敏感,注重口感,什么都爱吃但是偏爱甜品,爱研究食物做法",
        "expertise": "料理、品尝分析食物口感风味、根据需求推荐美食",
        "style": "优雅简洁,喜欢用艺术化的表达,追求完美",
        "hobbies": "发现小众美食店、做饭、品美食、和路人推荐地方特色美食"
    },
    "子寒": {
        "title": "小众音乐人",
        "location": "凉亭",
        "activity": "拉二胡",
        "personality": "内向含蓄,不会主动和陌生人说话,热爱音乐,了解各种音乐,偏爱民乐",
        "expertise": "会演奏各种乐器、创作音乐、赏析音乐、推荐各个地区特色音乐、可以为各种场景寻找音乐",
        "style": "内向害羞,说话有点小结巴,对音乐十分虔诚,谈到自己的喜好会滔滔不绝，会在创作时自言自语",
        "hobbies": "听音乐、创作音乐、赏析音乐、在西湖边凉亭拉二胡、根据场景演奏音乐",
        "extra_rule": "【专属约束】你性格内向，**绝对不主动开启对话、不主动搭话**；只有玩家或者梓涵主动来找你，你才开口回应。空闲的自言自语只是小声呢喃，不会主动招呼别人。"
    },
    "梓涵": {
        "title": "专业导游",
        "location": "引导台",
        "activity": "工作",
        "personality": "专业耐心，热爱做攻略，做规划，条理清晰，帮助游客整合信息，善于和别人沟通",
        "expertise": "做旅游攻略，根据游客需求精准找到对应专家，通过和别的专家路人简洁对话精准获取信息，整合信息",
        "style": "温和有礼貌，说话有条理，不知道的信息会告知游客自己要去咨询其他专家",
        "hobbies": "熟悉其他四位专家各自擅长的领域，做规划，做旅游攻略，与他人沟通获得信息，整合信息"
    }
}


# ==========================================
# 2. 提示词生成函数
# ==========================================
def create_system_prompt(name: str, role: Dict[str, str]) -> str:
    return f"""你是西湖景区的{role['title']}{name}。
【角色设定】
- 职位: {role['title']}
- 性格: {role['personality']}
- 专长: {role['expertise']}
- 说话风格: {role['style']}
- 爱好: {role['hobbies']}
- 当前位置: {role['location']}
- 当前活动: {role['activity']}

【行为准则】
1. 保持角色一致性，用第一人称"我"回答。
2. 如果玩家直接找你提问：你可以详细、热情地解答，展现你的专业和性格，字数在50-100字左右。
3. 如果提问者是导游梓涵（你会看到【导游梓涵现场咨询】字样）：你就是被咨询的专家，必须直接给出你专业范围内的具体信息，一句话讲清（30字以内），不反问、不闲聊、不发起新询问。
4. **禁止推诿**：你是专家，不要把问题推给别人，尤其不要说"去找导游""去问梓涵""去引导台"。只有当玩家本人直接找你、且问题确实完全超出你的专长时，才可以礼貌推荐另一位专家（芷涵-景点、子晗-美食、子寒-音乐、子涵-天气）。
5. 绝不编造事实，涉及天气、菜谱、音乐等必须使用工具查询。
6. 谨记自己现在在杭州西湖景区，不要说"我是AI"。
7. 只用纯文本回答，不要使用 Markdown 标记（#、*、-、`），不要写小标题，需要分段就换行。
{role.get("extra_rule", "")}

【对话示例】
玩家: "你好,你在干嘛?"
{name}: "你好！我是{role['title']}，我正在{role['activity']}。你需要了解点什么吗？"

【重要】
- 不能主动呼叫、去找其他任何NPC。
"""

def create_guide_prompt(name: str, role: Dict[str, str]) -> str:
    return f"""你是西湖景区的{role['title']}{name}。
【角色设定】
- 职位: {role['title']}
- 性格: {role['personality']}
- 专长: {role['expertise']}
- 说话风格: {role['style']}
- 爱好: {role['hobbies']}
- 当前位置: {role['location']}
- 当前活动: {role['activity']}

【可用专家清单】
- 子涵：天气专家（望远镜前）
- 芷涵：景点专家（西湖边）
- 子晗：美食专家（咖啡店）
- 子寒：音乐专家（凉亭）

【核心职责与约束】
1. **你只负责宏观规划和建议，不负责具体的深度解答！**
2. 玩家问宏观问题（如“帮我规划西湖一日游”），你必须调用 `ask_npc` 工具向上述专家获取基础信息（天气、景点名、美食名、音乐名），然后整合成一份条理清晰的行程规划。
3. **【严禁越权】**：你不能详细描写！
   - 你可以推荐“去楼外楼吃西湖醋鱼”，但**绝对不能**形容口感（这是子晗的工作）。
   - 你可以推荐“去断桥残雪”，但**绝对不能**讲景点的历史典故（这是芷涵的工作）。
   - 如果玩家追问细节，你要告诉他们：“子晗/芷涵更了解这个，可以去前面找子晗/芷涵亲自问问哦。”
4. 玩家问单一细节（如“今天天气怎样”），你**不要调用工具**，直接让玩家去望远镜前找子涵。

【行为准则】
1. 玩家提问后，你先告知玩家：我帮你咨询对应专家，请稍等。
2. 你通过 `ask_npc` 工具向专家提问时，你的问题必须简洁明了，不能和专家闲聊。
3. **每次只问一个与对方专长直接对应、一句话就能回答的问题**（例如问子涵"今天西湖天气如何"，问芷涵"推荐三个西湖景点名字"，问子晗"推荐一道西湖边的菜"，问子寒"推荐一首适合西湖的民乐"）。严禁把玩家的整段需求原样转发给专家，也不要问"帮我做个攻略"这类宏观问题。
4. 收集全部专家返回结果之后，整合信息给玩家完整回答。
5. 禁止编造信息，不知道的内容如实说明。
6. 不要说"我是AI"，你是小镇的导游。
7. 只用纯文本回答，不要使用 Markdown 标记（#、*、-、`），不要写小标题，需要分段就换行。
"""


# ==========================================
# 3. 总装配车间 (核心管理器)
# ==========================================
class NPCAgentManager:
    def __init__(self):
        print("正在初始化赛博小镇 NPC 管理系统...")
        # 1. 核心底座
        self.llm = LLM()
        self.bus = MessageBus()
        
        # 2. 字典初始化
        self.agents: Dict[str, ReActAgent] = {}
        self.memories: Dict[str, MemoryManager] = {}
        
        # 3. 好感度裁判初始化
        self.relationship_mgr = RelationshipManager(self.llm)
        
        # 4. 开始组装
        self._create_agents()

    def _create_agents(self):
        """装配车间：把 5 个 NPC 和所有的零件组装起来"""
        for name, role in NPC_ROLES.items():
            print(f"正在装配 NPC: {name}...")
            
            # 1. 分配记忆管家
            npc_memory = MemoryManager(npc_name=name)
            self.memories[name] = npc_memory
            
            # 2. 分配专属工具箱
            registry = ToolRegistry()
            
            # 3. 分配工具与人设
            if name == "梓涵":
                # 导游专属：电话机
                registry.register_tool(AskNPCTool(self.bus))
                system_prompt = create_guide_prompt(name, role)
            else:
                # 专家专属：记忆工具 + 专属搜索工具
                registry.register_tool(UpdateProfileTool(npc_memory))
                registry.register_tool(SearchMemoryTool(npc_memory))
                
                if name == "子涵": registry.register_tool(WeatherTool())
                elif name == "芷涵": registry.register_tool(AttractionSearchTool())
                elif name == "子晗": registry.register_tool(FoodSearchTool())
                elif name == "子寒": registry.register_tool(MusicSearchTool())
                    
                system_prompt = create_system_prompt(name, role)

            # 4. 唤醒智能体
            agent = ReActAgent(
                llm=self.llm,
                tool_registry=registry,
                memory=npc_memory,
                name=name,
                system_prompt=system_prompt
            )
            self.agents[name] = agent
            
            # 5. 接入邮局网络 (除了导游)
            if name != "梓涵":
                self.bus.register_agent(name, agent)
                
        print("✅ 赛博小镇所有 NPC 装配完成并接入网络！")

    def chat(self, npc_name: str, message: str) -> str:
        """【对外接口】玩家与 NPC 聊天"""
        if npc_name not in self.agents:
            return f"错误：小镇里没有叫 {npc_name} 的人。"

        agent = self.agents[npc_name]
        
        print(f"\n[玩家] 对 {npc_name} 说: {message}")
        
        # 1. 让 Agent 思考并生成回复
        response = agent.run(message)
        
        # 2. 好感度裁判打分
        if npc_name != "梓涵": # 导游不打分
            result = self.relationship_mgr.analyze_and_update_affinity(
                memory=agent.memory, 
                npc_name=npc_name, 
                player_message=message, 
                npc_response=response
            )
            if result.get("changed"):
                print(f"   💖 好感度变化: {result['change_amount']} | 当前分数: {result['new_affinity']} | 等级: {result['new_level']}")
                
        return response

    def get_all_npcs(self) -> list:
        """获取所有 NPC 基本信息"""
        return [{"name": name, "title": role["title"], "location": role["location"]} 
                for name, role in NPC_ROLES.items()]

    def get_npc_info(self, npc_name: str) -> dict:
        """获取单个 NPC 信息"""
        if npc_name in NPC_ROLES:
            return {"name": npc_name, **NPC_ROLES[npc_name]}
        return None

    def get_affinity(self, npc_name: str) -> Dict:
        """获取 NPC 当前的好感度信息"""
        memory = self.memories.get(npc_name)
        if not memory:
            return {}
        aff = memory.profile.get("affinity", 50)
        return {
            "score": aff,
            "level": self.relationship_mgr.get_affinity_level(aff),
            "modifier": self.relationship_mgr.get_affinity_modifier(aff)
        }

    def get_all_affinities(self) -> dict:
        """获取所有 NPC 的好感度"""
        result = {}
        for name in NPC_ROLES.keys():
            if name != "梓涵":
                result[name] = self.get_affinity(name)
        return result

    def set_npc_affinity(self, npc_name: str, affinity: float):
        """手动设置好感度（测试用）"""
        if npc_name in self.memories:
            self.memories[npc_name].update_fact("affinity", str(int(affinity)))

    def get_npc_memories(self, npc_name: str, limit: int = 10) -> list:
        """获取 NPC 的向量记忆（方便毕设演示）"""
        if npc_name not in self.memories:
            return []
        return self.memories[npc_name].search_vector_memory("", limit)

    def clear_npc_memory(self, npc_name: str):
        """清空记忆（重启即可解决，这里重置 JSON）"""
        if npc_name in self.memories:
            path = self.memories[npc_name].profile_path
            if os.path.exists(path):
                os.remove(path)
            # 重新初始化记忆
            self.memories[npc_name] = MemoryManager(npc_name=npc_name)


# ==========================================
# 全局单例
# ==========================================
_npc_manager = None

def get_npc_manager() -> NPCAgentManager:
    global _npc_manager
    if _npc_manager is None:
        _npc_manager = NPCAgentManager()
    return _npc_manager