extends Node2D
## 主场景 + 【新增】导游协作导演
## 玩家问导游一个问题后，这里把后端真实的 ask_npc 事件流变成可见的演出：
## 梓涵绕开中厅的墙走到专家面前 → 提问气泡 → 专家「正在思考…」→ 真实答案气泡
## → 走向下一位 → 全部问完走回引导台；同时右上角 HUD 画出整条协作链路，
## 目标不在画面里时屏幕边缘给出指向箭头。碎碎念依旧错峰播放，不会齐刷刷。

const POLL_INTERVAL := 10.0
const EVENT_INTERVAL := 0.35          # 协作事件轮询间隔
const MAX_CONCURRENT_BUBBLES := 2
const MIN_START_GAP := 1.15
const FIRST_SPREAD := Vector2(0.8, 8.0)
const FRESH_SPREAD := Vector2(0.4, 9.0)
const AMBIENT_CHANCE := 0.5

# 地图路由：中厅横墙 x39~818 / y231~306，上下厅只能从 x>818 绕行，
# 而 y306~335 之间有一条窄通道，脚底碰撞盒刚好能过。
const TRUNK_Y := 320.0
const GATE_X := 862.0
const UPPER_Y := 231.0
const CONSULT_SPEED := 175.0

const PROFILES := {
	"子涵": {"gap": Vector2(7.0, 14.0), "weight": 1.00, "quiet": false},
	"芷涵": {"gap": Vector2(5.5, 11.0), "weight": 1.20, "quiet": false},
	"子晗": {"gap": Vector2(8.0, 15.0), "weight": 0.95, "quiet": false},
	"子寒": {"gap": Vector2(15.0, 27.0), "weight": 0.45, "quiet": true},
	"梓涵": {"gap": Vector2(9.0, 18.0), "weight": 0.80, "quiet": false},
}
const DEFAULT_PROFILE := {"gap": Vector2(8.0, 16.0), "weight": 1.0, "quiet": false}

const AMBIENT := {
	"子涵": ["（抬头看了看云脚）", "（在本子上记下一组气压）", "（把望远镜转向湖面）"],
	"芷涵": ["（把相机举向断桥）", "（翻着皱巴巴的地图）", "（哼着歌沿湖边走）"],
	"子晗": ["（用小勺敲了敲杯沿）", "（低头闻了闻桂花香）", "（把甜点摆正了一点）"],
	"子寒": ["（调了调二胡的弦）", "（把谱子翻回上一页）", "（极轻地试了一个音）"],
	"梓涵": ["（整理手里的行程单）", "（抬头看了看引导台）", "（在图上圈了一个点）"],
}

const EXPERT_ORDER := ["子涵", "芷涵", "子晗", "子寒"]

var api_client: Node = null
var _slots: Dictionary = {}
var _names: Array[String] = []
var _cursor: int = 0
var _clock: float = 0.0
var _poll_timer: float = 0.0
var _last_start: float = -999.0

# 协作会话
var _hud: Control = null
var _hud_layer: CanvasLayer = null
var _aff_panel: Control = null          # 【新增】关系档案面板
var _aff_layer: CanvasLayer = null      # 【新增】
var _consult_active: bool = false
var _consult_elapsed: float = 0.0
var _event_timer: float = 0.0
var _last_seq: int = 0
var _baselining: bool = true
var _asked: int = 0
var _done: int = 0
var _active_target: String = ""
var _simple_wait_npc: String = ""

# 【新增】"走到才开口"的演出暂存
const GUIDE_ARRIVE_DIST := 52.0      # 判定"已经站在专家旁边"的距离
const GUIDE_STAND_OFFSET := 44.0     # 站位点：站在专家身边而不是压在他身上
var _stage_target: String = ""        # 正在走向的专家
var _stage_question: String = ""      # 到了之后要喊的问题
var _stage_stand: Vector2 = Vector2.ZERO
var _stage_t: float = 0.0
var _stage_timeout: float = 2.5
var _stage_reply: String = ""         # 还没到就先到的答案
var _stage_reply_ok: bool = true
var _stage_has_reply: bool = false
var _stage_last_pos: Vector2 = Vector2.ZERO   # 卡死检测
var _stage_stuck: float = 0.0

# 【新增】到得比答案晚时，答案延后 0.9 秒播，让"去问"那句先被看见
var _queued_answer_on: bool = false
var _queued_answer_t: float = 0.0
var _queued_answer_target: String = ""
var _queued_answer_reply: String = ""
var _queued_answer_ok: bool = true

# 【新增】回原位的看门狗
var _home_check_t: float = 0.0
var _home_retry: int = 0
var _returning_home: bool = false
var _home_snapping: bool = false


func _ready() -> void:
	print("[INFO] 主场景初始化")
	add_to_group("consult_director")
	_build_slots()
	_build_hud()
	_build_affinity_panel()
	api_client = get_node_or_null("/root/APIClient")
	if api_client != null:
		api_client.npc_status_received.connect(_on_npc_status_received)
		api_client.consult_events_received.connect(_on_consult_events)
		api_client.events_seq_received.connect(_on_events_seq)          # 【新增】开对话先定水位线
		api_client.chat_response_received.connect(_on_chat_finished)
		api_client.chat_error.connect(_on_chat_failed)
		api_client.get_npc_status()
		api_client.poll_interactions(0)      # 取基线 seq，避免回放历史事件
	else:
		print("[ERROR] API客户端未找到")


func _build_slots() -> void:
	_slots.clear()
	_names.clear()
	for npc in get_tree().get_nodes_in_group("npcs"):
		if not is_instance_valid(npc):
			continue
		var n: String = str(npc.npc_name)
		if n.is_empty() or _slots.has(n):
			continue
		_names.append(n)
		_slots[n] = {
			"node": npc,
			"next_at": _clock + randf_range(FIRST_SPREAD.x, FIRST_SPREAD.y),
			"pending": "", "backend_text": "", "was_active": false,
		}
	_names.shuffle()


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 5
	add_child(_hud_layer)
	var script_res: Resource = load("res://scripts/consult_hud.gd")
	_hud = Control.new()
	_hud.set_script(script_res)
	_hud_layer.add_child(_hud)


# 【新增】关系档案面板（TAB 开关），比HUD低一层，同屏互不遮挡
func _build_affinity_panel() -> void:
	_aff_layer = CanvasLayer.new()
	_aff_layer.layer = 4
	add_child(_aff_layer)
	_aff_panel = Control.new()
	_aff_panel.set_script(load("res://scripts/affinity_panel.gd"))
	_aff_layer.add_child(_aff_panel)


func _node_of(n: String) -> Node:
	if _slots.has(n):
		return _slots[n]["node"]
	return null


func _process(delta: float) -> void:
	_clock += delta
	if _names.is_empty():
		_build_slots()

	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		if api_client != null:
			api_client.get_npc_status()

	if _consult_active and not _baselining:
		_consult_elapsed += delta
		_event_timer += delta
		if _event_timer >= EVENT_INTERVAL:
			_event_timer = 0.0
			if api_client != null:
				api_client.poll_interactions(_last_seq)
		if _hud != null and _hud.visible:
			_hud.set_elapsed(_consult_elapsed)
			_update_pointer()
	elif _simple_wait_npc != "":
		_consult_elapsed += delta

	_tick_slots()
	_tick_stage(delta)            # 【新增】走到位再开口
	_tick_queued_answer(delta)    # 【新增】答案延后播
	_tick_home_watchdog(delta)    # 【新增】问完押回原位


func _update_pointer() -> void:
	if _active_target == "" or _hud == null:
		_hud.set_pointer(Vector2.ZERO, false, Color.WHITE, "")
		return
	var target: Node = _node_of(_active_target)
	if target == null or not is_instance_valid(target):
		_hud.set_pointer(Vector2.ZERO, false, Color.WHITE, "")
		return
	var vp: Viewport = get_viewport()
	var world_pos: Vector2 = target.global_position
	var screen: Vector2 = vp.get_canvas_transform() * world_pos
	var rect: Rect2 = vp.get_visible_rect()
	var inside: bool = rect.grow(-70.0).has_point(screen)
	var col: Color = target.get_accent()
	_hud.set_pointer(screen, not inside, col, "梓涵正在找 " + _active_target)


# ==================== 会话入口（由 dialogue_ui 调用） ====================
func on_chat_started(npc_name: String, _message: String) -> void:
	_consult_elapsed = 0.0
	if npc_name != "梓涵":
		_simple_wait_npc = npc_name
		var n: Node = _node_of(npc_name)
		if n != null and is_instance_valid(n):
			n.show_thinking()
		return

	_consult_active = true
	_asked = 0
	_done = 0
	_active_target = ""
	_clear_stage()
	_home_retry = 0
	_returning_home = false
	_baselining = true
	_event_timer = EVENT_INTERVAL
	if api_client != null:
		api_client.request_last_seq()      # 【新增】只问水位线，不回放历史事件

	var experts: Array = []
	for e in EXPERT_ORDER:
		var node: Node = _node_of(e)
		if node == null:
			continue
		experts.append({"name": e, "title": str(node.npc_title), "color": node.get_accent()})
	if _hud != null:
		_hud.open_session(experts)
		_hud.set_footer("梓涵正在拆解你的需求…")

	var guide: Node = _node_of("梓涵")
	if guide != null and is_instance_valid(guide):
		guide.say("这个问题我去问问几位专家，稍等一下", 4.0, false, true)


func _on_consult_events(events: Array, last_seq: int) -> void:
	if _baselining:
		_last_seq = maxi(_last_seq, last_seq)
		_baselining = false
		return
	if not _consult_active:
		_last_seq = maxi(_last_seq, last_seq)
		return
	var floor_seq: int = _last_seq
	_last_seq = maxi(_last_seq, last_seq)
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		# 【新增】水位线以下都是历史事件（比如 since=0 的回放），不能当成"刚刚发生"来演，
		# 否则梓涵会照着上一局的旧记录跑到别的专家面前问旧问题
		if int(e.get("seq", 0)) <= floor_seq:
			continue
		var phase: String = str(e.get("phase", ""))
		var target: String = str(e.get("target", ""))
		var question: String = str(e.get("question", ""))
		var reply: String = str(e.get("reply", ""))
		var ok: bool = bool(e.get("ok", true))
		if phase == "asking":
			_handle_asking(target, question)
		elif phase == "answered":
			_handle_answered(target, reply, ok)


func _on_events_seq(last_seq: int) -> void:
	# 【新增】水位线到了，从这一刻开始才认真实事件
	if not _consult_active:
		return
	_last_seq = maxi(_last_seq, last_seq)
	_baselining = false
	_event_timer = 0.0
	if api_client != null:
		api_client.poll_interactions(_last_seq)


func _handle_asking(target: String, question: String) -> void:
	_asked += 1
	_active_target = target
	var guide: Node = _node_of("梓涵")
	var expert: Node = _node_of(target)
	if guide == null or expert == null:
		return
	if not is_instance_valid(guide) or not is_instance_valid(expert):
		return

	# 上一段还没走到就来了新的咨询：先把上一段落地，别把台词吞掉
	_flush_stage()

	# 【新增】专家一被约就站定：不然这 3~6 秒里它还在巡逻，
	# 站位点算的是它"刚才"的位置，梓涵走过去人已经挪开了，距离判断全乱
	if expert.has_method("focus_answer"):
		expert.focus_answer()

	# 【新增】走到"站位点"（专家身边 44px），不是压到专家身上，
	# 否则两个碰撞体会互相顶住，梓涵停在很远的地方就算"到了"
	var stand: Vector2 = _stand_pos(expert, guide)
	guide.walk_path(_route(guide.global_position, stand), CONSULT_SPEED)

	_stage_target = target
	_stage_question = question
	_stage_stand = stand
	_stage_t = 0.0
	_stage_has_reply = false
	_stage_reply = ""
	_stage_last_pos = guide.global_position
	_stage_stuck = 0.0
	# 兜底：给足时间，宁可晚一点也走过去再开口（真人速度下正常 2~4 秒就到）
	_stage_timeout = clampf(guide.global_position.distance_to(stand) / CONSULT_SPEED * 3.0 + 2.0, 5.0, 14.0)

	if _hud != null:
		_hud.set_status(target, 1)
		_hud.set_active(target)
		_hud.set_counts(_asked, _done)
		_hud.set_footer("→ " + target + "：" + _clip(question, 24))
	get_tree().call_group("dialogue_system", "consult_step", target, question)


func _handle_answered(target: String, reply: String, ok: bool) -> void:
	_done += 1
	# 【新增】梓涵还在路上？答案先存着，等他站到专家旁边再一起演，
	# 避免出现"隔着半张地图"的回答气泡
	if _stage_target == target:
		_stage_reply = reply
		_stage_reply_ok = ok
		_stage_has_reply = true
	else:
		_show_answer(target, reply, ok)
	if _hud != null:
		_hud.set_status(target, 2 if ok else 3)
		_hud.set_counts(_asked, _done)
		_hud.set_footer("← " + target + "：" + _clip(reply, 24))
	get_tree().call_group("dialogue_system", "consult_reply", target, reply, ok)


# ==================== 【新增】"走到才开口"的演出调度 ====================
func _stand_pos(expert: Node, guide: Node) -> Vector2:
	var away: Vector2 = guide.global_position - expert.global_position
	if away.length() < 1.0:
		away = Vector2(0.0, 1.0)
	var side: float = 44.0 if guide.global_position.x >= expert.global_position.x else -44.0
	var p: Vector2 = expert.global_position + away.normalized() * GUIDE_STAND_OFFSET
	# NPC 的脚底碰撞盒是 22×14、中心在 origin 下方 27px（即 y+20 ~ y+34），
	# 站位点必须让整个碰撞盒躲开中厅横墙（y 231~306），否则梓涵会顶着墙根卡住，
	# 卡住检测一丢路点，人还在半路就开口了。
	if expert.global_position.y < UPPER_Y:
		if p.y > UPPER_Y - 37.0:      # 194：脚底上沿 214，仍在墙上沿之上
			p = Vector2(expert.global_position.x + side, UPPER_Y - 37.0)
	else:
		if p.y < 306.0 + 14.0 + 27.0: # 288：脚底上沿刚好压到墙下沿以下
			p = Vector2(expert.global_position.x + side, 306.0 + 14.0 + 27.0)
	return p


func _tick_stage(delta: float) -> void:
	if _stage_target == "":
		return
	var guide: Node = _node_of("梓涵")
	var expert: Node = _node_of(_stage_target)
	if guide == null or expert == null or not is_instance_valid(guide) or not is_instance_valid(expert):
		_flush_stage()
		return
	_stage_t += delta
	var d: float = guide.global_position.distance_to(expert.global_position)
	# 1) 到身边了（站位点就在专家外 44px，52 足够判断）
	if d <= GUIDE_ARRIVE_DIST:
		_flush_stage()
		return
	# 2) 路走完了（被墙/被NPC顶住，卡住检测会丢路点）也算到位，别一直不开口
	if not guide.is_consult_walking() and _stage_t > 0.35:
		_flush_stage()
		return
	# 3) 人卡住不动 1.2 秒：说明路被挡死，开口总比僵在原地好
	if guide.global_position.distance_to(_stage_last_pos) < 2.0:
		_stage_stuck += delta
		if _stage_stuck > 1.2:
			_flush_stage()
			return
	else:
		_stage_stuck = 0.0
		_stage_last_pos = guide.global_position
	# 4) 最后兜底：走太久也开口，防止演出卡死在"走"
	if _stage_t >= _stage_timeout:
		_flush_stage()


func _flush_stage() -> void:
	if _stage_target == "":
		return
	var target: String = _stage_target
	var question: String = _stage_question
	_stage_target = ""
	_stage_question = ""
	var guide: Node = _node_of("梓涵")
	var expert: Node = _node_of(target)
	if guide != null and is_instance_valid(guide):
		guide.say("去问 " + target + "：" + _clip(question, 26), 5.0, false, true)
	if expert != null and is_instance_valid(expert):
		expert.show_thinking()
		if expert.has_method("focus_answer"):
			expert.focus_answer()       # 【新增】站定播待机动画，别一边被问一边乱走
	if _stage_has_reply:
		var reply: String = _stage_reply
		var ok: bool = _stage_reply_ok
		_stage_has_reply = false
		_stage_reply = ""
		# 答案早就到了：延后一点再弹，别把刚喊出的"去问 …"直接顶掉
		_queued_answer_on = true
		_queued_answer_t = 0.9
		_queued_answer_target = target
		_queued_answer_reply = reply
		_queued_answer_ok = ok


func _tick_queued_answer(delta: float) -> void:
	if not _queued_answer_on:
		return
	_queued_answer_t -= delta
	if _queued_answer_t > 0.0:
		return
	_queued_answer_on = false
	_show_answer(_queued_answer_target, _queued_answer_reply, _queued_answer_ok)
	_queued_answer_target = ""
	_queued_answer_reply = ""


func _show_answer(target: String, reply: String, ok: bool) -> void:
	var expert: Node = _node_of(target)
	if expert != null and is_instance_valid(expert):
		expert.say(_clip(reply, 34), 5.5, false, true)
	var guide: Node = _node_of("梓涵")
	if guide != null and is_instance_valid(guide):
		guide.say("记下了 ✓", 2.2, true, true)


func _clear_stage() -> void:
	_stage_target = ""
	_stage_question = ""
	_stage_has_reply = false
	_stage_reply = ""
	_stage_t = 0.0
	_queued_answer_on = false
	_queued_answer_target = ""
	_queued_answer_reply = ""


# ==================== 【新增】回原位 ====================
func _guide_go_home() -> void:
	var guide: Node = _node_of("梓涵")
	if guide == null or not is_instance_valid(guide):
		return
	var post: Vector2 = guide.get_post_position()
	if guide.global_position.distance_to(post) <= 6.0:
		_returning_home = false
		return
	guide.walk_path(_route(guide.global_position, post), CONSULT_SPEED)
	_returning_home = true


func _tick_home_watchdog(delta: float) -> void:
	_home_check_t += delta
	if _home_check_t < 0.5:
		return
	_home_check_t = 0.0
	if _consult_active:
		return
	var guide: Node = _node_of("梓涵")
	if guide == null or not is_instance_valid(guide):
		return
	var post: Vector2 = guide.get_post_position()
	var dist: float = guide.global_position.distance_to(post)
	if dist <= 24.0:
		_returning_home = false
		_home_retry = 0
		return
	if guide.is_consult_walking():
		return
	if _home_snapping:
		return
	# 正常已经发过回位路径；这里只补"回调没触发/路点被丢光"的情况
	if _home_retry < 3:
		_home_retry += 1
		guide.walk_path(_route(guide.global_position, post), CONSULT_SPEED)
		_returning_home = true
		print("[INFO] 梓涵回位重试 ", _home_retry)
	elif dist > 40.0:
		# 三次重走都被地形挡住：淡出淡入"挪"回引导台，
		# 比一直杵在专家旁边更像正常收场（只在被卡死时才会发生）
		_snap_home(guide, post)


func _snap_home(guide: Node, post: Vector2) -> void:
	_home_snapping = true
	guide.stop_consult_walk()
	var tw: Tween = create_tween()
	tw.tween_property(guide, "modulate:a", 0.0, 0.18)
	tw.tween_callback(_place_guide_at.bind(guide, post))
	tw.tween_property(guide, "modulate:a", 1.0, 0.18)
	tw.tween_callback(_finish_snap)


func _place_guide_at(guide: Node, post: Vector2) -> void:
	if not is_instance_valid(guide):
		return
	guide.global_position = post
	guide.velocity = Vector2.ZERO
	print("[INFO] 梓涵被地形卡住，已淡入淡出送回引导台")


func _finish_snap() -> void:
	_home_snapping = false
	_home_retry = 0
	_returning_home = false


func _on_chat_finished(npc_name: String, _message: String) -> void:
	if npc_name != "梓涵":
		if _simple_wait_npc == npc_name:
			_simple_wait_npc = ""
		var n: Node = _node_of(npc_name)
		if n != null and is_instance_valid(n):
			n.hide_thinking()
		return
	if not _consult_active:
		return
	_consult_active = false
	_active_target = ""
	_clear_stage()
	var guide: Node = _node_of("梓涵")
	if guide != null and is_instance_valid(guide):
		guide.say("都问清楚了，攻略给你整理好了", 4.5, false, true)
	for e in EXPERT_ORDER:
		var node: Node = _node_of(e)
		if node != null and is_instance_valid(node) and node.is_bubble_active():
			pass
	if _hud != null:
		_hud.set_pointer(Vector2.ZERO, false, Color.WHITE, "")
		_hud.close_session(true)
	get_tree().call_group("dialogue_system", "consult_end", _done, _consult_elapsed)
	_release_consult_locks()
	# 【新增】先放开锁再发回位路径，避免刚发的路点被清掉
	_guide_go_home()


func _on_chat_failed(error_message: String) -> void:
	if _simple_wait_npc != "":
		var n: Node = _node_of(_simple_wait_npc)
		if n != null and is_instance_valid(n):
			n.hide_thinking()
		_simple_wait_npc = ""
	if not _consult_active:
		return
	_consult_active = false
	_active_target = ""
	_clear_stage()
	var guide: Node = _node_of("梓涵")
	if guide != null and is_instance_valid(guide):
		guide.say("抱歉，这趟没问明白…", 4.0, false, true)
	if _hud != null:
		_hud.set_pointer(Vector2.ZERO, false, Color.WHITE, "")
		_hud.set_footer(_clip(error_message, 30))
		_hud.close_session(false)
	get_tree().call_group("dialogue_system", "consult_end", _done, _consult_elapsed)
	_release_consult_locks()
	_guide_go_home()   # 【新增】失败也押回原位


func _release_consult_locks() -> void:
	for e in EXPERT_ORDER:
		var node: Node = _node_of(e)
		if node != null and is_instance_valid(node):
			node.stop_consult_walk()
			if node.has_method("release_answer_focus"):
				node.release_answer_focus()   # 【新增】解除站定，恢复原来的巡逻/待机
		if _slots.has(e):
			_slots[e]["next_at"] = _clock + randf_range(4.0, 10.0)
	if _slots.has("梓涵"):
		_slots["梓涵"]["next_at"] = _clock + randf_range(8.0, 14.0)


# ==================== 地图路由 ====================
func _route(from: Vector2, to: Vector2) -> Array:
	var pts: Array = []
	var from_up: bool = from.y < UPPER_Y
	var to_up: bool = to.y < UPPER_Y
	if from_up != to_up:
		if to_up:
			# 【修正】先横着走到门口，再往上穿窄通道。
			# 原来第一步是"在自己的 x 上先爬到 TRUNK_Y"，只要 from.x < GATE_X
			# 就会贴着横墙下沿蹭，碰撞体一顶就卡住，卡住检测丢点后又斜切，
			# 结果人还在拐角外面，时间就到了——看起来就是"远远地问了一句"。
			pts.append(Vector2(GATE_X, from.y))
			pts.append(Vector2(GATE_X, TRUNK_Y))
			pts.append(Vector2(GATE_X, to.y))
		else:
			# 同理：先沿着门口那条竖线降到目标所在的高度，再横着过去。
			# 原来在 TRUNK_Y 就横移到目标 x，下厅靠墙那段（约 x≈812、y≈430）
			# 有块斜墙，梓涵会正好顶在那里，人回不去引导台
			pts.append(Vector2(GATE_X, from.y))
			pts.append(Vector2(GATE_X, TRUNK_Y))
			pts.append(Vector2(GATE_X, to.y))
	pts.append(to)
	return pts


func _clip(text: String, n: int) -> String:
	var t: String = text.replace("\n", " ").strip_edges()
	if t.length() <= n:
		return t
	return t.substr(0, n) + "…"


# ==================== 碎碎念（错峰调度） ====================
func _on_npc_status_received(dialogues: Dictionary) -> void:
	if _names.is_empty():
		_build_slots()
	var fresh: Array[String] = []
	for key in dialogues:
		var n: String = str(key)
		if not _slots.has(n):
			continue
		var text: String = str(dialogues[key]).strip_edges()
		if text.is_empty():
			continue
		if n == "梓涵" and text.begins_with("[[ASK|"):
			_slots[n]["backend_text"] = text
			continue      # 协作演出已由实时事件流接管，不再走 30 秒延迟的旧表演
		if text == _slots[n]["backend_text"]:
			continue
		_slots[n]["backend_text"] = text
		_slots[n]["pending"] = text
		fresh.append(n)
	fresh.shuffle()
	for n in fresh:
		var want: float = _clock + randf_range(FRESH_SPREAD.x, FRESH_SPREAD.y)
		_slots[n]["next_at"] = minf(float(_slots[n]["next_at"]), want)


func _tick_slots() -> void:
	if _names.is_empty():
		return
	var active := 0
	for n in _names:
		var s: Dictionary = _slots[n]
		var node: Node = s["node"]
		if not is_instance_valid(node):
			continue
		var now_active: bool = node.is_bubble_active()
		if now_active:
			active += 1
		if bool(s["was_active"]) and not now_active:
			var p: Dictionary = PROFILES.get(n, DEFAULT_PROFILE)
			var gap: Vector2 = p["gap"]
			var w: float = maxf(0.2, float(p["weight"]))
			s["next_at"] = _clock + randf_range(gap.x, gap.y) / w
		s["was_active"] = now_active

	if active >= MAX_CONCURRENT_BUBBLES or _clock - _last_start < MIN_START_GAP:
		return

	var count: int = _names.size()
	for i in range(count):
		var idx: int = (_cursor + i) % count
		var n2: String = _names[idx]
		var s2: Dictionary = _slots[n2]
		var node2: Node = s2["node"]
		if not is_instance_valid(node2):
			continue
		if _clock < float(s2["next_at"]):
			continue
		if _is_blocked(n2, node2):
			s2["next_at"] = _clock + randf_range(1.5, 3.5)
			continue
		var prof: Dictionary = PROFILES.get(n2, DEFAULT_PROFILE)
		var pending: String = str(s2["pending"])
		var spoke := false
		if not pending.is_empty():
			spoke = node2.say(pending, -1.0, bool(prof["quiet"]))
			if spoke:
				s2["pending"] = ""
		else:
			if randf() <= AMBIENT_CHANCE * float(prof["weight"]):
				var line: String = _pick_ambient(n2, node2.get_last_shown_text())
				if not line.is_empty():
					spoke = node2.say(line, -1.0, true)
			if not spoke:
				var g: Vector2 = prof["gap"]
				s2["next_at"] = _clock + randf_range(g.x, g.y) * 0.6
		if spoke:
			s2["was_active"] = true
			_last_start = _clock
			_cursor = (idx + 1) % count
			return


func _is_blocked(n: String, node: Node) -> bool:
	if bool(node.is_interacting) and n != "梓涵":
		return true
	if node.is_consult_walking():
		return true
	if _consult_active and (n == "梓涵" or n == _active_target):
		return true
	if _simple_wait_npc == n:
		return true
	return false


func _pick_ambient(n: String, last_text: String) -> String:
	var pool: Array = AMBIENT.get(n, [])
	if pool.is_empty():
		return ""
	var candidates: Array = []
	for line in pool:
		if str(line) != last_text:
			candidates.append(str(line))
	if candidates.is_empty():
		return ""
	return str(candidates[randi() % candidates.size()])
