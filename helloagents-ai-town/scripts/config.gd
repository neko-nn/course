# 赛博小镇 - 全局配置
extends Node

# ==================== API配置 ====================
# 必须用 127.0.0.1，不要用 localhost（Windows 会先解析 IPv6 ::1，导致约 30 秒卡顿）
const API_BASE_URL = "http://127.0.0.1:8000"
const API_CHAT = API_BASE_URL + "/chat"
const API_NPCS = API_BASE_URL + "/npcs"
const API_NPC_STATUS = API_BASE_URL + "/npcs/status"
const API_AFFINITIES = API_BASE_URL + "/affinities"      # 【新增】四位专家的好感度总表
const API_AFFINITY_PREFIX = API_BASE_URL + "/npcs/"      # 【新增】拼 /npcs/<名字>/affinity
const API_HEALTH = API_BASE_URL + "/"

# 请求超时(秒)
const CHAT_TIMEOUT = 120.0
const STATUS_TIMEOUT = 8.0
const LIST_TIMEOUT = 8.0

# ==================== NPC配置 ====================
const NPC_NAMES = ["子涵", "芷涵", "子晗", "子寒", "梓涵"]
const NPC_TITLES = {
	"子涵": "天气学家",
	"芷涵": "爱旅行的大学生",
	"子晗": "美食品鉴家",
	"子寒": "小众音乐人",
	"梓涵": "专业导游"
}

# ==================== 游戏配置 ====================
const PLAYER_SPEED = 200.0
const INTERACTION_DISTANCE = 80.0
const NPC_STATUS_UPDATE_INTERVAL = 5.0   # 前端轮询间隔(后端有缓存，很便宜)

# ==================== 碰撞分层 ====================
const LAYER_WALL = 1
const LAYER_PLAYER = 2
const LAYER_NPC = 4
# 角色「身体占位」层：只挡其他角色，不挡墙(所以不会改变墙的贴身手感)
const LAYER_NPC_GUARD = 8
const LAYER_PLAYER_GUARD = 16
# 脚底碰撞盒(俯视角只用脚底，视觉与手感才一致)
const PLAYER_FEET_SIZE = Vector2(24, 14)
const PLAYER_FEET_OFFSET = Vector2(0, 30)
const NPC_FEET_SIZE = Vector2(22, 14)
const NPC_FEET_OFFSET = Vector2(0, 27)
const NPC_INTERACT_RADIUS = 60.0
# 玩家是否被NPC身体挡住(1=只被墙挡；5=墙+NPC；13=墙+NPC+NPC身体占位)
const PLAYER_MASK = LAYER_WALL | LAYER_NPC | LAYER_NPC_GUARD

# ==================== UI配置 ====================
const DIALOGUE_FADE_TIME = 0.3
const NPC_LABEL_OFFSET = Vector2(0, -60)
const NPC_BUBBLE_DURATION = 10.0
const NPC_BUBBLE_WIDTH = 190.0

# 【新增】好感度等级配色（与后端 get_affinity_level 的五个等级一一对应）
const AFFINITY_LEVEL_COLORS = {
	"陌生": "#7f9aa3",
	"熟悉": "#5fd0e6",
	"友好": "#6ee7a8",
	"亲密": "#ffc45c",
	"挚友": "#ff86b8"
}
# 【新增】不记录好感度的NPC（后端 agents.chat 对梓涵跳过打分）
const AFFINITY_EXCLUDED = ["梓涵"]

# ==================== 调试配置 ====================
const DEBUG_MODE = true
const SHOW_INTERACTION_RANGE = true
const DEBUG_KEY_LOG = false      # 按键刷屏日志
const DEBUG_SOUND_LOG = false    # 走路音效刷屏日志
const DEBUG_AREA_LOG = false     # Area进入/离开刷屏日志

# ==================== 工具函数 ====================
func log_info(message: String) -> void:
	if DEBUG_MODE:
		print("[INFO] ", message)

func log_error(message: String) -> void:
	print("[ERROR] ", message)

func log_api(endpoint: String, data: Dictionary) -> void:
	if DEBUG_MODE:
		print("[API] ", endpoint, " -> ", JSON.stringify(data))