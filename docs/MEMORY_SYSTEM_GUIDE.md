# 🧠 NPC记忆系统使用指南

## 📚 概述

赛博小镇的NPC有三类"记忆"，各管一段：**上下文滑窗**管这一轮聊什么、**档案**管你是谁、**向量库**管过去聊过什么。三者都按NPC隔离，重启服务后档案仍然在。

先说清一条代码现状：项目里**没有 SQLite、没有 MemoryConfig、没有重要性衰减**。档案是纯 JSON，长期回忆走 Qdrant。

---

## ✨ 核心功能

### 1. **短期记忆 (对话上下文)**
- 📝 存在 `Agent._history` 里，只记最终一问一答，不含工具调用的中间消息
- 🪟 每轮由 `ContextBuilder` 重算: 系统人设 + 档案注入 + 历史滑窗
- 📏 滑窗上限: 最多保留 10 条，总预算 3000 token，预留 20% 给输出
- ⏰ 没有超时机制，服务重启即清空（重要内容已进档案或向量库）

### 2. **长期记忆 (档案 + 向量库)**
- 💾 `profile.json`: 玩家名字、生日、好感度、喜好清单，改一次就落盘
- 🔍 Qdrant 向量集合 `memory_<NPC名>`: 每条对话一条向量（1024维，COSINE）
- 🧠 向量化走阿里云 DashScope `text-embedding-v3`（需要 `EMBED_API_KEY`）
- 🎯 检索默认取 top 3，空查询直接返回空列表（不发网络请求）

### 3. **记忆隔离**
- 🔒 每个NPC独立目录 `memory_data/<NPC名>/`、独立向量集合
- 🚫 NPC之间互不可见
- 👤 当前是单玩家设计，没有 `player_id` 多用户分区

---

## 🎯 使用示例

### 示例1: 基本对话记忆

```
第一次对话:
玩家: "你好,你是做什么的?"
子涵: "我是天气学家，主要看云图和气压场。"

第二次对话 (同一进程内,5分钟后):
玩家: "还记得我刚才问你什么吗?"
子涵: "记得，你问我是做什么的，我说我盯云图过日子。"
```
> 这条"记得"靠的是 `_history` 还留在滑窗里。

### 示例2: 跨重启的长期记忆

```
第一天:
玩家: "我叫小林,生日是5月20号。"
子涵: "记下了，小林，5月20号。"

玩家: "我特别喜欢爬山。"
子涵: (调用 update_profile，写进 facts)

第二天(重启服务后):
玩家: "你记得我是谁吗?"
子涵: "当然，小林，5月20号生日，还爱爬山。"
```
> 这条靠 `profile.json`，与进程无关。

### 示例3: 记忆隔离

```
与子涵对话:
玩家: "我最近在研究多智能体系统"
子涵: "那挺有意思，天气模型里也有类似的分工。"

与子寒对话:
玩家: "我刚才和子涵聊了什么?"
子寒: "不知道，我只关心我的二胡。"
```
> 每个NPC只拿到自己的档案和向量集合。

---

## 🔧 技术实现

### 架构设计

```
NPCAgentManager
├── agents: Dict[str, ReActAgent]           # 每个NPC一个Agent
├── memories: Dict[str, MemoryManager]      # 每个NPC一个记忆管理器
└── chat(npc_name, message)
    ├── 1. ContextBuilder 拼系统人设 + 档案 + 历史滑窗
    ├── 2. ReActAgent 最多5轮工具调用，出最终回复
    ├── 3. history 追加 user/assistant
    └── 4. add_vector_memory("玩家说：X。NPC回复：Y")
```

> 第 3、4 步落下的都是 `ReActAgent._clean_reply()` 处理过的回复：Markdown 的 `###` 标题符、加粗星号、反引号、代码围栏、行首列表符会先被清掉。所以滑窗和向量库里存的都是干净的自然语言，下一轮召回时不会把格式记号当成内容。

### 记忆存储结构

```
backend/memory_data/
├── 子涵/
│   └── profile.json        # 档案（唯一落盘文件）
├── 芷涵/
│   └── profile.json
├── 子晗/
│   └── profile.json
├── 子寒/
│   └── profile.json
└── 梓涵/
    └── profile.json

Qdrant（远程）
├── memory_子涵/
├── memory_芷涵/
├── memory_子晗/
├── memory_子寒/
└── memory_梓涵/
```

### 档案数据格式

```json
{
  "player_name": "未知",
  "birthday": "未知",
  "affinity": 0,
  "facts": ["喜欢爬山", "在学多智能体"]
}
```

- 缺字段会自动补默认值，不会覆盖已有内容
- `affinity` 是累加字段（详见好感度指南）

### 注入到提示词

`get_context_prompt()` 把档案拼成一段文本，放进系统提示词:
```
关于你认识的这位玩家：
- 名字：小林
- 生日：5月20日
- 当前好感度：41/100
- 你记得的事：喜欢爬山；在学多智能体
```

---

## 🚀 API接口

### 1. 对话接口 (自动使用记忆)

```http
POST /chat
Content-Type: application/json

{
  "npc_name": "子涵",
  "message": "你还记得我叫什么吗?"
}
```

**响应:**
```json
{
  "npc_name": "子涵",
  "npc_title": "天气学家",
  "message": "记得，小林，5月20号生日。",
  "success": true,
  "timestamp": "2026-11-20T10:30:00"
}
```

### 2. 获取NPC记忆

```http
GET /npcs/子涵/memories?limit=10
```

**响应:**
```json
{
  "npc_name": "子涵",
  "memories": []
}
```

**注意**: 该接口内部调用 `search_vector_memory("")`，空查询按设计直接返回空列表，所以**现在恒为空**。想验证向量记忆，用游戏对话或多聊几轮后调 `/chat` 观察模型是否引用旧内容。

### 3. 清空NPC记忆 (测试用)

```http
DELETE /npcs/子涵/memories
```

**响应:**
```json
{
  "message": "已清空 子涵 的记忆"
}
```

**注意**: 这个接口删的是 `profile.json` 并重建 MemoryManager，Qdrant 里的历史向量**不会删**；要彻底清空请到 Qdrant 控制台删对应集合。

---

## 🧪 测试方法

### 方法1: 使用API测试

1. 启动后端服务:
```bash
cd backend
python main.py
```

2. 访问API文档: http://127.0.0.1:8000/docs

3. 测试:
   - `POST /chat` 报名字和生日
   - 重启服务
   - 再问"我是谁"，看是否记得
   - `DELETE /npcs/子涵/memories` 后再问，应回到"未知"

### 方法2: 在Godot中测试

1. 启动后端服务
2. 运行Godot游戏
3. 与同一个NPC对话多次，先自我介绍，隔几轮再问"我叫什么"
4. 观察NPC是否能答出

---

## 📊 记忆系统配置

### 当前写死的参数（core/memory.py / core/context.py）

| 参数 | 值 | 位置 |
|------|----|------|
| 存储目录 | `./memory_data/<NPC名>` | core/memory.py |
| 向量维度 | 1024 | core/memory.py |
| 距离度量 | COSINE | core/memory.py |
| 集合名 | `memory_<NPC名>` | core/memory.py |
| Qdrant超时 | 8秒 | core/memory.py |
| Embedding超时 | 10秒 | core/memory.py |
| 检索条数 | 默认3 | core/memory.py |
| 上下文总预算 | 3000 token | core/context.py |
| 输出预留 | 20% | core/context.py |
| 历史保留 | 最多10条 | core/context.py |

### 调整建议

- **想多记几轮**: 改 `history_max_keep` 与 `max_tokens`（注意别把系统人设挤掉，ContextBuilder会截断并告警）
- **想检索更多**: `search_vector_memory` 的 `limit`，或改 `MemoryTool` 默认参数
- **想换向量模型**: 改 `_get_embedding` 里的 model 与维度，旧集合需要重建
- **完全不想用向量库**: 不填 `QDRANT_URL`，自动降级，档案功能不受影响

---

## 🎓 教学价值

### 学习要点

1. **短长期记忆的分层**
   - 为什么"最近10条"放内存、"我是谁"放JSON、"聊过什么"放向量库
   - 三类记忆各自失效后的表现

2. **上下文预算**
   - ContextBuilder 如何用 token 估算做滑窗
   - 系统人设超长时的截断策略

3. **向量检索**
   - 中文文本 → embedding → Qdrant query_points
   - 空查询保护、网络异常降级

4. **工具化记忆**
   - `update_profile` 让模型自己决定记什么
   - `search_memory` 让模型自己决定查什么

---

## 🔍 调试技巧

### 1. 查看记忆日志

```
[ContextBuilder] 历史滑窗保留 6 条 | 剩余 Token 空间: 2100
```
出现"系统人设超长"的warning时，说明人设被截断了。

### 2. 检查档案文件

```bash
cd backend/memory_data/子涵
type profile.json      # Windows
cat profile.json       # macOS/Linux
```

### 3. 清空记忆重新测试

```bash
# 删除档案目录（服务运行时会继续用内存里的旧对象，建议先停服务）
rm -rf backend/memory_data/子涵
```
或直接调 `DELETE /npcs/子涵/memories`。

---

## ❓ 常见问题

### Q1: NPC为什么记不住对话?

**可能原因:**
- 超出了10条滑窗（早期内容已不在上下文）
- 记忆被 `delete` 接口清掉
- 问的是需要长期记忆的内容，但模型没调 `search_memory` / 没写 `update_profile`

**解决方法:**
- 先自我介绍并明确说"记住"
- 查看 profile.json 是否写进去了
- 降低对话轮次间隔，别让滑窗滚太快

### Q2: 记忆检索不准确?

**可能原因:**
- 查询是空字符串（直接返回空）
- embedding 网络失败（返回空列表）
- 历史里根本没存相关内容

**解决方法:**
- 用具体问题而不是"嗯""哦"
- 检查 `EMBED_API_KEY`
- 观察控制台是否有"查找失败"

### Q3: 记忆占用空间太大?

**解决方法:**
- 清理旧集合（本项目不做容量淘汰）
- 减少 `add_vector_memory` 的写入频率（比如只写包含事实的回合）

### Q4: 为什么 `/memories` 永远是空数组?

**原因:** 接口传的是空查询，`search_vector_memory` 对空字符串直接返回 `[]`。这是代码现状，不是没记忆——记忆在 Qdrant 里，只是这个接口没给查询词。

---

## 🎉 下一步

记忆之外，系统还实现了:

1. ✅ **好感度系统** - NPC与玩家的关系管理
2. ✅ **情感分析** - 使用LLM对每轮对话打分
3. ✅ **关系等级** - 陌生、熟悉、友好、亲密、挚友

---

## 📝 总结

✅ NPC记忆系统已集成到赛博小镇

**核心特性:**
- 🪟 上下文滑窗（10条 / 3000 token）
- 💾 档案持久化（profile.json）
- 🔍 向量语义检索（Qdrant + DashScope）
- 🔒 按NPC隔离
- 🧯 网络异常自动降级
