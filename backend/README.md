# 赛博小镇 - FastAPI后端

基于自研多智能体内核的AI NPC对话系统后端服务。

## 🎯 功能特性

### 核心功能
- ✅ **单个NPC对话**: 玩家与NPC实时对话，每个NPC一个独立ReActAgent处理
- ✅ **批量对话生成**: 定时批量生成所有NPC的自主对话，降低API成本80%
- ✅ **状态管理**: 自动更新和缓存NPC状态
- ✅ **导游协作事件流**: 梓涵咨询专家的过程以事件形式实时暴露给前端
- ✅ **好感度打分**: 对话结束后由LLM分析情感并更新NPC档案
- ✅ **记忆管理**: 档案持久化 + Qdrant向量记忆，网络异常自动降级
- ✅ **CORS支持**: 支持Godot导出后跨域访问

### NPC角色
1. **子涵** - 天气学家 (望远镜前)
2. **芷涵** - 爱旅行的大学生 (西湖边)
3. **子晗** - 美食品鉴家 (咖啡店)
4. **子寒** - 小众音乐人 (凉亭)
5. **梓涵** - 专业导游 (引导台)

## 📦 安装依赖

### 1. 安装Python依赖
```bash
cd backend
pip install -r requirements.txt
```

### 2. 配置环境变量
在 `backend/` 下创建 `.env` 文件，代码实际读取的键如下:

```env
# LLM (OpenAI兼容接口)
LLM_MODEL_ID=Qwen/Qwen2.5-72B-Instruct
LLM_API_KEY=your-api-key
LLM_BASE_URL=https://api-inference.modelscope.cn/v1/
LLM_TIMEOUT=30

# 向量库
QDRANT_URL=your-qdrant-url
QDRANT_API_KEY=your-qdrant-key

# Embedding (阿里云DashScope)
EMBED_API_KEY=your-dashscope-key

# 联网搜索
TAVILY_API_KEY=your-tavily-key
```

**注意**: 未配置 `LLM_API_KEY` 时服务仍能启动，但对话只能返回兜底话术；未配置 `QDRANT_URL` / `EMBED_API_KEY` 时自动降级为纯本地模式，只保留档案。

## 🚀 启动服务

### 方法1: 直接运行
```bash
python main.py
```

### 方法2: 使用uvicorn
```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

`main.py` 中已关闭热重载 (`reload=False`)，避免改 `.gd` 文件触发后端重启把正在进行的请求断掉。

启动成功后访问:
- **API文档**: http://127.0.0.1:8000/docs
- **根路径**: http://127.0.0.1:8000/

## 🧪 测试API

后端没有单独的测试脚本，直接用 Swagger 或 curl 验证:

1. 启动服务后打开 http://127.0.0.1:8000/docs
2. 依次测试 `/chat` → `/npcs/status` → `/npcs/interactions`
3. 用 `python view_logs.py list` 查看日志目录（需代码调用logger后才有内容，见 DIALOGUE_LOG_GUIDE.md）

## 📡 API接口

### 1. 获取NPC列表
```http
GET /npcs
```

响应示例:
```json
{
  "npcs": [
    {
      "name": "子涵",
      "title": "天气学家",
      "location": "望远镜前",
      "activity": "",
      "available": true
    }
  ],
  "total": 5
}
```

### 2. 与NPC对话
```http
POST /chat
Content-Type: application/json

{
  "npc_name": "子涵",
  "message": "今天杭州天气怎么样?"
}
```

响应示例:
```json
{
  "npc_name": "子涵",
  "npc_title": "天气学家",
  "message": "刚查了一下，杭州今天多云转晴，气温18摄氏度，风不大，适合出门走走。",
  "success": true,
  "timestamp": "2026-11-20T10:30:00"
}
```

**注意**: 该接口是同步 `def`，FastAPI 会放进线程池执行；否则导游思考的几十秒会独占事件循环，前端轮询 `/npcs/interactions` 将一直拿不到响应。

### 3. 获取NPC状态
```http
GET /npcs/status
```

响应示例:
```json
{
  "dialogues": {
    "子涵": "中午紫外线有点强，大家注意防晒。",
    "芷涵": "吃个饭继续逛西湖！",
    "子晗": "今天的咖啡很醇厚。",
    "子寒": "（创作音乐中...）",
    "梓涵": "中午休息一下，下午继续工作。"
  },
  "last_update": "2026-11-20T12:05:00",
  "next_update_in": 25
}
```

### 4. 强制刷新状态
```http
POST /npcs/status/refresh
```

### 5. 导游协作事件流
```http
GET /npcs/interactions?since=0
```

响应示例:
```json
{
  "events": [
    {
      "seq": 7,
      "phase": "asking",
      "guide": "梓涵",
      "target": "子涵",
      "question": "今天杭州天气怎么样？",
      "reply": "",
      "step": 7,
      "ok": true,
      "ts": 1795000000.0
    }
  ],
  "last_seq": 7
}
```

`phase` 为 `asking`（已发起咨询）或 `answered`（已回复）；前端按 `since=last_seq` 增量轮询。该路由必须声明在 `/npcs/{npc_name}` 之前，否则会被路径参数吞掉。

> `question` 字段推送的始终是**未包装的原始问题**，`【导游梓涵现场咨询】` 这层身份标注只加在真正发给专家 Agent 的文本上，所以前端气泡、HUD、日志看到的都是人话。

### 6. NPC详情
```http
GET /npcs/{npc_name}
```

### 7. 好感度
```http
GET /npcs/{npc_name}/affinity
GET /affinities
PUT /npcs/{npc_name}/affinity?affinity=80
```

### 8. 记忆
```http
GET /npcs/{npc_name}/memories?limit=10
DELETE /npcs/{npc_name}/memories
```

### 9. 健康检查
```http
GET /health
```

## 🏗️ 项目结构

```
backend/
├── main.py                 # FastAPI主程序(对话/NPC/协作事件流接口)
├── config.py               # 配置(从.env读取LLM相关配置)
├── models.py               # 数据模型(Pydantic)
├── agents.py               # NPC角色配置 + Agent装配(NPC_ROLES / NPCAgentManager)
├── relationship_manager.py # 好感度情感分析
├── batch_generator.py      # 批量对话生成器
├── state_manager.py        # NPC状态管理器
├── logger.py               # 对话日志模块(需业务代码调用)
├── view_logs.py            # 日志查看工具(tail / view / list)
├── core/                   # 自研多智能体内核
│   ├── agent.py            # Agent抽象基类
│   ├── react.py            # ReActAgent(最多5轮工具调用)
│   ├── context.py          # ContextBuilder(token预算+滑动窗口)
│   ├── llm.py              # LLM封装(OpenAI兼容)
│   ├── memory.py           # MemoryManager(档案+Qdrant向量记忆)
│   ├── bus.py              # MessageBus(权限表+真实转发)
│   └── message.py          # 消息信封
├── tool/                   # 工具集
│   ├── base.py             # Tool / ToolRegistry
│   ├── asktool.py          # ask_npc(导游咨询+协作事件流)
│   ├── memorytools.py      # update_profile / search_memory
│   ├── search.py           # 景点/美食/音乐搜索(Tavily)
│   └── weather.py          # 天气查询(wttr.in)
├── memory_data/            # 每个NPC一个目录，profile.json在此
├── logs/                   # 日志目录
├── requirements.txt        # Python依赖
├── .env                    # 本地环境变量(需自行创建)
└── README.md               # 本文件
```

## 🎨 核心设计

### 批量对话生成
为了降低API成本和延迟，系统采用批量生成策略:

**传统方式**:
- 5个NPC × 每30秒 = 10次API调用/分钟
- 每小时: 600次调用

**批量方式**:
- 1次批量调用/30秒 = 2次API调用/分钟
- 每小时: 120次调用
- **成本降低80%!**

状态管理器初始化时先用预设对话兜底，服务一起来前端就有碎碎念；首次批量更新放在后台任务里，不挡 uvicorn 绑端口。批量生成用 `asyncio.to_thread` 丢线程并设25秒超时，避免每30秒冻结一次事件循环。

### 工作流程
```
1. 定时器触发(30秒)
   ↓
2. 批量生成器构建提示词
   ↓
3. 一次LLM调用生成所有NPC对话
   ↓
4. 解析JSON响应(失败则用按时间段取预设对话)
   ↓
5. 若这30秒内发生过导游咨询，梓涵的台词被替换为 [[ASK|target=...]]
   ↓
6. 更新状态管理器缓存
   ↓
7. Godot客户端每10秒轮询 /npcs/status
```

### 导游协作链路
```
玩家在对话UI输入 → POST /chat
   ↓
梓涵 ReActAgent 决定调用 ask_npc（问题只针对一位专家的专长，一句话能答）
   ↓
AskNPCTool 先推 asking 事件(前端立刻看到"梓涵正在前往子涵")
   ↓
AskNPCTool 给问题加身份标注「【导游梓涵现场咨询】…不要让提问者去找导游」
   ↓
MessageBus 校验权限(梓涵→四位专家；专家→梓涵)
   ↓
专家的 ReActAgent 真实作答(最多5轮，可调天气/搜索/记忆工具)
   ↓
若回复是"去找导游/去引导台"这类推诿 → 带强制指令重问一次（只重试1次）
   ↓
推 answered 事件 → 前端演出 + HUD + 对话时间线
```
> 所有 NPC 的最终回答都会经 `ReActAgent._clean_reply()` 清掉 Markdown 记号（###、**、反引号、围栏），前端纯文本气泡不会出现乱码标题。

## 🔧 配置说明

### config.py
```python
API_HOST = "0.0.0.0"
API_PORT = 8000

# NPC状态批量更新间隔(秒)
NPC_UPDATE_INTERVAL = 30

# LLM从环境变量读取，默认ModelScope
LLM_MODEL_ID = os.getenv("LLM_MODEL_ID", "Qwen/Qwen2.5-72B-Instruct")
```

### 关键常量（代码内固定）
| 项目 | 值 | 位置 |
|------|----|------|
| Agent最大思考轮数 | 5 | core/react.py |
| LLM输出上限 | 500 tokens | core/llm.py |
| LLM超时 | 30秒（LLM_TIMEOUT可覆盖） | core/llm.py |
| 上下文预算 | 3000 tokens，预留20% | core/context.py |
| 历史最多保留 | 10条 | core/context.py |
| 向量维度 | 1024 (COSINE) | core/memory.py |
| 向量集合名 | memory_<NPC名> | core/memory.py |
| 协作事件上限 | 240条 | tool/asktool.py |

### 调整更新频率
修改 `config.py` 中的 `NPC_UPDATE_INTERVAL`:
- 开发测试: 10秒
- 正式运行: 30-60秒
- 低成本模式: 120秒

## 🐛 故障排查

### 问题1: 启动提示未设置LLM_API_KEY
```
⚠️  警告: 未设置LLM_API_KEY环境变量
```
**解决**: 在 `.env` 中填写 `LLM_API_KEY`；不填也能启动，但对话只会返回兜底话术。

### 问题2: Qdrant连接失败
```
[子涵] 连接失败，降级为纯本地模式: ...
```
**解决**: 检查 `QDRANT_URL` / `QDRANT_API_KEY`。降级后档案(名字/生日/好感/喜好)照常可用，只是向量回忆功能不可用。

### 问题3: 对话超时或无响应
**解决**: 检查 `LLM_BASE_URL` 与网络；LLM超时默认30秒，前端对话请求超时180秒。

### 问题4: CORS错误
**解决**: 检查 `config.py` 中的 `CORS_ORIGINS`（当前为 `["*"]`）。

### 问题5: 导游协作HUD不出现
**解决**: 确认 `/npcs/interactions` 可访问；该接口与 `/chat` 必须能并发响应（`/chat` 同步def已被丢进线程池）。
