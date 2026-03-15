extends CharacterBody3D

signal action_received(agent_id: String, action: String)

@export_group("Agent WS")
@export var use_prolog_agent := true
@export var ws_url := "ws://127.0.0.1:8080/ws"
@export var send_interval := 0.12
@export var send_urgent_on_sensor_events := true
@export var debug_agent_io := false

var ws: WebSocketPeer = null
var connected := false
var agent_id := ""
var manager: Node = null
var elapsed := 0.0
var energy := 100.0
var last_action := "idle"

var theory_text := ""
var theory_sent := false
var theory_dirty := false
var urgent_send_requested := false

func setup(id: String, manager_ref, url: String) -> void:
	agent_id = id
	name = id
	manager = manager_ref
	if url.strip_edges() != "":
		ws_url = url
	theory_sent = false
	theory_dirty = false
	_build_ws()
	_connect_ws()

func set_theory(text: String) -> void:
	theory_text = text
	theory_dirty = true
	theory_sent = false

func _build_ws() -> void:
	ws = WebSocketPeer.new()

func _connect_ws() -> void:
	if not use_prolog_agent:
		return
	if ws_url.strip_edges() == "":
		return
	var err := ws.connect_to_url(ws_url)
	if err != OK:
		push_warning("WebSocket connect error for %s: %s url: %s" % [agent_id, err, ws_url])

func reconnect(url: String) -> void:
	ws_url = url
	connected = false
	theory_sent = false
	urgent_send_requested = false
	if ws:
		ws.close()
	_build_ws()
	_connect_ws()

func _process(delta: float) -> void:
	if not use_prolog_agent:
		return
	if ws == null:
		return

	_tick_agent_connection(delta)

func _tick_agent_connection(delta: float) -> void:
	ws.poll()
	connected = ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	if not connected:
		return

	elapsed += delta
	var tick_interval := maxf(send_interval, 0.02)
	if urgent_send_requested or elapsed >= tick_interval:
		elapsed = 0.0
		urgent_send_requested = false
		_send_percepts()

	while ws.get_available_packet_count() > 0:
		var packet := ws.get_packet()
		if not ws.was_string_packet():
			continue
		_handle_message(packet.get_string_from_utf8())

func _handle_message(text: String) -> void:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning("JSON parse error: %s" % json.get_error_message())
		return

	var data_variant: Variant = json.data
	if typeof(data_variant) != TYPE_DICTIONARY:
		return
	var data: Dictionary = data_variant

	if data.has("energy"):
		energy = float(data["energy"])
	if data.has("action"):
		apply_action(str(data["action"]))
		if debug_agent_io:
			print("[%s] action=%s energy=%s" % [agent_id, last_action, str(energy)])

func _send_percepts() -> void:
	var payload := {
		"agent": agent_id,
		"percepts": build_percepts()
	}
	if theory_text != "" and (theory_dirty or not theory_sent):
		payload["theory"] = theory_text
		theory_sent = true
		theory_dirty = false

	var text := JSON.stringify(payload)
	if ws.has_method("send_text"):
		ws.send_text(text)
	else:
		ws.put_packet(text.to_utf8_buffer())
	if debug_agent_io:
		print("[%s] percepts=%s" % [agent_id, str(payload["percepts"])])

func request_urgent_send() -> void:
	if not send_urgent_on_sensor_events:
		return
	urgent_send_requested = true

# Override in subclasses
func build_percepts() -> Array:
	return []

# Override in subclasses
func perform_action(action: String) -> void:
	pass

func apply_action(action: String) -> void:
	var normalized := action.strip_edges().to_lower()
	last_action = normalized
	perform_action(normalized)
	emit_signal("action_received", agent_id, normalized)

func get_energy() -> float:
	return energy
