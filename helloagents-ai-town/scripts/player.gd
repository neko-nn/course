# 玩家控制脚本
extends CharacterBody2D

@export var speed: float = 200.0

# 当前可交互的NPC(每帧取最近的一个)
var nearby_npc: Node = null
var _nearby: Array[Node] = []

var is_interacting: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D

var interact_sound: AudioStreamPlayer = null
var running_sound: AudioStreamPlayer = null
var is_playing_running_sound: bool = false

func _ready():
	add_to_group("player")
	_setup_collision()

	interact_sound = get_node_or_null("InteractSound")
	running_sound = get_node_or_null("RunningSound")

	Config.log_info("玩家初始化完成")
	camera.enabled = true
	if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation("idle"):
		animated_sprite.play("idle")

# 碰撞分层 + 脚底碰撞盒（不用改tscn）
func _setup_collision() -> void:
	collision_layer = Config.LAYER_PLAYER   # 2
	collision_mask = Config.PLAYER_MASK     # 1 = 只被墙挡住
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		var rect := RectangleShape2D.new()   # 新建，避免改到共享资源
		rect.size = Config.PLAYER_FEET_SIZE
		cs.shape = rect
		cs.position = Config.PLAYER_FEET_OFFSET

func _physics_process(_delta: float):
	_update_nearest_npc()

	if is_interacting:
		velocity = Vector2.ZERO
		move_and_slide()
		if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.play("idle")
		stop_running_sound()
		return

	var input_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_direction * speed
	move_and_slide()
	update_animation(input_direction)
	update_running_sound(input_direction)

# ==================== 附近NPC管理 ====================
func add_nearby_npc(npc: Node) -> void:
	if is_instance_valid(npc) and not _nearby.has(npc):
		_nearby.append(npc)

func remove_nearby_npc(npc: Node) -> void:
	_nearby.erase(npc)

func set_nearby_npc(npc: Node) -> void:
	# 兼容旧接口
	if npc == null:
		_nearby.clear()
	else:
		add_nearby_npc(npc)

func _update_nearest_npc() -> void:
	var best: Node = null
	var best_d := INF
	for n in _nearby:
		if not is_instance_valid(n):
			continue
		var d := global_position.distance_squared_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	_nearby = _nearby.filter(func(n): return is_instance_valid(n))
	if best != nearby_npc:
		nearby_npc = best
		if nearby_npc != null:
			Config.log_info("可交互NPC: " + nearby_npc.npc_name)

func get_nearby_npc() -> Node:
	return nearby_npc

# ==================== 动画 ====================
func update_animation(direction: Vector2):
	if animated_sprite.sprite_frames == null:
		return
	if direction.length() > 0:
		if abs(direction.x) > abs(direction.y):
			if direction.x > 0:
				_play("walk_right", false)
			else:
				_play("walk_left", true)
		else:
			if direction.y > 0:
				_play("walk_down", false)
			else:
				_play("walk_up", false)
	else:
		if animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.play("idle")

func _play(anim: String, flip: bool) -> void:
	if animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.play(anim)
		animated_sprite.flip_h = false
	elif animated_sprite.sprite_frames.has_animation("walk"):
		animated_sprite.play("walk")
		animated_sprite.flip_h = flip

# ==================== 输入 ====================
func _input(event: InputEvent):
	# 【新增】对话中（E/Enter 正在被输入框使用）不再触发交互，否则回车发送会被
	# 这里截走重新 start_dialogue，输入框被清空，看起来就是"回车发不出去"
	if is_interacting:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if Config.DEBUG_KEY_LOG:
			print("[DEBUG] 按键: ", event.keycode)
		if event.keycode == KEY_E or event.keycode == KEY_ENTER or event.is_action_pressed("ui_accept"):
			if nearby_npc != null:
				interact_with_npc()
			else:
				print("[WARN] 没有附近的NPC可以交互")

func interact_with_npc():
	if nearby_npc == null:
		return
	if interact_sound:
		interact_sound.play()
	Config.log_info("与NPC交互: " + nearby_npc.npc_name)
	get_tree().call_group("dialogue_system", "start_dialogue", nearby_npc.npc_name)

func set_interacting(interacting: bool):
	is_interacting = interacting
	if interacting:
		print("[INFO] 🔒 玩家进入交互状态,移动已禁用")
		stop_running_sound()
	else:
		print("[INFO] 🔓 玩家退出交互状态,移动已启用")

# ==================== 音效 ====================
func update_running_sound(direction: Vector2):
	if running_sound == null:
		return
	if direction.length() > 0:
		if not is_playing_running_sound:
			running_sound.play()
			is_playing_running_sound = true
			if Config.DEBUG_SOUND_LOG:
				print("[INFO] 🎵 开始播放走路音效")
	else:
		stop_running_sound()

func stop_running_sound():
	if running_sound and is_playing_running_sound:
		running_sound.stop()
		is_playing_running_sound = false
		if Config.DEBUG_SOUND_LOG:
			print("[INFO] 🔇 停止走路音效")
