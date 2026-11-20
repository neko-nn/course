# 赛博小镇 - 安装配置指南

## 📋 系统要求

- **操作系统:** Windows 10/11, macOS, Linux
- **Godot:** 4.x（工程按4.x特性配置，建议用同版本打开）
- **Python:** 3.10+
- **Git:** (可选,用于克隆项目)

## 🚀 安装步骤

### 步骤1: 下载项目

**方法A: 使用Git**
```bash
git clone <项目仓库地址>
cd Helloagents-AI-Town
```

**方法B: 下载ZIP**
1. 下载项目ZIP文件
2. 解压到任意目录

### 步骤2: 安装Godot

1. 访问 [Godot官网](https://godotengine.org/download)
2. 下载与工程配置一致的Godot 4.x版本
3. 解压并运行Godot

### 步骤3: 配置Python环境

#### 3.1 创建虚拟环境
```bash
cd backend
python -m venv venv
```

#### 3.2 激活虚拟环境
**Windows:**
```bash
venv\Scripts\activate
```

**macOS/Linux:**
```bash
source venv/bin/activate
```

#### 3.3 安装依赖
```bash
pip install -r requirements.txt
```

#### 3.4 关于AI框架
本项目的智能体能力由自带的 `core/` 模块实现（Agent、ReActAgent、ContextBuilder、MessageBus、MemoryManager），**不需要额外安装外部Agent框架**。

### 步骤4: 配置环境变量

#### 4.1 创建环境变量文件
项目未附带 `.env.example`，直接在 `backend/` 下新建 `.env`:
```bash
cd backend
# 手动新建 .env 文件
```

#### 4.2 编辑.env文件
```env
# LLM配置（OpenAI兼容接口，默认ModelScope） - 请填写你的API密钥
LLM_MODEL_ID=Qwen/Qwen2.5-72B-Instruct
LLM_API_KEY=sk-your-api-key-here
LLM_BASE_URL=https://api-inference.modelscope.cn/v1/
LLM_TIMEOUT=30

# 向量库（长期记忆，可不填）
QDRANT_URL=your-qdrant-url
QDRANT_API_KEY=your-qdrant-key

# Embedding（向量化，Qdrant使用时必须）
EMBED_API_KEY=your-dashscope-key

# 联网搜索（景点/美食/音乐工具）
TAVILY_API_KEY=your-tavily-key
```

**重要:** 请将 `LLM_API_KEY` 替换为你的实际API密钥。只填LLM相关键即可跑通对话；Qdrant/Embedding 不填时会自动降级为纯本地模式（档案照常保存，向量回忆不可用）。

**说明:** `API_HOST`、`API_PORT`、`NPC_UPDATE_INTERVAL` 写在 `config.py` 里，不从 `.env` 读取，需要改端口/频率请直接改代码。

### 步骤5: 启动后端服务

```bash
cd backend
python main.py
```

**预期输出:**
```
============================================================
🎮 赛博小镇后端服务启动中...
============================================================
✅ 所有服务已启动!
📡 API地址: http://127.0.0.1:8000
📚 API文档: http://127.0.0.1:8000/docs
============================================================

INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

看到 `✅ 所有服务已启动!` 与 `Uvicorn running on http://0.0.0.0:8000` 就表示成功；紧接着各NPC会初始化记忆，连不上Qdrant时会打印"降级为纯本地模式"。

### 步骤6: 打开Godot项目

1. 启动Godot
2. 点击"导入"
3. 选择 `Helloagents-AI-Town/helloagents-ai-town/project.godot`（选工程根，不要直接选 main.tscn）
4. 点击"导入并编辑"

### 步骤7: 运行游戏

1. 在Godot编辑器中,点击右上角的"运行"按钮 (或按F5)
2. 游戏窗口应该打开（默认1280×720）
3. 使用WASD移动,E键与NPC交互

## 🎮 游戏操作

- **WASD / 方向键** - 移动玩家
- **E**（或Enter/Space） - 与NPC交互
- **Enter** - 发送消息（输入框里直接回车；中文输入法选词时按一次是选中候选词，再按一次才发送）
- **TAB** - 打开/关闭「关系档案」面板，看四位专家的好感度
- **ESC** - 关闭对话框

## 🧪 测试

### 测试后端API
访问: http://127.0.0.1:8000/docs （Swagger，可直接"Try it out"逐条试接口）

建议顺序:
1. `GET /health` - 健康检查
2. `GET /npcs` - 是否有5个NPC
3. `POST /chat` - 与子涵对话
4. `GET /npcs/interactions?since=0` - 协作事件流

### 体验导游协作
在游戏里找到梓涵（引导台），输入「帮我规划西湖一日游」，观察右上角HUD与对话框里的协作时间线。

### 查看对话日志
```bash
cd backend
python view_logs.py list
```
> 注意: 当前 `agents.py` 未调用 `logger.py` 里的日志函数，日志文件里暂时没有内容，接入方法见 [DIALOGUE_LOG_GUIDE.md](DIALOGUE_LOG_GUIDE.md)。

## ❓ 常见问题

### Q1: 后端启动失败?
**A:** 检查:
1. Python版本是否>=3.10
2. 是否激活了虚拟环境
3. 是否安装了所有依赖（缺 `openai` / `qdrant-client` / `tavily-python` 会直接导入失败）
4. 8000端口是否被占用
5. .env文件是否配置正确

### Q2: Godot无法打开项目?
**A:** 检查:
1. Godot版本是否为4.x
2. project.godot文件是否存在
3. 是否选择的是 `helloagents-ai-town/` 目录或 `project.godot`，而不是单个场景文件

### Q3: 游戏运行但无法对话?
**A:** 检查:
1. 后端服务是否正在运行
2. `scripts/config.gd` 中 `API_BASE_URL` 是否为 `http://127.0.0.1:8000`（不要用 localhost）
3. 查看Godot的 Output 面板是否有 `[API] ... 请求失败` 之类的错误
4. 是否在NPC交互半径外按了E

### Q4: 对话很慢或提示走神?
**A:** LLM单次超时为30秒（`LLM_TIMEOUT`），导游协作一轮可能要问多位专家，前端对话请求超时设为180秒。若频繁走神，检查 `LLM_BASE_URL` 与网络。

## 🎉 开始体验!

现在你可以在游戏中与NPC对话了!
