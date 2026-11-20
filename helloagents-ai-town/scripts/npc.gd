extends CharacterBody2D
## NPC：外观 / 巡逻 / 交互范围 / 头顶气泡
## 【新增】协作演出能力：按路径点行走（会绕开中厅那道墙）、思考中气泡、专属色。
## 气泡为独立状态机（淡入→打字机→停留→淡出），不用 await 计时器，
## 因此不会互相顶掉，也不会出现「同时亮、同时灭」。

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

const LAYER_WALL := 1
const LAYER_PLAYER := 2
const LAYER_NPC := 4
const FEET_SIZE := Vector2(22, 14)
const FEET_OFFSET := Vector2(0, 27)
const UPPER_RECT := Rect2(55, 105, 1180, 115)
const LOWER_RECT := Rect2(55, 315, 690, 230)

const BUBBLE_MIN_W := 118.0
const BUBBLE_MAX_W := 244.0
const FADE_IN := 0.24
const FADE_OUT := 0.34
const CHARS_PER_SEC := 26.0
const RISE := 7.0
const HEAD_GAP := 66.0

const ACCENTS := {
	"子涵": Color("#5fd0e6"),
	"芷涵": Color("#ff86b8"),
	"子晗": Color("#ffc45c"),
	"子寒": Color("#9be07a"),
	"梓涵": Color("#8ea6ff"),
}

enum BubbleState { IDLE, FADE_IN, HOLD, FADE_OUT }

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var name_label: Label = $NameLabel

var current_dialogue: String = ""
var is_interacting: bool = false
var is_npc_interacting: bool = false
var npc_interacting_target: Node = null
var player: Node = null
var interaction_hint: Label = null

var wander_target: Vector2 = Vector2.ZERO
var wander_timer: float = 0.0
var is_wandering: bool = false
var spawn_position: Vector2 = Vector2.ZERO
var _stuck_time: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

# 【新增】协作行走
var _consult_path: Array = []
var _consult_speed: float = 170.0
var _consult_stuck: float = 0.0

# 【新增】被咨询/回答期间站定不动，播放待机动画
var _answer_focus: bool = false

# ⭐【新增】闲置随机动作变量
var _idle_action_timer: float = 0.0
var _current_idle_action: String = "idle"

var _accent: Color = Color("#5fd0e6")
var _bubble: PanelContainer = null
var _bubble_label: Label = null
var _bubble_tail: Polygon2D = null
var _bubble_state: int = BubbleState.IDLE
var _bubble_t: float = 0.0
var _bubble_hold: float = 4.0
var _bubble_chars: float = 0.0
var _bubble_total: int = 0
var _bubble_quiet: bool = false
var _bubble_needs_layout: bool = false
var _bubble_base_pos: Vector2 = Vector2.ZERO
var _last_shown_text: String = ""
var _thinking: bool = false
var _think_t: float = 0.0
var _think_dots: int = 0

func _ready() -> void:
	add_to_group("npcs")
	spawn_position = global_position
	_accent = accent_color if accent_color.a > 0.0 else ACCENTS.get(npc_name, Color("#5fd0e6"))
	name_label.text = npc_name
	name_label.add_theme_color_override("font_color", _accent.lightened(0.22))
	name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.07, 0.9))
	name_label.add_theme_constant_override("outline_size", 4)

	_setup_collision()
	_setup_hint()
	_setup_bubble()

	var old_label: Node = get_node_or_null("DialogueLabel")
	if old_label != null:
		old_label.visible = false

	if wander_rect.size == Vector2.ZERO:
		wander_rect = UPPER_RECT if spawn_position.y < 231.0 else LOWER_RECT
	if wander_range <= 0.0:
		wander_enabled = false

	if sprite_frames != null:
		animated_sprite.sprite_frames = sprite_frames
	# ⭐ 初始化时强制换一次动作
	play_random_idle_action(true)

	if wander_enabled:
		wander_timer = randf_range(wander_interval_min, wander_interval_max)
		choose_new_wander_target()
	_last_pos = global_position
	Config.log_info("NPC初始化: " + npc_name)


func get_accent() -> Color:
	return _accent

func get_post_position() -> Vector2:
	return spawn_position

func _setup_collision() -> void:
	collision_layer = LAYER_NPC
	collision_mask = LAYER_WALL
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null:
		var rect := RectangleShape2D.new()
		rect.size = FEET_SIZE
		cs.shape = rect
		cs.position = FEET_OFFSET
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = LAYER_WALL | LAYER_PLAYER
	interaction_area.monitorable = false
	var ics: CollisionShape2D = interaction_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if ics != null:
		var circle := CircleShape2D.new()
		circle.radius = interact_radius
		ics.shape = circle
		ics.position = Vector2(0, 10)
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

func _setup_hint() -> void:
	interaction_hint = get_node_or_null("InteractionHint") as Label
	if interaction_hint == null:
		interaction_hint = Label.new()
		interaction_hint.name = "InteractionHint"
		interaction_hint.text = "按E交互"
		interaction_hint.add_theme_font_size_override("font_size", 12)
		interaction_hint.add_theme_color_override("font_color", _accent.lightened(0.35))
		interaction_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		interaction_hint.add_theme_constant_override("outline_size", 4)
		interaction_hint.position = Vector2(-28, -78)
		interaction_hint.z_index = 110
		interaction_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(interaction_hint)
	interaction_hint.visible = false

func _setup_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.z_index = 120
	_bubble.visible = false
	_bubble.modulate.a = 0.0
	_bubble_tail = Polygon2D.new()
	_bubble_tail.color = Color(0.043, 0.086, 0.11, 0.92)
	_bubble.add_child(_bubble_tail)
	_bubble_label = Label.new()
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_label.visible_characters = 0
	_bubble.add_child(_bubble_label)
	add_child(_bubble)
	_apply_bubble_style(false)

func _apply_bubble_style(quiet: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.086, 0.11, 0.92) if not quiet else Color(0.035, 0.07, 0.09, 0.80)
	sb.border_color = Color(_accent.r, _accent.g, _accent.b, 0.60 if not quiet else 0.32)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.set_content_margin_all(8)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.shadow_color = Color(0, 0, 0, 0.38)
	sb.shadow_size = 5
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble_tail.color = sb.bg_color
	_bubble_label.add_theme_font_size_override("font_size", 12 if quiet else 14)
	_bubble_label.add_theme_color_override("font_color",
		Color(0.78, 0.87, 0.83, 1.0) if quiet else Color(0.97, 0.99, 1.0, 1.0))
	_bubble_label.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.04, 0.85))
	_bubble_label.add_theme_constant_override("outline_size", 3)

func say(text: String, hold: float = -1.0, quiet: bool = false, force: bool = false) -> bool:
	text = text.strip_edges()
	if text.is_empty():
		return false
	if _bubble_state != BubbleState.IDLE and not force:
		return false
	_thinking = false
	_bubble_quiet = quiet
	_bubble_total = text.length()
	_bubble_chars = 0.0
	_bubble_label.text = text
	_bubble_label.visible_characters = 0
	_bubble_label.custom_minimum_size = Vector2(
		clampf(40.0 + float(_bubble_total) * 12.5, BUBBLE_MIN_W, BUBBLE_MAX_W), 0.0)
	_apply_bubble_style(quiet)
	var auto_hold: float = clampf(2.4 + float(_bubble_total) * 0.135, 3.2, 7.6)
	if quiet:
		auto_hold *= 0.82
	auto_hold *= randf_range(0.9, 1.15)
	var typing: float = float(_bubble_total) / CHARS_PER_SEC
	_bubble_hold = maxf(hold if hold > 0.0 else auto_hold, typing + 1.15)
	_bubble.visible = true
	_bubble.modulate.a = 0.0
	_bubble.reset_size()
	_bubble_needs_layout = true
	_bubble_state = BubbleState.FADE_IN
	_bubble_t = 0.0
	_last_shown_text = text
	current_dialogue = text
	return true

func show_thinking() -> void:
	if not say("正在思考", -1.0, true, true):
		return
	_thinking = true
	_think_t = 0.0
	_think_dots = 0
	_bubble_hold = 100000.0
	_bubble_label.visible_characters = -1

func hide_thinking() -> void:
	_thinking = false
	hide_bubble_now()

func is_bubble_active() -> bool:
	return _bubble_state != BubbleState.IDLE

func get_last_shown_text() -> String:
	return _last_shown_text

func hide_bubble_now() -> void:
	_bubble_state = BubbleState.IDLE
	_bubble_t = 0.0
	_thinking = false
	if is_instance_valid(_bubble):
		_bubble.visible = false
		_bubble.modulate.a = 0.0

func update_dialogue(dialogue: String) -> void:
	current_dialogue = dialogue
	say(dialogue, 7.6)

func show_npc_bubble(text: String, duration: float = 3.0) -> void:
	say(text, duration, false, true)

func get_npc_name() -> String:
	return npc_name

func get_npc_title() -> String:
	return npc_title

func _process(delta: float) -> void:
	if _bubble_state == BubbleState.IDLE or not is_instance_valid(_bubble):
		return
	if _bubble_needs_layout:
		_layout_bubble()
		_bubble_needs_layout = false
	if _thinking:
		_think_t += delta
		if _think_t >= 0.38:
			_think_t = 0.0
			_think_dots = (_think_dots + 1) % 4
			var dots: String = ""
			for i in range(_think_dots):
				dots += "·"
			_bubble_label.text = "正在思考" + dots
			_bubble_label.visible_characters = -1
	_bubble_t += delta
	match _bubble_state:
		BubbleState.FADE_IN:
			var k: float = clampf(_bubble_t / FADE_IN, 0.0, 1.0)
			var e: float = 1.0 - pow(1.0 - k, 3.0)
			_bubble.modulate.a = e * _target_alpha()
			_bubble.position = _bubble_base_pos + Vector2(0.0, RISE * (1.0 - e))
			_advance_reveal(delta)
			if k >= 1.0:
				_bubble_state = BubbleState.HOLD
				_bubble_t = 0.0
		BubbleState.HOLD:
			_advance_reveal(delta)
			if _bubble_t >= _bubble_hold:
				_bubble_state = BubbleState.FADE_OUT
				_bubble_t = 0.0
		BubbleState.FADE_OUT:
			var k2: float = clampf(_bubble_t / FADE_OUT, 0.0, 1.0)
			_bubble.modulate.a = (1.0 - k2) * _target_alpha()
			_bubble.position = _bubble_base_pos + Vector2(0.0, -RISE * 0.5 * k2)
			if k2 >= 1.0:
				_bubble.visible = false
				_bubble_state = BubbleState.IDLE
				_bubble_t = 0.0


func _target_alpha() -> float:
	return 0.84 if _bubble_quiet else 1.0


func _advance_reveal(delta: float) -> void:
	if _thinking or _bubble_label.visible_characters < 0:
		return
	_bubble_chars += delta * CHARS_PER_SEC
	var n: int = int(_bubble_chars)
	if n >= _bubble_total:
		_bubble_label.visible_characters = -1
	else:
		_bubble_label.visible_characters = n


func _layout_bubble() -> void:
	var sz: Vector2 = _bubble.size
	if sz.x <= 1.0:
		sz = Vector2(BUBBLE_MIN_W, 34.0)
	var pos := Vector2(-sz.x * 0.5, -HEAD_GAP - sz.y)
	var vp: Viewport = get_viewport()
	if vp != null:
		var world_rect: Rect2 = vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)
		var min_x: float = world_rect.position.x + 8.0
		var max_x: float = world_rect.end.x - sz.x - 8.0
		if max_x > min_x:
			var gx: float = clampf(global_position.x + pos.x, min_x, max_x)
			pos.x = gx - global_position.x
	_bubble_base_pos = pos
	_bubble.position = pos
	var cx: float = sz.x * 0.5
	_bubble_tail.polygon = PackedVector2Array([
		Vector2(cx - 7.0, sz.y - 1.0), Vector2(cx + 7.0, sz.y - 1.0), Vector2(cx, sz.y + 8.0)])

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	player = body
	if body is PhysicsBody2D:
		add_collision_exception_with(body)
		body.add_collision_exception_with(self)
	if player.has_method("add_nearby_npc"):
		player.add_nearby_npc(self)
	elif player.has_method("set_nearby_npc"):
		player.set_nearby_npc(self)
	if interaction_hint != null:
		interaction_hint.visible = true

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if player != null and is_instance_valid(player):
		if player.has_method("remove_nearby_npc"):
			player.remove_nearby_npc(self)
		elif player.has_method("set_nearby_npc"):
			if player.get("nearby_npc") == self:
				player.set_nearby_npc(null)
	player = null
	if interaction_hint != null:
		interaction_hint.visible = false

func set_interacting(interacting: bool) -> void:
	is_interacting = interacting
	if interacting:
		if _consult_path.is_empty() and not _thinking:
			hide_bubble_now()
	else:
		wander_timer = 0.0

# ⭐【核心补丁】完全替换原来的 _play_idle 逻辑
func play_random_idle_action(force_change: bool = false) -> void:
	# 倒计时，如果没到时间且不是强制换，就不换
	if not force_change:
		_idle_action_timer -= get_physics_process_delta_time()
		if _idle_action_timer > 0:
			return
			
	# 抽签（40% 发呆，30% 喝咖啡，30% 拉二胡）
	var rand_val = randf()
	if rand_val < 0.4:
		_current_idle_action = "idle"
	elif rand_val < 0.7 and animated_sprite.sprite_frames.has_animation("drink_coffee"):
		_current_idle_action = "drink_coffee"
	elif animated_sprite.sprite_frames.has_animation("play_erhu"):
		_current_idle_action = "play_erhu"
	else:
		_current_idle_action = "idle"
		
	# 播放动画
	if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(_current_idle_action):
		animated_sprite.play(_current_idle_action)
	else:
		_play_idle() # 兜底
		
	# 随机设定持续时间
	_idle_action_timer = randf_range(3.0, 6.0)

# 原来的 _play_idle 保留，作为强制的兜底
func _play_idle() -> void:
	_current_idle_action = "idle"
	if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation("idle"):
		animated_sprite.play("idle")


# ==================== 协作行走 ====================
func walk_path(path: Array, speed: float = 170.0) -> void:
	_consult_path = path.duplicate()
	_consult_speed = speed
	_consult_stuck = 0.0
	is_wandering = false
	is_npc_interacting = false

func stop_consult_walk() -> void:
	_consult_path.clear()
	velocity = Vector2.ZERO

func is_consult_walking() -> bool:
	return _consult_path.size() > 0


# 【新增】被导游咨询时进入"站定回答"状态：停掉巡逻、原地播待机动画，
# 否则专家会一边被问一边乱走，玩家看不出来他到底在不在听。
func focus_answer() -> void:
	_answer_focus = true
	is_wandering = false
	wander_timer = 0.0
	velocity = Vector2.ZERO
	_play_idle()


func release_answer_focus() -> void:
	_answer_focus = false
	wander_timer = randf_range(1.0, 3.0)


func is_answer_focused() -> bool:
	return _answer_focus

func _step_consult(delta: float) -> void:
	if _consult_path.is_empty():
		return
	var wp: Vector2 = _consult_path[0]
	if global_position.distance_to(wp) < 12.0:
		_consult_path.remove_at(0)
		if _consult_path.is_empty():
			velocity = Vector2.ZERO
			move_and_slide()
			play_random_idle_action(true) # ⭐ 走完路径后，强制换姿势
		return
	var dir: Vector2 = (wp - global_position).normalized()
	velocity = dir * _consult_speed
	move_and_slide()
	update_animation(dir)
	if global_position.distance_to(_last_pos) < 0.6:
		_consult_stuck += delta
		if _consult_stuck > 1.0:
			_consult_stuck = 0.0
			_consult_path.remove_at(0)
	else:
		_consult_stuck = 0.0
	_last_pos = global_position


# ==================== 移动 ====================
func _physics_process(delta: float) -> void:
	# 1. 协作行走优先
	if not _consult_path.is_empty():
		_step_consult(delta)
		return

	# 2. 交互中强制发呆
	if is_interacting:
		velocity = Vector2.ZERO
		move_and_slide()
		_play_idle()
		return

	# 2.5 【新增】被咨询/正在回答：站定播待机动画，不巡逻、不乱走
	if _answer_focus:
		velocity = Vector2.ZERO
		move_and_slide()
		_play_idle()
		return

	# 3. 走向其他 NPC
	if is_npc_interacting and npc_interacting_target != null and is_instance_valid(npc_interacting_target):
		var target_pos: Vector2 = npc_interacting_target.global_position
		if global_position.distance_to(target_pos) > 60.0:
			var dir2: Vector2 = (target_pos - global_position).normalized()
			velocity = dir2 * move_speed
			move_and_slide()
			update_animation(dir2)
		else:
			velocity = Vector2.ZERO
			move_and_slide()
			play_random_idle_action() # ⭐ 原地等待时随机动作
		return

	# 4. 不巡逻只发呆
	if not wander_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		play_random_idle_action() # ⭐ 原地待机
		return

	# 5. 常规巡逻
	wander_timer -= delta
	if wander_timer <= 0:
		choose_new_wander_target()
		wander_timer = randf_range(wander_interval_min, wander_interval_max)

	if is_wandering:
		if global_position.distance_to(wander_target) < 10.0:
			is_wandering = false
			velocity = Vector2.ZERO
			move_and_slide()
			play_random_idle_action(true) # ⭐ 到达目标后，重新抽签
		else:
			var direction: Vector2 = (wander_target - global_position).normalized()
			velocity = direction * move_speed
			move_and_slide()
			update_animation(direction)
			if global_position.distance_to(_last_pos) < 0.5:
				_stuck_time += delta
				if _stuck_time > 0.6:
					_stuck_time = 0.0
					choose_new_wander_target()
					wander_timer = randf_range(wander_interval_min, wander_interval_max)
			else:
				_stuck_time = 0.0
	else:
		velocity = Vector2.ZERO
		move_and_slide()
		play_random_idle_action() # ⭐ 巡逻间隙的发呆
	_last_pos = global_position


func choose_new_wander_target() -> void:
	var offset := Vector2(randf_range(-wander_range, wander_range), randf_range(-wander_range, wander_range))
	var t: Vector2 = spawn_position + offset
	wander_target = Vector2(
		clampf(t.x, wander_rect.position.x, wander_rect.end.x),
		clampf(t.y, wander_rect.position.y, wander_rect.end.y))
	is_wandering = true


func update_animation(direction: Vector2) -> void:
	if animated_sprite.sprite_frames == null:
		return
	if direction.length() <= 0.0:
		play_random_idle_action()
		return
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0.0:
			_play_walk("walk_right", false)
		else:
			_play_walk("walk_left", true)
	else:
		if direction.y > 0.0:
			_play_walk("walk_down", false)
		else:
			_play_walk("walk_up", false)


func _play_walk(anim: String, flip: bool) -> void:
	if animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.play(anim)
		animated_sprite.flip_h = false
	elif animated_sprite.sprite_frames.has_animation("walk"):
		animated_sprite.play("walk")
		animated_sprite.flip_h = flip


func go_to_other_npc(target_npc: Node) -> void:
	if not is_instance_valid(target_npc):
		return
	is_npc_interacting = true
	npc_interacting_target = target_npc
	is_wandering = false

func stop_npc_interaction() -> void:
	is_npc_interacting = false
	npc_interacting_target = null
	wander_timer = 0.0
