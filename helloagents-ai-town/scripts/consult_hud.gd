extends Control
## 【新增】导游协作链路 HUD
## 把「梓涵 → 四位专家」的多智能体通信实时画出来：
## 节点状态、流动光点、进度条、耗时、当前问答，以及目标在屏幕外时的边缘指示箭头。
## 所有文字都用 Label（避免 draw_string 的中文缺字风险），图形用 _draw 自绘。

const PANEL_W := 372.0
const PANEL_H := 252.0
const MARGIN := 18.0

const INK := Color("#0b1418")
const SURFACE := Color("#13242c")
const TEXT := Color("#eaf4f6")
const MUTED := Color("#7f9aa3")
const GUIDE := Color("#8ea6ff")
const OK_COL := Color("#6ee7a8")
const BAD_COL := Color("#ff6b6b")

const STATE_IDLE := 0
const STATE_ASKING := 1
const STATE_DONE := 2
const STATE_FAIL := 3

var _t: float = 0.0
var _alpha: float = 0.0
var _closing: bool = false
var _close_delay: float = 0.0
var _elapsed: float = 0.0
var _asked: int = 0
var _done: int = 0
var _bar: float = 0.0
var _active: String = ""
var _panel := Rect2()

var _experts: Array = []          # [{name,title,color,state}]
var _row_name: Array = []
var _row_status: Array = []

var _title: Label
var _sub: Label
var _live: Label
var _timer: Label
var _guide_label: Label
var _footer: Label
var _pointer_label: Label

var _pointer_on: bool = false
var _pointer_pos := Vector2.ZERO
var _pointer_col: Color = GUIDE
var _guide_pos := Vector2(52, 140)
var _row_x := 232.0
var _row_ys := [86.0, 124.0, 162.0, 200.0]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_labels()
	resized.connect(_relayout)
	_relayout()


func _mk_label(parent: Node, size_px: int, col: Color, pos: Vector2, w: float, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 3)
	l.position = pos
	l.size = Vector2(w, float(size_px) + 8.0)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	parent.add_child(l)
	return l


func _build_labels() -> void:
	_title = _mk_label(self, 15, TEXT, Vector2(16, 12), 220, HORIZONTAL_ALIGNMENT_LEFT)
	_title.text = "导游协作链路"
	_sub = _mk_label(self, 11, MUTED, Vector2(16, 33), 240, HORIZONTAL_ALIGNMENT_LEFT)
	_sub.text = "梓涵 · 多智能体实时通信"
	_live = _mk_label(self, 11, OK_COL, Vector2(PANEL_W - 60.0, 12), 44, HORIZONTAL_ALIGNMENT_LEFT)
	_live.text = "LIVE"
	_timer = _mk_label(self, 13, TEXT, Vector2(PANEL_W - 116.0, 31), 100, HORIZONTAL_ALIGNMENT_RIGHT)
	_timer.text = "00:00"
	_guide_label = _mk_label(self, 12, GUIDE, Vector2(20, 162), 64, HORIZONTAL_ALIGNMENT_CENTER)
	_guide_label.text = "梓涵"
	_footer = _mk_label(self, 11, MUTED, Vector2(16, PANEL_H - 30.0), PANEL_W - 32.0, HORIZONTAL_ALIGNMENT_LEFT)
	_footer.text = "等待导游发起咨询…"
	_pointer_label = _mk_label(self, 12, TEXT, Vector2.ZERO, 140, HORIZONTAL_ALIGNMENT_LEFT)
	_pointer_label.visible = false


func _relayout() -> void:
	_panel = Rect2(Vector2(maxf(MARGIN, size.x - PANEL_W - MARGIN), MARGIN), Vector2(PANEL_W, PANEL_H))
	_title.position = _panel.position + Vector2(16, 12)
	_sub.position = _panel.position + Vector2(16, 33)
	_live.position = _panel.position + Vector2(PANEL_W - 60.0, 12)
	_timer.position = _panel.position + Vector2(PANEL_W - 116.0, 31)
	_guide_label.position = _panel.position + Vector2(20, 162)
	_footer.position = _panel.position + Vector2(16, PANEL_H - 30.0)
	for i in range(_row_name.size()):
		var y: float = _row_ys[i]
		_row_name[i].position = _panel.position + Vector2(_row_x + 18.0, y - 16.0)
		_row_status[i].position = _panel.position + Vector2(_row_x + 18.0, y + 1.0)
	queue_redraw()


# ==================== 对外接口 ====================
func open_session(experts: Array) -> void:
	_experts.clear()
	for e in experts:
		_experts.append({"name": str(e["name"]), "title": str(e["title"]),
						 "color": e["color"], "state": STATE_IDLE})
	for l in _row_name:
		l.queue_free()
	for l in _row_status:
		l.queue_free()
	_row_name.clear()
	_row_status.clear()
	for i in range(_experts.size()):
		var y: float = _row_ys[i] if i < _row_ys.size() else 86.0 + float(i) * 38.0
		var nm: Label = _mk_label(self, 13, TEXT, Vector2.ZERO, 130, HORIZONTAL_ALIGNMENT_LEFT)
		nm.text = str(_experts[i]["name"])
		var st: Label = _mk_label(self, 10, MUTED, Vector2.ZERO, 130, HORIZONTAL_ALIGNMENT_LEFT)
		st.text = str(_experts[i]["title"])
		_row_name.append(nm)
		_row_status.append(st)
	_asked = 0
	_done = 0
	_bar = 0.0
	_elapsed = 0.0
	_active = ""
	_closing = false
	_close_delay = 0.0
	_alpha = 0.0
	_footer.text = "导游正在分析需求…"
	visible = true
	_relayout()
	set_process(true)


func set_status(npc_name: String, state: int) -> void:
	for i in range(_experts.size()):
		if str(_experts[i]["name"]) == npc_name:
			_experts[i]["state"] = state
			var col: Color = MUTED
			var txt: String = str(_experts[i]["title"])
			if state == STATE_ASKING:
				col = _experts[i]["color"]
				txt = "正在思考…"
			elif state == STATE_DONE:
				col = OK_COL
				txt = "已回复"
			elif state == STATE_FAIL:
				col = BAD_COL
				txt = "未接通"
			_row_status[i].text = txt
			_row_status[i].add_theme_color_override("font_color", col)
			return


func set_active(npc_name: String) -> void:
	_active = npc_name


func set_counts(asked: int, done: int) -> void:
	_asked = asked
	_done = done


func set_footer(text: String) -> void:
	_footer.text = text


func set_elapsed(sec: float) -> void:
	_elapsed = sec
	var s: int = int(sec)
	_timer.text = "%02d:%02d" % [s / 60, s % 60]


func close_session(success: bool) -> void:
	_closing = true
	_close_delay = 3.2
	_active = ""
	_pointer_on = false
	_pointer_label.visible = false
	_live.text = "DONE" if success else "END"
	_live.add_theme_color_override("font_color", OK_COL if success else BAD_COL)
	_footer.text = ("整合完成 · 共 %d 次协作 · 用时 %ds" % [_done, int(_elapsed)]) if success else "本次咨询已结束"


func set_pointer(screen_pos: Vector2, on: bool, col: Color, text: String) -> void:
	_pointer_on = on
	_pointer_pos = screen_pos
	_pointer_col = col
	_pointer_label.visible = on
	if on:
		_pointer_label.text = text


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _closing:
		_close_delay -= delta
		if _close_delay <= 0.0:
			_alpha = maxf(0.0, _alpha - delta * 2.2)
			if _alpha <= 0.01:
				visible = false
				set_process(false)
				return
	else:
		_alpha = minf(1.0, _alpha + delta * 3.4)
	var target: float = 0.0
	if _asked > 0:
		target = float(_done) / float(maxi(1, _asked))
	_bar = lerpf(_bar, target, minf(1.0, delta * 5.0))
	modulate.a = _alpha
	queue_redraw()


func _draw() -> void:
	if not visible or _alpha <= 0.01:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK.r, INK.g, INK.b, 0.93)
	sb.border_color = Color(GUIDE.r, GUIDE.g, GUIDE.b, 0.42)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	draw_style_box(sb, _panel)

	# 顶部渐变条：暮蓝 → 湖青 → 荷粉，暗示这是一条跨智能体的链路
	var stops := [GUIDE, Color("#5fd0e6"), Color("#ff86b8")]
	var seg_w: float = (PANEL_W - 24.0) / 2.0
	for i in range(2):
		var a: Color = stops[i]
		var b: Color = stops[i + 1]
		for k in range(12):
			var f0: float = float(k) / 12.0
			var c: Color = a.lerp(b, f0)
			draw_rect(Rect2(_panel.position + Vector2(12.0 + seg_w * float(i) + seg_w * f0, 5.0),
							Vector2(seg_w / 12.0 + 1.0, 2.0)), c, true)

	# LIVE 呼吸点
	var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
	var live_col: Color = OK_COL if not _closing else MUTED
	draw_circle(_panel.position + Vector2(PANEL_W - 68.0, 19.0), 3.5 + pulse * 1.6,
				Color(live_col.r, live_col.g, live_col.b, 0.35 + pulse * 0.5))

	# 进度条
	var track := Rect2(_panel.position + Vector2(16, 54), Vector2(PANEL_W - 32.0, 5.0))
	draw_rect(track, Color(1, 1, 1, 0.07), true)
	if _bar > 0.001:
		draw_rect(Rect2(track.position, Vector2(track.size.x * _bar, 5.0)), GUIDE, true)
		draw_circle(track.position + Vector2(track.size.x * _bar, 2.5), 3.5, Color("#5fd0e6"))

	var gp: Vector2 = _panel.position + _guide_pos
	# 连线
	for i in range(_experts.size()):
		var y: float = _row_ys[i] if i < _row_ys.size() else 86.0 + float(i) * 38.0
		var ep: Vector2 = _panel.position + Vector2(_row_x, y)
		var col: Color = _experts[i]["color"]
		var state: int = int(_experts[i]["state"])
		if state == STATE_IDLE:
			draw_line(gp, ep, Color(1, 1, 1, 0.07), 1.5, true)
		elif state == STATE_ASKING:
			_draw_flow(gp, ep, col)
		else:
			var lc: Color = OK_COL if state == STATE_DONE else BAD_COL
			draw_line(gp, ep, Color(lc.r, lc.g, lc.b, 0.45), 2.0, true)
			_draw_check(ep + Vector2(-26, 0), lc)

	# 导游节点
	draw_circle(gp, 19.0, Color(GUIDE.r, GUIDE.g, GUIDE.b, 0.14))
	draw_circle(gp, 13.0, SURFACE)
	draw_arc(gp, 13.0, 0.0, TAU, 40, GUIDE, 2.0, true)
	var spin: float = fmod(_t * 1.6, TAU)
	if _active != "":
		draw_arc(gp, 17.0, spin, spin + 1.5, 20, Color("#5fd0e6"), 2.0, true)
	draw_circle(gp, 5.0, GUIDE)

	# 专家节点
	for i in range(_experts.size()):
		var y2: float = _row_ys[i] if i < _row_ys.size() else 86.0 + float(i) * 38.0
		var ep2: Vector2 = _panel.position + Vector2(_row_x, y2)
		var col2: Color = _experts[i]["color"]
		var st: int = int(_experts[i]["state"])
		if st == STATE_ASKING:
			var p2: float = 0.5 + 0.5 * sin(_t * 5.0)
			draw_circle(ep2, 13.0 + p2 * 4.0, Color(col2.r, col2.g, col2.b, 0.16))
		draw_circle(ep2, 9.0, SURFACE)
		var ring: Color = Color(col2.r, col2.g, col2.b, 1.0 if st != STATE_IDLE else 0.35)
		draw_arc(ep2, 9.0, 0.0, TAU, 28, ring, 2.0, true)
		if st == STATE_DONE:
			draw_circle(ep2, 4.0, OK_COL)
		elif st == STATE_FAIL:
			draw_circle(ep2, 4.0, BAD_COL)
		elif st == STATE_ASKING:
			draw_circle(ep2, 3.0 + 1.5 * sin(_t * 6.0), col2)

	# 屏幕外指示箭头
	if _pointer_on:
		_draw_pointer()


func _draw_flow(a: Vector2, b: Vector2, col: Color) -> void:
	var d: Vector2 = b - a
	var length: float = d.length()
	if length < 1.0:
		return
	var dir: Vector2 = d / length
	var dash: float = 9.0
	var gap: float = 7.0
	var offset: float = fmod(_t * 46.0, dash + gap)
	var x: float = -offset
	while x < length:
		var s: float = maxf(0.0, x)
		var e: float = minf(length, x + dash)
		if e > s:
			draw_line(a + dir * s, a + dir * e, Color(col.r, col.g, col.b, 0.75), 2.0, true)
		x += dash + gap
	var f: float = fmod(_t * 0.75, 1.0)
	var pp: Vector2 = a.lerp(b, f)
	draw_circle(pp, 5.0, Color(col.r, col.g, col.b, 0.25))
	draw_circle(pp, 3.0, col)


func _draw_check(p: Vector2, col: Color) -> void:
	draw_line(p + Vector2(-4, 0), p + Vector2(-1, 3), col, 2.0, true)
	draw_line(p + Vector2(-1, 3), p + Vector2(5, -4), col, 2.0, true)


func _draw_pointer() -> void:
	var m: float = 46.0
	var p := Vector2(
		clampf(_pointer_pos.x, m, maxf(m, size.x - m)),
		clampf(_pointer_pos.y, m, maxf(m, size.y - 240.0))
	)
	var to_target: Vector2 = (_pointer_pos - p)
	var ang: float = to_target.angle() if to_target.length() > 1.0 else 0.0
	var tip: Vector2 = p + Vector2(cos(ang), sin(ang)) * 16.0
	var l: Vector2 = p + Vector2(cos(ang + 2.5), sin(ang + 2.5)) * 11.0
	var r: Vector2 = p + Vector2(cos(ang - 2.5), sin(ang - 2.5)) * 11.0
	var pulse: float = 0.55 + 0.45 * sin(_t * 5.0)
	draw_circle(p, 20.0, Color(_pointer_col.r, _pointer_col.g, _pointer_col.b, 0.12 * pulse))
	draw_colored_polygon(PackedVector2Array([tip, l, r]),
						 Color(_pointer_col.r, _pointer_col.g, _pointer_col.b, 0.9))
	_pointer_label.position = p + Vector2(-70, 22)
	_pointer_label.size = Vector2(140, 20)
	_pointer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pointer_label.add_theme_color_override("font_color", _pointer_col)