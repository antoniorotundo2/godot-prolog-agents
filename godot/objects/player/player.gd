extends "res://scripts/Agent.gd"
class_name Player

const PLAYER_GROUP := "soccer_test_players"

@export_group("Soccer")
@export_enum("left", "right") var side: String = "left"
@export_file("*.pl") var prolog_path: String = ""
@export var max_velocita: float = 4.8
@export var kick_force: float = 4.6
@export var kick_distance: float = 0.95
@export var kick_cooldown_seconds: float = 0.22
@export var goal_line_x: float = 4.75
@export var defend_x: float = 3.7
@export var separation_distance: float = 0.85
@export var separation_weight: float = 1.1
@export var close_contact_speed_factor: float = 0.78

@export_group("Fallback Input")
@export var use_manual_input_when_offline := false

@onready var mesh: MeshInstance3D = $Mesh

var _ball: RigidBody3D = null
var _current_action := "idle"
var _kick_cooldown := 0.0
var _sidestep_dir := 1.0
var _percepts_signature := ""
var _start_transform := Transform3D.IDENTITY

func _ready() -> void:
	_start_transform = global_transform
	add_to_group(PLAYER_GROUP)
	_initialize_agent()
	_load_theory_from_path()
	_apply_side_visual()
	_track_percept_changes(true)

func _initialize_agent() -> void:
	var generated_id := str(get_path()).replace("/", "_")
	setup(generated_id, get_tree().current_scene, ws_url)

func _load_theory_from_path() -> void:
	if prolog_path.strip_edges() == "":
		return
	if not FileAccess.file_exists(prolog_path):
		push_warning("Missing prolog file: %s" % prolog_path)
		return
	var f := FileAccess.open(prolog_path, FileAccess.READ)
	if f == null:
		push_warning("Unable to open prolog file: %s" % prolog_path)
		return
	set_theory(f.get_as_text())

func _physics_process(delta: float) -> void:
	_kick_cooldown = maxf(0.0, _kick_cooldown - delta)
	if _ball == null:
		_ball = _resolve_ball()

	var move_dir := Vector3.ZERO
	if use_manual_input_when_offline and not connected:
		move_dir = _manual_move_dir()
	else:
		move_dir = _prolog_move_dir()

	var speed_factor := 1.0
	var separation := _compute_separation_vector()
	if separation.length_squared() > 0.0001:
		var combined := move_dir + separation * separation_weight
		if combined.length_squared() > 0.0001:
			move_dir = combined.normalized()
		speed_factor = close_contact_speed_factor

	velocity.x = move_dir.x * max_velocita * speed_factor
	velocity.z = move_dir.z * max_velocita * speed_factor
	velocity.y = 0.0
	move_and_slide()

	if velocity.length() > 0.01:
		# Convert velocity to local space so mirrored/rotated root transforms
		# (like Player2) don't flip visual facing.
		var local_vel := global_transform.basis.inverse() * velocity
		local_vel.y = 0.0
		mesh.rotation.y = atan2(-local_vel.z, local_vel.x)

	if _current_action == "kick_to_opp":
		_try_kick_ball()

	_track_percept_changes(false)

func _manual_move_dir() -> Vector3:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	return direction

func _prolog_move_dir() -> Vector3:
	if _ball == null:
		return Vector3.ZERO

	match _current_action:
		"move_to_ball", "kick_to_opp":
			return _direction_to(_ball.global_position)
		"defend_goal":
			return _direction_to(_defend_position())
		"sidestep":
			var to_ball := _direction_to(_ball.global_position)
			if to_ball.length() < 0.001:
				to_ball = -global_basis.z
			var lateral := Vector3.UP.cross(to_ball).normalized()
			# Keep side movement but still bias toward the ball, otherwise agents orbit it.
			return (lateral * _sidestep_dir * 0.7 + to_ball * 0.45).normalized()
		"celebrate":
			rotate_y(deg_to_rad(250.0) * get_physics_process_delta_time())
			return Vector3.ZERO
		"idle":
			return Vector3.ZERO
		_:
			return _direction_to(_ball.global_position)

func _defend_position() -> Vector3:
	if side == "left":
		return Vector3(-defend_x, global_position.y, 0.0)
	return Vector3(defend_x, global_position.y, 0.0)

func _direction_to(target: Vector3) -> Vector3:
	var d := target - global_position
	d.y = 0.0
	if d.length() < 0.05:
		return Vector3.ZERO
	return d.normalized()

func _try_kick_ball() -> void:
	if _ball == null:
		return
	if _kick_cooldown > 0.0:
		return
	var dist := global_position.distance_to(_ball.global_position)
	if dist > kick_distance:
		return

	var target := _opponent_goal_position()
	var dir := (target - _ball.global_position)
	dir.y = 0.0
	if dir.length() < 0.05:
		return

	var spread := Vector3(0.0, 0.0, randf_range(-0.35, 0.35))
	dir += spread
	_ball.apply_central_impulse(dir.normalized() * kick_force)
	_kick_cooldown = kick_cooldown_seconds

func _opponent_goal_position() -> Vector3:
	if side == "left":
		return Vector3(goal_line_x, 0.25, 0.0)
	return Vector3(-goal_line_x, 0.25, 0.0)

func _resolve_ball() -> RigidBody3D:
	var root := get_tree().current_scene
	if root == null:
		return null
	var node := root.get_node_or_null("Palla")
	if node is RigidBody3D:
		return node as RigidBody3D
	return null

func _closest_enemy_distance() -> float:
	var best := INF
	for other in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if other == self:
			continue
		if not (other is Node3D):
			continue
		var d := global_position.distance_to((other as Node3D).global_position)
		if d < best:
			best = d
	return best

func _compute_separation_vector() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if other == self:
			continue
		if not (other is Node3D):
			continue
		var delta := global_position - (other as Node3D).global_position
		delta.y = 0.0
		var dist := delta.length()
		if dist <= 0.001 or dist >= separation_distance:
			continue
		var weight := (separation_distance - dist) / separation_distance
		push += delta.normalized() * weight

	if push.length_squared() <= 0.0001:
		return Vector3.ZERO
	return push.normalized()

func build_percepts() -> Array:
	var p: Array = []
	if _ball == null:
		_ball = _resolve_ball()
	if _ball == null:
		return p

	p.append("ball_visible")
	var ball_pos := _ball.global_position
	var dist := global_position.distance_to(ball_pos)
	if dist < kick_distance + 0.15:
		p.append("ball_near")
		if _ball.linear_velocity.length() < 0.08:
			p.append("ball_stuck")

	if side == "left":
		if ball_pos.x > 0.0:
			p.append("ball_in_opp_half")
		else:
			p.append("ball_in_own_half")
		if ball_pos.x > goal_line_x:
			p.append("ball_in_opp_goal")
	else:
		if ball_pos.x < 0.0:
			p.append("ball_in_opp_half")
		else:
			p.append("ball_in_own_half")
		if ball_pos.x < -goal_line_x:
			p.append("ball_in_opp_goal")

	if _closest_enemy_distance() < 0.9:
		p.append("enemy_near")

	return p

func perform_action(action: String) -> void:
	_current_action = action
	if action == "sidestep":
		_sidestep_dir = 1.0 if randf() > 0.5 else -1.0
	elif action == "kick_to_opp":
		_try_kick_ball()

func _track_percept_changes(force_send: bool) -> void:
	var signature := JSON.stringify(build_percepts())
	if force_send or signature != _percepts_signature:
		_percepts_signature = signature
		request_urgent_send()

func _apply_side_visual() -> void:
	if mesh == null:
		return
	var m := StandardMaterial3D.new()
	if side == "left":
		m.albedo_color = Color(0.25, 0.55, 1.0)
	else:
		m.albedo_color = Color(1.0, 0.45, 0.25)
	m.roughness = 0.8
	m.metallic = 0.05
	mesh.material_override = m

func reset_to_initial_position() -> void:
	global_transform = _start_transform
	velocity = Vector3.ZERO
	_current_action = "idle"
	_kick_cooldown = 0.0
	_sidestep_dir = 1.0
	_track_percept_changes(true)
