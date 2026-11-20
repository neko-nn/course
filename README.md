# 赛博小镇 - AI NPC对话系统

基于自研多智能体内核的AI小镇模拟游戏，展示多智能体系统在游戏中的应用。

## 🎮 功能特性

- ✅ 5个AI NPC (子涵、芷涵、子晗、子寒、梓涵)
- ✅ 智能对话系统 (ReActAgent + 工具调用，最多5轮思考)
- ✅ 记忆系统 (上下文滑窗 + 档案持久化 + Qdrant向量记忆，支持降级纯本地模式)
- ✅ 好感度系统 (5个等级，分析结果写入NPC档案profile.json；对话面板顶部实时读出，TAB 键打开关系档案面板看全景)
- ✅ 多智能体导游协作：梓涵可咨询其余四位专家，事件流实时可视化(HUD + 对话时间线)；演出细节为"走到专家身边才开口、专家站定播待机动画作答、问完自动回引导台"
- ✅ NPC自主行为 (闲逛、闲置随机动画状态机、头顶气泡错峰播放)
- ✅ 日志系统 (logger.py 日志模块 + view_logs.py 查看工具)

## 🛠️ 技术栈

- **游戏引擎:** Godot 4.x (工程按4.x配置)
- **后端框架:** FastAPI + Python 3.10+
- **AI框架:** 自研core智能体模块 (Agent、ReActAgent、ContextBuilder、MessageBus)
- **LLM:** OpenAI兼容接口 (默认走ModelScope，可配置其余的LLM服务)
- **向量库:** Qdrant (连接失败自动降级纯本地模式)
- **Embedding:** 阿里云DashScope text-embedding-v3

## 📦 快速开始

详见 [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md)

> 💡 体验协作演示：运行游戏，找到NPC梓涵，输入「帮我规划西湖一日游」即可触发多智能体协作链路可视化。

## 📚 文档

- [安装配置指南](docs/SETUP_GUIDE.md)
- [后端说明文档](backend/README.md)
- [GDScript脚本说明](helloagents-ai-town/README.md)
- [对话日志系统](docs/DIALOGUE_LOG_GUIDE.md)
- [好感度系统](docs/AFFINITY_SYSTEM_GUIDE.md)
- [记忆系统](docs/MEMORY_SYSTEM_GUIDE.md)

