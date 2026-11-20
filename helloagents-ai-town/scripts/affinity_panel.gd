# 【新增】关系档案面板
extends Control
## 按 TAB 打开左上角的"关系档案"，列出四位专家对玩家的好感度：
## 名字 + 等级 + 分值 + 一条进度条。数据来自 GET /affinities（梓涵不参与）。
## 面板打开时每 10 秒刷新一次；对话结束收到回复时也会顺手刷一次。
## 所有文字用 Label，图形用 ProgressBar + StyleBoxFlat，跟小镇的墨青配色一致。

const PANEL_W := 320.0
const PANEL_H := 300.0
const MARGIN := 20.0

const INK := Color("#0b1418")
const SURFACE := Color("#13242c")
const LINE := Color("#22404c")
const TEXT := Color("#eaf4f6")
const MUTED := Color("#7f9aa3")
const GUIDE := Color("#8ea6ff")

const EXPERTS := ["子涵", "芷涵", "子晗", "子寒"]
const ROW_H := 52.0
const FIRST_ROW_Y := 56.0
const REFRESH_INTERVAL := 10.0

var _panel: Panel = null
var _title: Label = null
var _hint: Label = null
var _footer: Label = null
var _names: Array[Label] = []
var _scores: Array[Label] = []
var _bars: Array[ProgressBar] = []

var _looking := false
var _api: Node = null
var _refresh_accum: float = 0.0
var _first_paint: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()

	_api = get_node_or_null("/root/APIClient")
	if _api != null:
		_api.affinities_received.connect(_on_affinities_received)
		_api.affinity_received.connect(_on_single_affinity)
		_api.chat_response_received.connect(_on_chat_response)
	print("[INFO] 关系档案面板初始化完成（TAB 开关）")


func _build() -> void:
	_panel = Panel.new()
	_panel.position = Vector2(MARGIN, MARGIN)
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK.r, INK.g, INK.b, 0.94)
	sb.border_color = Color(GUIDE.r, GUIDE.g, GUIDE.b, 0.30)
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 8
	sb.content_margin_top = 6
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	_title = _mk_label(15, TEXT, Vector2(16, 10), 200, HORIZONTAL_ALIGNMENT_LEFT)
	_title.text = "关系档案"

	_hint = _mk_label(11, MUTED, Vector2(16, 31), 220, HORIZONTAL_ALIGNMENT_LEFT)
	_hint.text = "四位专家 · 好感度"

	_footer = _mk_label(11, MUTED, Vector2(16, PANEL_H - 26.0), PANEL_W - 32.0, HORIZONTAL_ALIGNMENT_LEFT)
	_footer.text = "TAB 关闭 · 数据来自后端口碑档案"

	for i in range(EXPERTS.size()):
		var y: float = FIRST_ROW_Y + ROW_H * float(i)
		var name_label := _mk_label(14, TEXT, Vector2(16, y), 190, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.text = EXPERTS[i] + " · —"
		_names.append(name_label)

		var score_label := _mk_label(13, MUTED, Vector2(PANEL_W - 86.0, y + 1.0), 70, HORIZONTAL_ALIGNMENT_RIGHT)
		score_label.text = "--"
		_scores.append(score_label)

		var bar := ProgressBar.new()
		bar.position = Vector2(16, y + 24.0)
		bar.size = Vector2(PANEL_W - 32.0, 6.0)
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style_bar(bar, MUTED)
		_panel.add_child(bar)
		_bars.append(bar)


func _mk_label(size_px: int, col: Color, pos: Vector2, w: float, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.70))
	l.add_theme_constant_override("outline_size", 3)
	l.position = pos
	l.size = Vector2(w, float(size_px) + 8.0)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	_panel.add_child(l)
	return l


func _style_bar(bar: ProgressBar, col: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.07)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(col.r, col.g, col.b, 0.95)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


# ==================== 开关 ====================
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_TAB:
		return
	# 正在输入框里打字时，TAB 留给 LineEdit 切焦点，不抢
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		return
	_looking = not _looking
	visible = _looking
	if _looking:
		_refresh_accum = 0.0
		if _api != null:
			_api.get_all_affinities()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		if _api != null:
			_api.get_all_affinities()


# ==================== 数据 ====================
func _on_affinities_received(affinities: Dictionary) -> void:
	for i in range(EXPERTS.size()):
		var n: String = EXPERTS[i]
		var d = affinities.get(n, null)
		if typeof(d) == TYPE_DICTIONARY:
			_apply_row(i, float(d.get("score", 0.0)), str(d.get("level", "")))
	_footer.text = "TAB 关闭 · 已同步后端档案"
	if _first_paint:
		_first_paint = false
		print("[INFO] 关系档案首次同步完成")


func _on_single_affinity(npc_name: String, score: float, level: String, _modifier: String) -> void:
	var i: int = EXPERTS.find(npc_name)
	if i < 0:
		return
	_apply_row(i, score, level)


func _on_chat_response(_npc_name: String, _message: String) -> void:
	if visible and _api != null:
		_api.get_all_affinities()


func _apply_row(i: int, score: float, level: String) -> void:
	if i < 0 or i >= _names.size():
		return
	var shown: float = clampf(score, 0.0, 100.0)
	var col: Color = Color(Config.AFFINITY_LEVEL_COLORS.get(level, "#7f9aa3"))
	var lv: String = level if not level.is_empty() else "—"
	_names[i].text = EXPERTS[i] + " · " + lv
	_names[i].add_theme_color_override("font_color", TEXT)
	_scores[i].text = "%d" % int(round(score))
	_scores[i].add_theme_color_override("font_color", col)
	_style_bar(_bars[i], col)
	_bars[i].value = shown
