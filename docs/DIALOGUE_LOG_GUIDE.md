# 对话日志系统使用指南

## 📝 概述

`logger.py` 提供了一套对话日志函数，把一轮对话的完整过程（玩家说了什么、好感度多少、检索到哪些记忆、NPC怎么回、分数变没变）同时输出到控制台和文件。

**先说清现状**: `logger.py` 本身已写完，但 `agents.py` 目前**没有调用**它——也就是说，直接启动服务时 `logs/` 目录里不会产生对话记录，控制台能看到的是各模块自己的 `print` 和 `[ContextBuilder]` 告警。想要完整的对话日志，按下面"如何接入"加三处调用即可。

---

## 🎯 功能特性

### 1. 可记录的对话信息

- 💬 对话开始/结束
- 📝 玩家消息
- 💖 当前好感度和关系等级
- 🧠 检索到的相关记忆条数与内容
- 🤖 正在生成回复 / NPC回复内容
- 📊 好感度变化（变化量、原因、情感倾向、等级变化）
- 💾 记忆保存确认

### 2. 双重输出

- **控制台输出** - 实时查看，方便调试
- **文件输出** - 持久化保存，方便回顾

### 3. 按日期分类

日志文件按日期自动命名:
```
backend/logs/
├── dialogue_2026-11-20.log
├── dialogue_2026-11-21.log
└── dialogue_2026-11-22.log
```

---

## 📂 文件结构

```
backend/
├── logger.py          # 日志系统核心模块（handler/函数都在这里）
├── view_logs.py       # 日志查看工具（tail / view / list）
├── agents.py          # 对话主流程（目前未接入logger）
└── logs/              # 日志目录（logger被import时自动创建）
    └── dialogue_YYYY-MM-DD.log
```

---

## 🔌 如何接入

### 步骤1: 在 agents.py 顶部引入

```python
from logger import (
    log_dialogue_start, log_affinity, log_memory_retrieval,
    log_generating_response, log_npc_response, log_analyzing_affinity,
    log_affinity_change, log_memory_saved, log_dialogue_end
)
```

### 步骤2: 在 chat 流程里按顺序调用

```python
def chat(self, npc_name: str, message: str) -> str:
    npc = self.agents.get(npc_name)
    if npc is None:
        raise ValueError(f"小镇里没有叫{npc_name}的人")

    memory = self.memories[npc_name]

    log_dialogue_start(npc_name, message)
    log_affinity(npc_name, memory.profile.get("affinity", 0),
                 self.relationship_mgr.get_affinity_level(memory.profile.get("affinity", 0)))

    reply = npc.run(message)      # ReActAgent 出最终回复
    log_npc_response(npc_name, reply)

    if npc_name != "梓涵":
        log_analyzing_affinity()
        result = self.relationship_mgr.analyze_and_update_affinity(npc_name, reply, message)
        log_affinity_change(result)

    log_memory_saved(npc_name)
    log_dialogue_end()
    return reply
```

> `log_memory_retrieval` 与 `log_generating_response` 按需插在检索/生成位置；前者参数是 `(npc_name, 条数, 记忆列表)`。

### 步骤3: 启动服务后确认

`logger.py` 被 import 时会打印:
```
📝 对话日志文件: D:\...\backend\logs\dialogue_2026-11-20.log
📂 日志目录: D:\...\backend\logs
```

---

## 🚀 使用方法

### 方法1: 查看今天的完整日志

```bash
cd backend
python view_logs.py view
```

**效果:**
- 显示今天的完整日志内容
- 一次性显示所有对话记录

---

### 方法2: 实时查看日志文件

**在另一个终端窗口运行:**
```bash
cd backend
python view_logs.py tail
```

**效果:**
- 实时显示日志内容 (类似 `tail -f`)
- 新的对话会立即显示
- 按 `Ctrl+C` 停止查看
- 如果今天的文件还没生成，会一直打印"⏳ 等待日志文件创建"

---

### 方法3: 列出所有日志文件

```bash
cd backend
python view_logs.py list
```

**效果:**
```
============================================================
📂 日志文件列表
📁 目录: D:\...\backend\logs
============================================================

1. dialogue_2026-11-20.log
   大小: 12.34 KB
   修改时间: 2026-11-20 14:30:25

2. dialogue_2026-11-19.log
   大小: 8.56 KB
   修改时间: 2026-11-19 18:45:12
```

> 不带参数直接运行 `python view_logs.py`，默认就是 tail 模式。

---

## 📊 日志格式示例

### 完整对话流程（接入后）

```
14:30:25 - ============================================================
14:30:25 - 💬 对话开始: 子涵 <-> 玩家
14:30:25 - ============================================================
14:30:25 - 📝 玩家消息: 你好,很高兴认识你!
14:30:25 - 💖 当前好感度: 36.0/100 (熟悉)
14:30:25 - 🧠 检索到0条相关记忆
14:30:28 - 🤖 正在生成回复...
14:30:30 - 💬 子涵回复: 你好！我也挺高兴，今天云层不高，适合出来走。
14:30:30 - 📊 正在分析好感度变化...
14:30:32 - 📈 好感度变化: 36.0 -> 41.0 (+5.0)
14:30:32 -   原因: 友好问候
14:30:32 -   情感: positive
14:30:32 -   🎉 关系等级变化: 熟悉 -> 友好
14:30:32 -   💾 对话已保存到子涵的记忆中
14:30:32 - ============================================================
14:30:32 - ✅ 对话完成

```

### 好感度未变化

```
14:35:12 - 💖 当前好感度: 41.0/100 (友好)
14:35:15 - 📊 正在分析好感度变化...
14:35:15 -   ➡️ 好感度未变化 (当前: 41.0)
14:35:15 -   原因: 中性闲聊
```

---

## 🎓 教学价值

### 1. 完整的对话流程可视化

可以看到:
- 📝 玩家输入
- 🧠 记忆检索
- 🤖 回复生成
- 📊 好感度分析
- 💾 记忆保存

### 2. 好感度验证

- 看到分数怎么变、为什么变
- 观察等级跨越的瞬间

### 3. 排查问题

- 对话卡在哪一步（生成 / 分析 / 保存）
- 记忆检索是否命中

---

## 🔧 技术实现

### logger.py 核心结构

```python
# 创建logger（名字固定为"dialogue"，避免和业务日志混在一起）
dialogue_logger = logging.getLogger("dialogue")
dialogue_logger.setLevel(logging.INFO)
dialogue_logger.handlers.clear()

# 文件handler - 保存到文件（utf-8，按日期命名）
file_handler = logging.FileHandler(LOG_FILE, encoding="utf-8")

# 控制台handler - 输出到控制台
console_handler = logging.StreamHandler()

dialogue_logger.addHandler(file_handler)
dialogue_logger.addHandler(console_handler)
dialogue_logger.propagate = False   # 不再向root logger冒泡，避免重复打印
```

### 函数清单

| 函数 | 作用 |
|------|------|
| `log_dialogue_start(npc, msg)` | 打印分隔线、对话双方、玩家消息 |
| `log_affinity(npc, value, level)` | 打印当前好感度与等级 |
| `log_memory_retrieval(npc, count, memories)` | 打印检索条数与记忆内容 |
| `log_generating_response()` | 打印"正在生成回复..." |
| `log_npc_response(npc, text)` | 打印NPC回复 |
| `log_analyzing_affinity()` | 打印"正在分析好感度变化..." |
| `log_affinity_change(result)` | 打印变化量、原因、情感、等级变化；未变化时走另一分支 |
| `log_memory_saved(npc)` | 打印记忆保存确认 |
| `log_dialogue_end()` | 打印"对话完成"并空一行 |

### view_logs.py

- 路径固定为 `backend/logs/dialogue_<今天>.log`
- `tail` 会 `seek(0, 2)` 到文件末尾再持续 `readline`
- `list` 用 `glob("dialogue_*.log")` 按修改时间倒序列出

---

## 📋 常见问题

### Q1: 日志文件在哪里?

**A:** `backend/logs/dialogue_YYYY-MM-DD.log`。目录在 `logger.py` 被 import 时自动创建。

### Q2: 为什么启动后 logs 里没有文件?

**A:** 因为 `agents.py` 还没调用 logger，模块根本没被 import。接入后（见"如何接入"）文件就会自动生成。

### Q3: 日志文件会占用很多空间吗?

**A:** 不大。每轮对话约 0.5-1 KB，100轮约 50-100 KB，一天通常不超过 1 MB。而且按日期分文件，不会无限追加到同一个文件里。

### Q4: 可以查看历史日志吗?

**A:** 可以，`python view_logs.py list` 看有哪些；要看某一天的内容，把 `view_logs.py` 顶部的日期改成那一天，或用编辑器直接打开对应文件。

---

## ✅ 总结

### 现状

1. ✅ **模块完整** - logger.py 的书写/双输出/按日分文件都已实现
2. ⚠️ **尚未接线** - agents.py 未调用，日志暂时为空
3. ✅ **查看工具可用** - view_logs.py 的 tail/view/list 可正常跑

### 使用建议

1. **开发调试** - 接入 logger 后看控制台，能一眼定位卡在哪步
2. **学习分析** - 用 `view_logs.py view` 复盘一整天的对话
3. **演示教学** - 用 `python view_logs.py tail` 现场滚动展示

---

## 🎉 开始使用

### 步骤1: 启动后端服务

```bash
cd backend
python main.py
```

### 步骤2: 运行Godot游戏

在Godot编辑器中运行游戏（F5）

### 步骤3: 与NPC对话

走到NPC附近,按E键开始对话

### 步骤4: 查看日志

**选项A: 查看控制台**
- 在运行 `python main.py` 的终端窗口查看

**选项B: 查看日志文件**
```bash
cd backend
python view_logs.py tail
```

---

**祝你使用愉快!** 🎮✨📝
