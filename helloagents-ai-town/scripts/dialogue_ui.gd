# 对话UI脚本
extends CanvasLayer
## 【改动】等待回复不再是一行死字：导游咨询期间，这里逐条打印真实的
## 「梓涵 → 子涵 提问 / 子涵 已回复」时间线，右上角还有状态与计时；
## 面板、按钮、输入框、滚动条全部换成小镇自己的墨青配色。

const INK := Color("#0b1418")
const SURFACE := Color("#13242c")
const LINE := Color("#22404c")
const TEXT := Color("#eaf4f6")
const MUTED := Color("#7f9aa3")
const GUIDE := Color("#8ea6ff")
const CYAN := Color("#5fd0e6")
const OK_COL := Color("#6ee7a8")
const BAD_COL := Color("#ff6b6b")
const AMBER := Color("#ffc45c")

const ACCENTS := {
	"子涵": "#5fd0e6", "芷涵": "#ff86b8", "子晗": "#ffc45c",
	"子寒": "#9be07a", "梓涵": "#8ea6ff",
}

@onready var panel: Panel = $Panel
@onready var npc_name_label: Label = $Panel/NPCName
@onready var npc_title_label: Label = $Panel/NPCTitle
@onready var dialogue_text: RichTextLabel = $Panel/DialogueText
@onready var player_input: LineEdit = $Panel/PlayerInput
@onready var send_button: Button = $Panel/SendButton
@onready var close_button: Button = $Panel/CloseButton
@onready var affinity_bar: ProgressBar = $Panel/AffinityBar      # 【新增】好感度进度条
@onready var affinity_label: Label = $Panel/AffinityLabel        # 【新增】好感度文字

var current_npc_name: String = ""
var api_client: Node = null
var _status: Label = null
var _awaiting: bool = false
var _wait_t: float = 0.0
var _consult_steps: int = 0
var _consult_done: int = 0

# 【新增】好感度显示状态
var _aff_score: float = 0.0
var _aff_known: bool = false
var _aff_tween: Tween = null


func _ready() -> void:
	add_to_group("dialogue_system")
	visible = false
	send_button.pressed.connect(_on_send_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)
	player_input.text_submitted.connect(_on_text_submitted)
	player_input.gui_input.connect(_on_player_input_gui_input)   # 【新增】回车发送
	_apply_theme()

	_status = Label.new()
	_status.position = Vector2(880, 16)
	_status.size = Vector2(370, 26)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", MUTED)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_status)

	api_client = get_node_or_null("/root/APIClient")
	if api_client != null:
		api_client.chat_response_received.connect(_on_chat_response_received)
		api_client.chat_error.connect(_on_chat_error)
		api_client.affinity_received.connect(_on_affinity_received)   # 【新增】
	_init_affinity_view()
	print("[INFO] 对话UI初始化完成")


func _apply_theme() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK.r, INK.g, INK.b, 0.96)
	sb.border_color = Color(GUIDE.r, GUIDE.g, GUIDE.b, 0.35)
	sb.border_width_top = 2
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 8
	sb.content_margin_top = 6
	panel.add_theme_stylebox_override("panel", sb)

	npc_name_label.add_theme_color_override("font_color", TEXT)
	npc_title_label.add_theme_color_override("font_color", MUTED)
	dialogue_text.add_theme_color_override("default_color", TEXT)
	dialogue_text.add_theme_font_size_override("normal_font_size", 15)

	var line_normal := StyleBoxFlat.new()
	line_normal.bg_color = SURFACE
	line_normal.border_color = LINE
	line_normal.set_border_width_all(1)
	line_normal.set_corner_radius_all(6)
	line_normal.content_margin_left = 10
	var line_focus := line_normal.duplicate() as StyleBoxFlat
	line_focus.border_color = CYAN
	player_input.add_theme_stylebox_override("normal", line_normal)
	player_input.add_theme_stylebox_override("focus", line_focus)
	player_input.add_theme_color_override("font_color", TEXT)
	player_input.add_theme_color_override("font_placeholder_color", MUTED)
	player_input.add_theme_color_override("caret_color", CYAN)

	_style_button(send_button, GUIDE, true)
	_style_button(close_button, LINE, false)

	# 滚动条也画成小镇自己的样子，而不是系统默认灰条
	var vs: VScrollBar = dialogue_text.get_v_scroll_bar()
	if vs != null:
		vs.custom_minimum_size = Vector2(8, 0)
		var track := StyleBoxFlat.new()
		track.bg_color = Color(1, 1, 1, 0.05)
		track.set_corner_radius_all(4)
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.55)
		thumb.set_corner_radius_all(4)
		var thumb_hi := thumb.duplicate() as StyleBoxFlat
		thumb_hi.bg_color = CYAN
		vs.add_theme_stylebox_override("scroll", track)
		vs.add_theme_stylebox_override("grabber", thumb)
		vs.add_theme_stylebox_override("grabber_highlight", thumb_hi)
		vs.add_theme_stylebox_override("grabber_pressed", thumb_hi)


func _style_button(btn: Button, col: Color, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(col.r, col.g, col.b, 0.22 if primary else 0.12)
	normal.border_color = Color(col.r, col.g, col.b, 0.75)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(col.r, col.g, col.b, 0.42 if primary else 0.22)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(col.r, col.g, col.b, 0.62 if primary else 0.32)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.add_theme_color_override("font_color", TEXT if primary else MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.add_theme_color_override("font_disabled_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.5))


# ==================== 【新增】好感度显示 ====================
func _init_affinity_view() -> void:
	affinity_label.add_theme_font_size_override("font_size", 13)
	affinity_label.add_theme_color_override("font_color", MUTED)
	affinity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_affinity_bar(MUTED)
	affinity_bar.value = 0.0
	affinity_bar.max_value = 100.0
	affinity_bar.show_percentage = false
	affinity_bar.visible = false
	affinity_label.text = ""


func _style_affinity_bar(col: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(4)
	affinity_bar.add_theme_stylebox_override("background", bg)
	affinity_bar.add_theme_stylebox_override("fill", fill)


func _setup_affinity(npc_name: String) -> void:
	if _aff_tween != null and _aff_tween.is_valid():
		_aff_tween.kill()
	_aff_known = false
	_aff_score = 0.0
	affinity_bar.value = 0.0
	if Config.AFFINITY_EXCLUDED.has(npc_name):
		# 梓涵是导游协调者，后端 agents.chat 对她就跳过打分
		affinity_bar.visible = false
		affinity_label.visible = true
		affinity_label.text = "导游 · 不记录好感度"
		affinity_label.add_theme_color_override("font_color", MUTED)
		return
	affinity_bar.visible = true
	affinity_label.visible = true
	affinity_label.text = "好感度 --"
	affinity_label.add_theme_color_override("font_color", MUTED)
	_style_affinity_bar(MUTED)
	if api_client != null:
		api_client.get_affinity(npc_name)


func _refresh_affinity() -> void:
	if api_client == null or current_npc_name.is_empty():
		return
	if Config.AFFINITY_EXCLUDED.has(current_npc_name):
		return
	api_client.get_affinity(current_npc_name)


func _on_affinity_received(npc_name: String, score: float, level: String, modifier: String) -> void:
	if not visible or npc_name != current_npc_name:
		return
	var shown: float = clampf(score, 0.0, 100.0)
	var col: Color = Color(Config.AFFINITY_LEVEL_COLORS.get(level, "#7f9aa3"))
	# 文字显示原始分值（后端档案不裁剪，可能超过100），进度条只画到0-100
	affinity_label.text = "%d · %s" % [int(round(score)), level]
	affinity_label.add_theme_color_override("font_color", col)
	_style_affinity_bar(col)
	if not _aff_known:
		_aff_known = true
		_aff_score = shown
		affinity_bar.value = shown
		return
	var delta: float = shown - _aff_score
	if _aff_tween != null and _aff_tween.is_valid():
		_aff_tween.kill()
	_aff_tween = create_tween()
	_aff_tween.tween_property(affinity_bar, "value", shown, 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if absf(delta) >= 1.0:
		_spawn_delta(delta, col)
	_aff_score = shown


func _spawn_delta(delta: float, col: Color) -> void:
	var l := Label.new()
	if delta > 0.0:
		l.text = "+%d" % int(round(delta))
	else:
		l.text = "%d" % int(round(delta))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col)
	l.position = affinity_bar.position + Vector2(affinity_bar.size.x + 6.0, -8.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(l)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 16.0, 1.0)
	t.tween_property(l, "modulate:a", 0.0, 1.0)
	t.chain().tween_callback(Callable(l, "queue_free"))


func _process(delta: float) -> void:
	if not visible or not _awaiting:
		return
	_wait_t += delta
	var s: int = int(_wait_t)
	var clock: String = "%02d:%02d" % [s / 60, s % 60]
	if current_npc_name == "梓涵":
		_status.text = "协作中 %s · 已发起 %d / 已回复 %d" % [clock, _consult_steps, _consult_done]
		_status.add_theme_color_override("font_color", GUIDE)
	else:
		_status.text = "对方思考中 %s" % clock
		_status.add_theme_color_override("font_color", AMBER)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			hide_dialogue()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if player_input.has_focus():
				return
			send_message()
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_E, KEY_SPACE, KEY_W, KEY_A, KEY_S, KEY_D]:
			get_viewport().set_input_as_handled()


func start_dialogue(npc_name: String) -> void:
	current_npc_name = npc_name
	var npc: Node = get_npc_by_name(npc_name)
	if npc != null and npc.has_method("set_interacting"):
		npc.set_interacting(true)
	npc_name_label.text = npc_name
	npc_name_label.add_theme_color_override("font_color", Color(ACCENTS.get(npc_name, "#8ea6ff")))
	npc_title_label.text = Config.NPC_TITLES.get(npc_name, "")
	_setup_affinity(npc_name)   # 【新增】把好感度条重置成这个人的数据
	dialogue_text.clear()
	dialogue_text.append_text("[color=#7f9aa3]与 " + npc_name + " 的对话开始[/color]\n")
	if npc_name == "梓涵":
		dialogue_text.append_text("[color=#8ea6ff]提示：问「帮我规划西湖一日游」这类宏观问题，可以看到导游去咨询其他专家的全过程。[/color]\n")
	player_input.text = ""
	_awaiting = false
	_status.text = ""
	send_button.disabled = false
	show_dialogue()
	player_input.grab_focus()
	print("[INFO] 开始对话: ", npc_name)


func show_dialogue() -> void:
	visible = true
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_interacting"):
		player.set_interacting(true)


func hide_dialogue() -> void:
	visible = false
	if current_npc_name != "":
		var npc: Node = get_npc_by_name(current_npc_name)
		if npc != null and npc.has_method("set_interacting"):
			npc.set_interacting(false)
	current_npc_name = ""
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_interacting"):
		player.set_interacting(false)


func _on_send_button_pressed() -> void:
	send_message()


func _on_text_submitted(_text: String) -> void:
	send_message()


# 【新增】回车发送：不抢 LineEdit 的提交动作，推到下一帧再发，
# 这样中文输入法按回车确认候选字时，最后一个字不会被吞掉。
func _on_player_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			call_deferred("_try_send_from_input")


func _try_send_from_input() -> void:
	if not visible or _awaiting:
		return
	if player_input.text.strip_edges().is_empty():
		return
	send_message()


func send_message() -> void:
	if _awaiting:
		return
	var message: String = player_input.text.strip_edges()
	if message.is_empty() or current_npc_name.is_empty():
		return
	dialogue_text.append_text("\n[color=#5fd0e6]玩家[/color]  " + message + "\n")
	player_input.text = ""
	_awaiting = true
	_wait_t = 0.0
	_consult_steps = 0
	_consult_done = 0
	send_button.disabled = true

	# 【新增】通知导演：世界里的演出和 HUD 从这一刻开始
	get_tree().call_group("consult_director", "on_chat_started", current_npc_name, message)

	if current_npc_name == "梓涵":
		dialogue_text.append_text("[color=#8ea6ff]梓涵[/color]  [color=#7f9aa3]正在拆解需求，准备联系专家…[/color]\n")
	else:
		dialogue_text.append_text("[color=#7f9aa3]对方正在思考…[/color]\n")
	_scroll_bottom()

	if api_client != null:
		api_client.send_chat(current_npc_name, message)
	else:
		_on_chat_error("API客户端未找到")


# ==================== 【新增】协作时间线 ====================
func consult_step(target: String, question: String) -> void:
	if not visible or current_npc_name != "梓涵":
		return
	_consult_steps += 1
	var hex: String = ACCENTS.get(target, "#8ea6ff")
	dialogue_text.append_text("[color=#8ea6ff]  → 咨询 " + target + "[/color]  [color=#7f9aa3]" + _clip(question, 46) + "[/color]\n")
	_scroll_bottom()


func consult_reply(target: String, reply: String, ok: bool) -> void:
	if not visible or current_npc_name != "梓涵":
		return
	_consult_done += 1
	var hex: String = ACCENTS.get(target, "#6ee7a8")
	var head: String = "  ✓ " + target + " 已回复" if ok else "  ! " + target + " 未接通"
	dialogue_text.append_text("[color=" + hex + "]" + head + "[/color]  " + _clip(reply, 70) + "\n")
	_scroll_bottom()


func consult_end(done: int, elapsed: float) -> void:
	if not visible or current_npc_name != "梓涵":
		return
	if done > 0:
		dialogue_text.append_text("[color=#6ee7a8]  协作完成：共咨询 %d 位专家，用时 %ds，正在整合…[/color]\n" % [done, int(elapsed)])
		_scroll_bottom()


func _clip(text: String, n: int) -> String:
	var t: String = text.replace("\n", " ").strip_edges()
	if t.length() <= n:
		return t
	return t.substr(0, n) + "…"


func _scroll_bottom() -> void:
	dialogue_text.scroll_to_line(dialogue_text.get_line_count() - 1)


func _on_chat_response_received(npc_name: String, message: String) -> void:
	if npc_name != current_npc_name:
		return
	_awaiting = false
	send_button.disabled = false
	var hex: String = ACCENTS.get(npc_name, "#ffc45c")
	dialogue_text.append_text("\n[color=" + hex + "]" + npc_name + "[/color]  " + message + "\n")
	_status.text = "已回复 · 用时 %ds" % int(_wait_t)
	_status.add_theme_color_override("font_color", OK_COL)
	_refresh_affinity()   # 【新增】后端是"先算分再返回"，此刻档案已更新，正好读到新值
	_scroll_bottom()
	player_input.grab_focus()


func _on_chat_error(error_message: String) -> void:
	_awaiting = false
	send_button.disabled = false
	dialogue_text.append_text("[color=#ff6b6b]错误：" + error_message + "[/color]\n")
	_status.text = "本次请求失败"
	_status.add_theme_color_override("font_color", BAD_COL)
	_scroll_bottom()
	player_input.grab_focus()


func _on_close_button_pressed() -> void:
	hide_dialogue()


func get_npc_by_name(npc_name: String) -> Node:
	for npc in get_tree().get_nodes_in_group("npcs"):
		if str(npc.npc_name) == npc_name:
			return npc
	return null