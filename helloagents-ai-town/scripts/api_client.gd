# API客户端 - 与FastAPI后端通信
extends Node

signal chat_response_received(npc_name: String, message: String)
signal chat_error(error_message: String)
signal npc_status_received(dialogues: Dictionary)
signal npc_list_received(npcs: Array)
signal consult_events_received(events: Array, last_seq: int)   # 【新增】导游协作事件
signal affinity_received(npc_name: String, score: float, level: String, modifier: String)  # 【新增】单个NPC好感度
signal affinities_received(affinities: Dictionary)                                        # 【新增】四位专家好感度总表
signal events_seq_received(last_seq: int)                                                 # 【新增】协作事件水位线

var http_chat: HTTPRequest
var http_status: HTTPRequest
var http_npcs: HTTPRequest
var http_events: HTTPRequest                                    # 【新增】
var http_affinity: HTTPRequest                                  # 【新增】单个好感度
var http_affinities: HTTPRequest                                # 【新增】好感度总表
var http_seq: HTTPRequest                                       # 【新增】协作事件水位线

var _chat_busy: bool = false
var _status_busy: bool = false
var _npcs_busy: bool = false
var _events_busy: bool = false
var _affinity_busy: bool = false                                # 【新增】
var _affinities_busy: bool = false                              # 【新增】
var _seq_busy: bool = false                                     # 【新增】
var _chat_start_ms: int = 0
var _status_fail: int = 0
var _status_retry_after: int = 0

const RESULT_TEXT := {
	0: "成功", 2: "无法连接服务器", 3: "域名解析失败", 4: "连接读写错误",
	5: "TLS握手失败", 6: "服务器无响应", 13: "请求超时"
}


func _ready() -> void:
	http_chat = HTTPRequest.new()
	http_status = HTTPRequest.new()
	http_npcs = HTTPRequest.new()
	http_events = HTTPRequest.new()
	http_affinity = HTTPRequest.new()
	http_affinities = HTTPRequest.new()
	http_seq = HTTPRequest.new()
	add_child(http_chat)
	add_child(http_status)
	add_child(http_npcs)
	add_child(http_events)
	add_child(http_affinity)
	add_child(http_affinities)
	add_child(http_seq)

	# 默认 timeout=0 表示永不超时，必须显式设置
	http_chat.timeout = 180.0
	http_status.timeout = 8.0
	http_npcs.timeout = 8.0
	http_events.timeout = 5.0        # 协作事件要快进快出，卡住就下一轮再来
	http_affinity.timeout = 5.0      # 好感度是装饰，短超时，失败就当没这回事
	http_affinities.timeout = 5.0
	http_seq.timeout = 5.0

	http_chat.request_completed.connect(_on_chat_request_completed)
	http_status.request_completed.connect(_on_status_request_completed)
	http_npcs.request_completed.connect(_on_npcs_request_completed)
	http_events.request_completed.connect(_on_events_completed)
	http_affinity.request_completed.connect(_on_affinity_request_completed)
	http_affinities.request_completed.connect(_on_affinities_request_completed)
	http_seq.request_completed.connect(_on_seq_completed)
	print("[INFO] API客户端初始化完成 -> ", Config.API_BASE_URL)


func _rname(r: int) -> String:
	return RESULT_TEXT.get(r, "错误码%d" % r)


func is_chat_busy() -> bool:
	return _chat_busy


# ==================== 对话 ====================
func send_chat(npc_name: String, message: String) -> void:
	if _chat_busy:
		chat_error.emit("上一条消息还在回复中，请稍候")
		return
	var payload := {"npc_name": npc_name, "message": message}
	print("[API] POST /chat -> ", payload)
	_chat_busy = true
	_chat_start_ms = Time.get_ticks_msec()
	var err: int = http_chat.request(
		Config.API_CHAT, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(payload)
	)
	if err != OK:
		_chat_busy = false
		chat_error.emit("请求发送失败(错误码 %d)" % err)


func _on_chat_request_completed(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_chat_busy = false
	var cost: float = (Time.get_ticks_msec() - _chat_start_ms) / 1000.0
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var msg := "对话失败：%s (http %d，%.1fs)" % [_rname(result), response_code, cost]
		print("[ERROR] ", msg)
		chat_error.emit(msg)
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		chat_error.emit("响应解析失败")
		return
	var response: Dictionary = json.data
	if typeof(response) == TYPE_DICTIONARY and response.get("success", false):
		print("[INFO] 收到NPC回复(%.1fs): " % cost, response["npc_name"])
		chat_response_received.emit(str(response["npc_name"]), str(response["message"]))
	else:
		chat_error.emit("对话失败")


# ==================== 【新增】导游协作事件流 ====================
func poll_interactions(since: int) -> void:
	if _events_busy:
		return
	_events_busy = true
	var url: String = Config.API_BASE_URL + "/npcs/interactions?since=" + str(since)
	var err: int = http_events.request(url)
	if err != OK:
		_events_busy = false


func _on_events_completed(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_events_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var data: Dictionary = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return
	var events: Array = data.get("events", [])
	var last_seq: int = int(data.get("last_seq", 0))
	consult_events_received.emit(events, last_seq)


# 【新增】只取"服务器现在到哪了"，不取事件内容。
# 开对话时先用它定一个水位线，否则 since=0 的历史事件会被当成新事件回放，
# 梓涵就会照着上一局的旧记录乱跑、问完也停在半路。
func request_last_seq() -> void:
	if _seq_busy:
		return
	_seq_busy = true
	var url: String = Config.API_BASE_URL + "/npcs/interactions?since=999999999"
	var err: int = http_seq.request(url)
	if err != OK:
		_seq_busy = false


func _on_seq_completed(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_seq_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return
	events_seq_received.emit(int(data.get("last_seq", 0)))


# ==================== NPC状态 ====================
func get_npc_status() -> void:
	if _status_busy or Time.get_ticks_msec() < _status_retry_after:
		return
	_status_busy = true
	var err: int = http_status.request(Config.API_NPC_STATUS)
	if err != OK:
		_status_busy = false


func _on_status_request_completed(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_status_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_status_fail += 1
		if _status_fail == 3:
			_status_retry_after = Time.get_ticks_msec() + 15000
			print("[WARN] 后端连续无响应，15秒后重试")
		return
	_status_fail = 0
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var response: Dictionary = json.data
	if typeof(response) == TYPE_DICTIONARY and response.has("dialogues"):
		npc_status_received.emit(response["dialogues"])


# ==================== NPC列表 ====================
func get_npc_list() -> void:
	if _npcs_busy:
		return
	_npcs_busy = true
	var err: int = http_npcs.request(Config.API_NPCS)
	if err != OK:
		_npcs_busy = false


func _on_npcs_request_completed(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_npcs_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var response: Dictionary = json.data
	if typeof(response) == TYPE_DICTIONARY and response.has("npcs"):
		npc_list_received.emit(response["npcs"])


# ==================== 【新增】好感度 ====================
# 后端 GET /npcs/{name}/affinity 只回 score/level/modifier，不回名字，
# 所以这里记住"这次请求问的是谁"，回调时一起发出去。
var _affinity_for: String = ""
# 只有一个 http_affinity 节点，忙时把后来的请求排进队列，避免快速切换NPC时条卡在 "--"
var _affinity_queue: Array = []


func get_affinity(npc_name: String) -> void:
	if _affinity_busy:
		if not _affinity_queue.has(npc_name):
			_affinity_queue.append(npc_name)
		return
	_affinity_busy = true
	_affinity_for = npc_name
	var url: String = Config.API_AFFINITY_PREFIX + npc_name.uri_encode() + "/affinity"
	var err: int = http_affinity.request(url)
	if err != OK:
		_affinity_busy = false


func _on_affinity_request_completed(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_affinity_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.data
			if typeof(data) == TYPE_DICTIONARY:
				affinity_received.emit(
					_affinity_for,
					float(data.get("score", 0.0)),
					str(data.get("level", "")),
					str(data.get("modifier", ""))
				)
	if not _affinity_queue.is_empty():
		var next_name: String = str(_affinity_queue.pop_front())
		get_affinity(next_name)


func get_all_affinities() -> void:
	if _affinities_busy:
		return
	_affinities_busy = true
	var err: int = http_affinities.request(Config.API_AFFINITIES)
	if err != OK:
		_affinities_busy = false


func _on_affinities_request_completed(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_affinities_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return
	affinities_received.emit(data)