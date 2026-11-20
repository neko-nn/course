# 🎮 赛博小镇 - GDScript脚本说明

## 📁 脚本文件列表

```
scripts/
├── config.gd          # 全局配置(AutoLoad: Config)
├── api_client.gd      # API通信客户端(AutoLoad: APIClient)
├── player.gd          # 玩家控制
├── npc.gd             # NPC行为(气泡/巡逻/协作行走/闲置动画)
├── dialogue_ui.gd     # 对话UI(含好感度条/回车发送)
├── consult_hud.gd     # 导游协作链路HUD
├── affinity_panel.gd  # 关系档案面板(TAB开关)
└── main.gd            # 主场景逻辑 + 协作演出导演
```

---

## 📄 脚本详解

### 1. config.gd (全局配置)
**用途**: 存储全局常量和配置，并作为 AutoLoad 单例 `Config` 供所有脚本访问

**关键配置**:
```gdscript
const API_BASE_URL = "http://127.0.0.1:8000"   # 必须用127.0.0.1，不要用localhost
const PLAYER_SPEED = 200.0                     # 玩家默认速度
const NPC_STATUS_UPDATE_INTERVAL = 5.0          # NPC状态轮询间隔配置项
const NPC_INTERACT_RADIUS = 60.0                # NPC交互半径
```

**碰撞分层**:
```gdscript
const LAYER_WALL = 1
const LAYER_PLAYER = 2
const LAYER_NPC = 4
const LAYER_NPC_GUARD = 8        # 角色身体占位，只挡角色不挡墙
const LAYER_PLAYER_GUARD = 16
const PLAYER_FEET_SIZE = Vector2(24, 14)   # 脚底碰撞盒
const PLAYER_FEET_OFFSET = Vector2(0, 30)
const NPC_FEET_SIZE = Vector2(22, 14)
const NPC_FEET_OFFSET = Vector2(0, 27)
const PLAYER_MASK = LAYER_WALL | LAYER_NPC | LAYER_NPC_GUARD
```

**NPC名称与职位**:
```gdscript
const NPC_NAMES = ["子涵", "芷涵", "子晗", "子寒", "梓涵"]
const NPC_TITLES = {
    "子涵": "天气学家", "芷涵": "爱旅行的大学生", "子晗": "美食品鉴家",
    "子寒": "小众音乐人", "梓涵": "专业导游"
}
```

**调试开关**: `DEBUG_MODE`、`SHOW_INTERACTION_RANGE`、`DEBUG_KEY_LOG`、`DEBUG_SOUND_LOG`、`DEBUG_AREA_LOG`

**使用方法**:
```gdscript
# 在任何脚本中访问
Config.log_info("消息")
var speed = Config.PLAYER_SPEED
```

---

### 2. api_client.gd (API客户端)
**用途**: 与FastAPI后端通信

**主要方法**:
- `send_chat(npc_name, message)` - 发送对话（同一时间只允许一条在途请求）
- `get_npc_status()` - 获取NPC状态（连续3次失败后自动停15秒）
- `get_npc_list()` - 获取NPC列表
- `poll_interactions(since)` - 拉取导游协作事件（`GET /npcs/interactions?since=`）
- `get_affinity(npc_name)` / `get_all_affinities()` - 取单个 / 四位专家好感度（单槽请求，忙时排队）
- `request_last_seq()` - 用 `?since=999999999` 只取"服务器现在到哪了"，给协作演出定水位线

**信号**:
- `chat_response_received(npc_name, message)` - 收到对话回复
- `chat_error(error_message)` - 对话错误
- `npc_status_received(dialogues)` - 收到NPC状态
- `npc_list_received(npcs)` - 收到NPC列表
- `consult_events_received(events, last_seq)` - 收到协作事件
- `affinity_received(npc_name, score, level, modifier)` - 单个NPC好感度
- `affinities_received(affinities)` - 四位专家好感度总表
- `events_seq_received(last_seq)` - 协作事件水位线

**超时设置**（`_ready` 中）:
| 请求 | 超时 |
|------|------|
| 对话 `/chat` | 180秒 |
| 状态 `/npcs/status` | 8秒 |
| 列表 `/npcs` | 8秒 |
| 协作事件 `/npcs/interactions` | 5秒 |
| 好感度 `/affinity`、`/affinities` | 5秒（装饰性数据，失败静默） |
| 水位线 `/npcs/interactions?since=999999999` | 5秒 |

**使用示例**:
```gdscript
# 获取API客户端(AutoLoad)
var api = get_node("/root/APIClient")

# 发送对话
api.send_chat("子涵", "今天天气怎么样")

# 监听回复
api.chat_response_received.connect(_on_response)

func _on_response(npc_name, message):
    print(npc_name + ": " + message)
```

---

### 3. player.gd (玩家控制)
**用途**: 处理玩家移动和交互

**关键功能**:
- `ui_left/ui_right/ui_up/ui_down` 移动（工程里同时映射了WASD、方向键和摇杆）
- `E` / `Enter` / `ui_accept` 与最近NPC交互
- 维护 `_nearby` 列表并每帧取最近的NPC
- 交互中冻结移动并停止走路音效

**节点要求**:
```
Player (CharacterBody2D)
├── AnimatedSprite2D        # idle / turn / walk_down / walk_left / walk_right / walk_up
├── CollisionShape2D        # 代码里会替换成脚底碰撞盒
├── Camera2D                # top_level = true
├── InteractSound (AudioStreamPlayer)
├── RunningSound (AudioStreamPlayer)
└── BodyGuard (StaticBody2D)  # 只挡其他角色
```

**自定义参数**:
```gdscript
@export var speed: float = 200.0  # main.tscn 里实例被覆盖为 100.56
```

---

### 4. npc.gd (NPC行为)
**用途**: NPC交互范围、头顶气泡、巡逻、协作行走、闲置随机动作

**关键功能**:
- 检测玩家进入/离开交互范围（Area2D body_entered/body_exited）
- 独立气泡状态机: `IDLE → FADE_IN → HOLD → FADE_OUT`（打字机逐字显示，不走 await 计时器，所以不会互相顶掉）
- `show_thinking()` / `hide_thinking()`: 协作时显示"正在思考·"
- `focus_answer()` / `release_answer_focus()` / `is_answer_focused()`: 被导游咨询时冻结巡逻，`_physics_process` 里走"站定"分支——`velocity` 归零、只播 `_play_idle()` 待机动画，不会再一边被问一边乱走；问答结束后由 main.gd 释放
- `walk_path(path, speed)`: 按路径点行走，配合 main.gd 的路由绕开中厅横墙
- 闲置动作抽签: 40% 发呆、30% 喝咖啡、30% 拉二胡（没有对应动画则回退 `idle`）
- 巡逻: `wander_range <= 0` 时自动关闭巡逻，原地待机

**节点要求**:
```
NPC (CharacterBody2D)
├── AnimatedSprite2D
├── CollisionShape2D
├── InteractionArea (Area2D)
│   └── CollisionShape2D
├── NameLabel (Label)
├── DialogueLabel (Label)      # 已弃用，运行时隐藏
└── BodyGuard (StaticBody2D)   # collision_layer = 8
```
> 运行时还会动态创建 `InteractionHint`（按E交互）和气泡 `PanelContainer`。

**导出参数**:
```gdscript
@export var npc_name: String = "张三"
@export var npc_title: String = "Python工程师"
@export var sprite_frames: SpriteFrames = null
@export var move_speed: float = 50.0
@export var wander_enabled: bool = true
@export var wander_range: float = 200.0
@export var wander_interval_min: float = 3.0
@export var wander_interval_max: float = 8.0
@export var wander_rect: Rect2 = Rect2(0, 0, 0, 0)
@export var interact_radius: float = 62.0
@export var accent_color: Color = Color(0, 0, 0, 0)
```

**使用方法**:
1. 在Inspector中设置NPC名字、职位、精灵帧、活动范围
2. `accent_color` 留空时按名字自动取专属色（子涵青、芷涵粉、子晗琥珀、子寒绿、梓涵蓝）
3. 脚本自动处理碰撞分层、交互范围、气泡与交互逻辑

---

### 5. dialogue_ui.gd (对话UI)
**用途**: 对话界面管理

**关键功能**:
- 显示/隐藏对话框，锁定玩家与NPC移动
- 处理玩家输入（Enter发送、ESC关闭）
- RichTextLabel 输出对话历史，墨青主题（面板/按钮/输入框/滚动条全部重绘）
- 右上角状态栏: 普通NPC显示"对方思考中 00:12"，梓涵显示"协作中 00:12 · 已发起 N / 已回复 M"
- 好感度条: 名字右侧 200×8 进度条 + 「41 · 友好」，五档配色，变化量 0.8 秒滚动 + `+N` 浮字；梓涵显示「导游 · 不记录好感度」
- 协作时间线: `consult_step()` / `consult_reply()` / `consult_end()`

**节点要求**:
```
DialogueUI (CanvasLayer)
└── Panel
    ├── NPCName (Label)
    ├── NPCTitle (Label)
    ├── AffinityBar (ProgressBar)
    ├── AffinityLabel (Label)
    ├── DialogueText (RichTextLabel)
    ├── PlayerInput (LineEdit)
    ├── SendButton (Button)
    └── CloseButton (Button)
```

**回车发送**: `text_submitted` 之外还挂了 `player_input.gui_input`，监听到 Enter 后 `call_deferred("_try_send_from_input")`。两条路都留着是因为中文输入法在选词时会把 Enter 吃掉、`text_submitted` 不一定触发；同一次按键里先到的那条会清空输入框，后到的那条看见空文本直接返回，不会重复发送。

**使用方法**:
```gdscript
# 开始对话（player.gd 就是这么调的）
get_tree().call_group("dialogue_system", "start_dialogue", "子涵")
```

---

### 6. consult_hud.gd (导游协作链路HUD)
**用途**: 把「梓涵 → 四位专家」的多智能体通信实时画出来

**关键功能**:
- 右上角面板（372×252）: 节点、流动光点、进度条、耗时、当前问答
- 四个专家节点状态: `IDLE / ASKING / DONE / FAIL`
- 目标在屏幕外时，屏幕边缘给出指向箭头
- 所有文字用 Label 绘制，图形用 `_draw` 自绘（避免中文缺字）

**对外接口**:
```gdscript
open_session(experts)            # 开始一次协作会话
set_status(npc_name, state)      # 设置单个专家状态
set_active(npc_name)             # 高亮当前正在被咨询的专家
set_counts(asked, done)          # 提问/回复计数
set_footer(text)                 # 底部提示语
set_elapsed(sec)                 # 计时器
close_session(success)           # 结束并淡出
set_pointer(screen_pos, on, col, text)  # 屏幕外指示箭头
```

**加载方式**: 不需要在场景里挂节点，`main.gd` 的 `_build_hud()` 运行时 `load("res://scripts/consult_hud.gd")` 并挂到一个 `CanvasLayer`（layer=5）。

---

### 7. affinity_panel.gd (关系档案面板)
**用途**: 一个键看全四位专家的好感度，不用逐个对话

**关键功能**:
- 按 `TAB` 开关；位于左上角 320×300 的 Control（CanvasLayer）
- 每位专家一行: 名字、等级、分值、进度条；`EXPERTS = ["子涵","芷涵","子晗","子寒"]`（梓涵不打分，不在列表）
- 打开时请求一次 `/affinities`，打开期间每 10 秒刷新；`affinity_received` / `chat_response_received` 也会触发刷新
- 输入框有焦点时 TAB 不抢，留给 LineEdit 插入制表符
- 文字用 Label 绘制，节点坐标相对面板自身，避免双重偏移

**加载方式**: `main.gd` 的 `_build_affinity_panel()` 运行时 `load("res://scripts/affinity_panel.gd")` 挂到 `CanvasLayer`（layer=4，比协作HUD的5低一层）。

---

### 8. main.gd (主场景 / 协作导演)
**用途**: 管理整个游戏场景，并把后端事件流变成可见演出

**关键功能**:
- 每10秒轮询 `/npcs/status`，把碎碎念分发到各NPC（错峰播放：最多2个气泡同时存在，最小间隔1.15秒）
- 协作期间每0.35秒轮询 `/npcs/interactions`；开对话时先向 `?since=999999999` 要一个水位线，水位线以下的历史事件一律不演，避免回放上一局的旧记录
- **走到才开口**：收到 `asking` 先让梓涵走到专家旁的"站位点"（专家外 44px，且避开中厅横墙），到位（≤52px）才喊问题、专家才弹"正在思考"。答案先到也先存着，到位后延后 0.9 秒播；卡死 1.2 秒或 5~14 秒兜底也会开口
- 专家被约即 `focus_answer()`：站定播待机动画，不再一边被问一边巡逻；会话结束时 `release_answer_focus()`
- 地图路由 `_route()`: 上厅(y<231)和下厅之间只能从 x>818 绕行，上下都沿 x=862 那条竖线换高度，再横向接近目标（避免贴着 y=320 横墙或下厅斜墙被顶住）
- 会话结束（成功/失败）后先释放锁再走回原位；另有 0.5 秒一次的看门狗，发现梓涵不在协作中却离原位 >24px 且没在走路，重发回位路径（最多 3 次）；3 次都被地形挡住且仍差 40px 以上时，用 0.18 秒淡出→换位→淡入把她送回引导台（只在卡死时触发，避免永远停在半路）
- 专家节点位置每帧复查：`_node_of()` 失效、专家走动导致站位点过期都会重算/直接开口，不会僵死

**关键常量**:
```gdscript
const POLL_INTERVAL := 10.0      # NPC状态轮询
const EVENT_INTERVAL := 0.35     # 协作事件轮询
const MAX_CONCURRENT_BUBBLES := 2
const MIN_START_GAP := 1.15
const TRUNK_Y := 320.0
const GATE_X := 862.0
const UPPER_Y := 231.0
const CONSULT_SPEED := 175.0
const EXPERT_ORDER := ["子涵", "芷涵", "子晗", "子寒"]
const GUIDE_ARRIVE_DIST := 52.0   # 判定"已经站到专家旁边"
const GUIDE_STAND_OFFSET := 44.0  # 站位点离专家多远
```

**节点要求**:
```
Main (Node2D)
├── Background (Sprite2D)
├── Player (实例化 player.tscn)
├── NPCs (Node2D)
│   ├── NPC_A  子涵(709,213)
│   ├── NPC_B  芷涵(548,138)
│   ├── NPC_C  子晗(1179,362)
│   ├── NPC_D  子寒(171,308)
│   └── NPC_D2 梓涵(813,570)
├── DialogueUI (实例化 dialogue_ui.tscn)
├── Walls (StaticBody2D)
├── AudioStreamPlayer (BGM.ogg, autoplay)
└── Borders (StaticBody2D)
```
> NPC 的登记不靠节点名，而是遍历 `npcs` 分组并按 `npc_name` 建槽位，所以增删NPC不用改 main.gd。

---

## 🔧 如何使用这些脚本

### 步骤1: AutoLoad（工程已配置好）
`project.godot` 中已注册:
- `Config` → `res://scripts/config.gd`
- `APIClient` → `res://scripts/api_client.gd`

如换新工程，在 `Project -> Project Settings -> AutoLoad` 中补上这两项即可。

### 步骤2: 附加脚本到场景
- `player.tscn` → `player.gd`
- `npc.tscn` → `npc.gd`
- `dialogue_ui.tscn` → `dialogue_ui.gd`
- `main.tscn` → `main.gd`
- `consult_hud.gd` 由 main.gd 运行时动态加载，不挂场景
- `affinity_panel.gd` 由 main.gd 运行时动态加载（layer=4），不挂场景

### 步骤3: 配置节点
确保每个场景的节点结构与脚本要求一致（碰撞盒尺寸由脚本在 `_ready` 里重设，无需手改）。

### 步骤4: 设置参数
在Inspector中设置导出参数（NPC名字、职位、精灵帧、活动范围、速度等）。

---

## 🐛 调试技巧

### 查看日志
所有脚本都使用 `Config.log_info()` 输出日志，在Godot的 **Output** 面板查看。

### 常见日志:
```
[INFO] API客户端初始化完成 -> http://127.0.0.1:8000
[INFO] 玩家初始化完成
[INFO] NPC初始化: 子涵
[INFO] 可交互NPC: 子涵
[API] POST /chat -> {"npc_name":"子涵","message":"今天天气怎么样"}
[INFO] 收到NPC回复(2.4s): 子涵
[INFO] 🔒 玩家进入交互状态,移动已禁用
🛑 玩家退出交互状态,移动已启用
```

### 启用调试模式
在 `config.gd` 中:
```gdscript
const DEBUG_MODE = true            # 显示详细日志
const SHOW_INTERACTION_RANGE = true # 显示交互范围
const DEBUG_KEY_LOG = false        # 按键刷屏日志
const DEBUG_SOUND_LOG = false      # 走路音效刷屏日志
```

---

## 📊 信号流程图

### 普通对话
```
玩家按E键
    ↓
player.gd: interact_with_npc()
    ↓
call_group("dialogue_system", "start_dialogue", npc_name)
    ↓
dialogue_ui.gd: start_dialogue(npc_name) → 锁定玩家/NPC
    ↓
玩家输入消息 → send_message()
    ↓
call_group("consult_director", "on_chat_started", ...)   # 通知导演
    ↓
api_client.gd: send_chat(npc_name, message)
    ↓
POST /chat（后端同步def，线程池执行）
    ↓
api_client.gd: _on_chat_request_completed()
    ↓
信号 chat_response_received
    ↓
dialogue_ui.gd: _on_chat_response_received() → 显示回复 + 刷新好感度条
    ↓
GET /npcs/{name}/affinity（后端先更新档案再返回，此刻即最新值）
    ↓
api_client.gd: affinity_received → dialogue_ui.gd: _on_affinity_received()
```

### 导游协作
```
玩家问梓涵宏观问题
    ↓
POST /chat（梓涵 ReActAgent 调 ask_npc）
    ↓
AskNPCTool 推 asking / answered 事件
    ↓
前端每0.35s poll_interactions(since)
    ↓
main.gd: _handle_asking() → 记下目标/问题，梓涵沿 _route 走向站位点
    ↓           走到（≤52px）才喊问题；专家 show_thinking() + focus_answer()（站定播待机）
    ↓
main.gd: _handle_answered() → 答案先入队，梓涵到位后延后 0.9 秒由专家弹出 + 梓涵"记下了"
    ↓
consult_hud.gd 更新节点状态 / 进度 / 计时
dialogue_ui.gd 追加协作时间线
    ↓
后端 /chat 返回 → main.gd: _on_chat_finished() → 梓涵走回引导台
```

---

## 🎯 扩展建议

### 添加新NPC
1. 在 `main.tscn` 的 `NPCs` 下实例化 `npc.tscn`
2. 设置 `npc_name`（与后端一致）、`npc_title`、精灵帧、位置
3. 在 `npc.gd` / `dialogue_ui.gd` 的 `ACCENTS` 里补一个主题色（不补会自动用默认青色）
4. 不需要改 main.gd（槽位按 `npcs` 分组自动建立）

### 添加新功能
1. 在 `config.gd` 中添加配置
2. 在 `api_client.gd` 中添加新API方法（记得配一个 HTTPRequest 和超时）
3. 在相应脚本中实现逻辑

### 优化性能
1. 调大 `main.gd` 的 `POLL_INTERVAL`（状态轮询从10秒放宽）
2. 气泡数量受 `MAX_CONCURRENT_BUBBLES` 限制，可再调小
3. 缩小 `NPC` 的 `wander_range` 减少移动计算

---

## 📚 参考资源

- **Godot文档**: https://docs.godotengine.org/
- **GDScript教程**: https://gdscript.com/
- **FastAPI文档**: https://fastapi.tiangolo.com/

---

## ❓ 常见问题

**Q: 如何修改API地址?**
A: 编辑 `config.gd` 中的 `API_BASE_URL`（保持 `127.0.0.1`，用 `localhost` 在Windows上可能先解析IPv6导致卡顿）

**Q: 如何添加更多NPC?**
A: 实例化 `npc.tscn`、设置参数；后端还要在 `NPC_ROLES` 里登记，否则对话接口会返回"小镇里没有叫XX的人"

**Q: 如何自定义对话框样式?**
A: 颜色常量在 `dialogue_ui.gd` 顶部（INK / SURFACE / LINE / TEXT / MUTED / GUIDE），`_apply_theme()` 里统一套用

**Q: 如何禁用调试日志?**
A: 在 `config.gd` 中设置 `DEBUG_MODE = false`

**Q: NPC为什么站着不动?**
A: `wander_range <= 0` 会关闭巡逻（main.tscn 里子晗、子寒、梓涵就是0），只播放闲置动画

**Q: 子寒为什么不主动搭话?**
A: 双重约束——后端提示词有"绝对不主动开启对话"，前端 `main.gd` 的 `PROFILES` 里子寒是 `quiet: true`、发言权重0.45
