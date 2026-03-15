extends CharacterBody3D

signal action_received(agent_id: String, action: String)

@export_file("*.pl") var prolog_path: String = ""
@export_enum("left", "right") var side: String = "left"

var ws: WebSocketPeer
var connected := false
var agent_id := ""
var manager = null
var ws_url := ""
var elapsed := 0.0
var send_interval := 0.15
var energy := 100.0
var last_action := "idle"
var theory_text := ""
var theory_sent := false
var theory_dirty := false

var move_speed := 3.0
var kick_force := 4.5
var patrol_dir := 1.0
var patrol_limit := 4.0
var goal_line := 9.0
var current_action := "idle"
var sidestep_time := 0.0
var sidestep_dir := 1.0

func setup(id: String, manager_ref, url: String) -> void:
	agent_id = id
	name = id
	manager = manager_ref
	ws_url = url
	theory_sent = false
	theory_dirty = false
	_build_ws()
	_connect_ws()

func init_agent() -> void:
	reset_position()
	apply_random_color()
	load_theory_from_path()

func set_theory(text: String) -> void:
	theory_text = text
	theory_dirty = true
	theory_sent = false

func _build_ws() -> void:
	ws = WebSocketPeer.new()

func _connect_ws() -> void:
	if ws_url == "":
		return
	var err = ws.connect_to_url(ws_url)
	if err != OK:
		push_warning("WebSocket connect error for %s: %s url: %s" % [agent_id, err, ws_url])

func reconnect(url: String) -> void:
	ws_url = url
	connected = false
	theory_sent = false
	if ws:
		ws.close()
	_build_ws()
	_connect_ws()

func _process(delta: float) -> void:
	if ws == null:
		return
	ws.poll()
	connected = ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	if not connected:
		return

	elapsed += delta
	if elapsed >= send_interval:
		elapsed = 0.0
		send_percepts()

	while ws.get_available_packet_count() > 0:
		var packet = ws.get_packet()
		if not ws.was_string_packet():
			continue
		var text = packet.get_string_from_utf8()
		_handle_message(text)

func _handle_message(text: String) -> void:
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_warning("JSON parse error: %s" % json.get_error_message())
		return
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.has("energy"):
		energy = float(data["energy"])
	if data.has("action"):
		apply_action(str(data["action"]))

func send_percepts() -> void:
	var percepts = build_percepts()
	var payload = {
		"agent": agent_id,
		"percepts": percepts
	}
	if theory_text != "" and (theory_dirty or not theory_sent):
		payload["theory"] = theory_text
		theory_sent = true
		theory_dirty = false

	var text = JSON.stringify(payload)
	if ws.has_method("send_text"):
		ws.send_text(text)
	else:
		ws.put_packet(text.to_utf8_buffer())

func load_theory_from_path() -> void:
	if prolog_path == "":
		return
	if not FileAccess.file_exists(prolog_path):
		push_warning("Missing prolog file: %s" % prolog_path)
		return
	var f = FileAccess.open(prolog_path, FileAccess.READ)
	if f == null:
		push_warning("Unable to open prolog file: %s" % prolog_path)
		return
	set_theory(f.get_as_text())

func reset_position() -> void:
	if side == "left":
		position = Vector3(-5.0, 0.5, randf_range(-3.0, 3.0))
	else:
		position = Vector3(5.0, 0.5, randf_range(-3.0, 3.0))
	velocity = Vector3.ZERO

func build_percepts() -> Array:
	var p: Array = []
	if manager == null:
		return p
	var ball = manager.get_ball()
	if ball == null:
		return p

	var ball_pos = ball.position
	var dist = position.distance_to(ball_pos)
	p.append("ball_visible")
	if dist < 1.2:
		p.append("ball_near")
		if ball.linear_velocity.length() < 0.05:
			p.append("ball_stuck")

	if side == "left":
		if ball_pos.x < 0:
			p.append("ball_in_own_half")
		else:
			p.append("ball_in_opp_half")
		if ball_pos.x > goal_line:
			p.append("ball_in_opp_goal")
	else:
		if ball_pos.x > 0:
			p.append("ball_in_own_half")
		else:
			p.append("ball_in_opp_half")
		if ball_pos.x < -goal_line:
			p.append("ball_in_opp_goal")

	if manager.is_enemy_near(self):
		p.append("enemy_near")

	return p

func apply_action(action: String) -> void:
	last_action = action
	perform_action(action)
	emit_signal("action_received", agent_id, action)

func perform_action(action: String) -> void:
	if manager == null:
		return
	var ball = manager.get_ball()
	var ball_pos = ball.position if ball != null else position

	current_action = action

	if action == "kick_to_opp":
		if ball != null and position.distance_to(ball_pos) < 1.4:
			kick_ball(ball)
	elif action == "sidestep":
		sidestep_time = 0.25
		sidestep_dir = 1.0 if randf() > 0.5 else -1.0
	elif action == "celebrate":
		rotate_y(deg_to_rad(90.0))

func _physics_process(delta: float) -> void:
	if manager == null:
		return

	var planar_velocity := Vector3.ZERO

	if sidestep_time > 0.0:
		planar_velocity.z = sidestep_dir * move_speed * 0.6
		sidestep_time -= delta
	else:
		if current_action == "move_to_ball" or current_action == "kick_to_opp":
			var ball = manager.get_ball()
			if ball != null:
				planar_velocity = direction_to(ball.position) * move_speed
		elif current_action == "defend_goal":
			planar_velocity = direction_to(manager.get_own_goal_pos(side)) * move_speed
		elif current_action == "patrol":
			planar_velocity = patrol_velocity()
		elif current_action == "idle":
			planar_velocity = Vector3.ZERO

	velocity.x = planar_velocity.x
	velocity.z = planar_velocity.z
	velocity.y = 0.0
	move_and_slide()
	clamp_position()

func direction_to(target: Vector3) -> Vector3:
	var dir = target - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return Vector3.ZERO
	return dir.normalized()

func kick_ball(ball: RigidBody3D) -> void:
	var target = manager.get_opp_goal_pos(side)
	var dir = (target - ball.position)
	dir.y = 0
	if dir.length() < 0.1:
		return
	var lateral = Vector3(0, 0, randf_range(-0.8, 0.8))
	dir += lateral
	ball.apply_central_impulse(dir.normalized() * kick_force)

func patrol_velocity() -> Vector3:
	if position.z > patrol_limit:
		patrol_dir = -1.0
	elif position.z < -patrol_limit:
		patrol_dir = 1.0
	return Vector3(0, 0, patrol_dir * move_speed * 0.35)

func clamp_position() -> void:
	position.x = clampf(position.x, -8.5, 8.5)
	position.z = clampf(position.z, -5.0, 5.0)

func get_energy() -> float:
	return energy

func apply_random_color() -> void:
	if not has_node("Visual"):
		return
	var visual := $Visual as MeshInstance3D
	if visual == null:
		return
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(randf(), randf(), randf())
	material.metallic = 0.1
	material.roughness = 0.7
	visual.material_override = material
