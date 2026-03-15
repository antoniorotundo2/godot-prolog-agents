extends "res://scripts/Agent.gd"

const BULLET_SCENE := preload("res://objects/tanks_objects/bullet.tscn")
const TANK_GROUP := "top_down_tank_agents"

@export_group("Tank Agent")
@export var team := 1
@export_file("*.pl") var prolog_path: String = "res://prolog/tank_hunter.pl"
@export var move_speed := 4.4
@export var strafe_speed := 3.3
@export var retreat_speed := 2.8
@export var shoot_range := 24.0
@export var too_close_range := 4.8
@export var perception_range := 35.0
@export var shoot_cooldown_seconds := 0.55
@export var hit_points := 100.0
@export var use_internal_camera := false
@export var patrol_speed := 2.4
@export var patrol_radius := 10.0
@export var patrol_repath_seconds := 2.0

@export_group("Anti Stallo")
@export var enable_unstuck := true
@export var stuck_check_interval := 0.35
@export var stuck_min_travel := 0.12
@export var stuck_trigger_seconds := 1.1
@export var unstuck_duration_seconds := 0.75

@export_group("Respawn")
@export var respawn_enabled := true
@export var respawn_delay_seconds := 1.4
@export var respawn_min_x := -18.0
@export var respawn_max_x := 18.0
@export var respawn_min_z := -18.0
@export var respawn_max_z := 18.0
@export var min_spawn_distance_from_other_tanks := 3.2

@export_group("Fallback Input")
@export var use_manual_input_when_offline := false

@onready var rotation_node: Node3D = $rotationNode
@onready var camera_3d: Camera3D = null
@onready var bullet_start_marker: Marker3D = $rotationNode/bulletStartMarker

var _current_action := "hold"
var _shoot_cooldown := 0.0
var _percepts_signature := ""
var _hp := 100.0
var _is_dead := false
var _base_collision_layer := 0
var _base_collision_mask := 0
var _spawn_y := 0.5
var _rng := RandomNumberGenerator.new()
var _stuck_timer := 0.0
var _stuck_check_timer := 0.0
var _stuck_ref_position := Vector3.ZERO
var _unstuck_time_left := 0.0
var _unstuck_dir := 1.0
var _patrol_target := Vector3.ZERO
var _patrol_repath_left := 0.0
var _patrol_origin := Vector3.ZERO

func _ready() -> void:
	add_to_group(TANK_GROUP)
	_rng.randomize()
	_hp = hit_points
	_is_dead = false
	_base_collision_layer = collision_layer
	_base_collision_mask = collision_mask
	_spawn_y = global_position.y
	_stuck_ref_position = global_position
	_patrol_origin = global_position
	_pick_new_patrol_target()
	_initialize_agent()
	_load_theory_from_path()
	_apply_team_visual()
	if camera_3d != null:
		camera_3d.current = use_internal_camera and team == 1
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
	if _is_dead or _hp <= 0.0:
		return

	_shoot_cooldown = maxf(0.0, _shoot_cooldown - delta)
	_unstuck_time_left = maxf(0.0, _unstuck_time_left - delta)
	_patrol_repath_left = maxf(0.0, _patrol_repath_left - delta)
	var target := _closest_enemy()
	var target_blocked := false
	if target != null:
		_face_target(target.global_position, delta)
		target_blocked = not _has_line_of_sight_to(target)

	var move_vector := Vector3.ZERO
	if use_manual_input_when_offline and not connected:
		move_vector = _manual_move_vector()
		if Input.is_action_just_pressed("left_mouse_click"):
			_shoot_at_position(_get_3d_mouse_position())
	else:
		move_vector = _ai_move_vector(target, target_blocked)
		if _current_action == "shoot":
			_try_shoot_target(target)
		move_vector = _apply_unstuck_override(move_vector, target)
		_update_stuck_detection(delta, move_vector, target_blocked)

	velocity.x = move_vector.x
	velocity.z = move_vector.z
	velocity.y = 0.0
	move_and_slide()
	_track_percept_changes(false)

func _manual_move_vector() -> Vector3:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (camera_3d.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	return direction * move_speed

func _ai_move_vector(target: Node3D, target_blocked: bool) -> Vector3:
	if target == null:
		return _patrol_move_vector()
	var to_enemy := _direction_to(target.global_position)
	var right := to_enemy.cross(Vector3.UP).normalized()
	var left := Vector3.UP.cross(to_enemy).normalized()
	var team_side := right if team == 1 else left

	match _current_action:
		"advance", "move_to_enemy":
			if target_blocked:
				return (to_enemy * 0.25 + team_side * 0.95).normalized() * move_speed * 0.9
			return to_enemy * move_speed
		"shoot":
			if target_blocked:
				return team_side * strafe_speed * 0.9
			var dist := global_position.distance_to(target.global_position)
			if dist > too_close_range * 1.1:
				return to_enemy * move_speed * 0.6
			return Vector3.ZERO
		"retreat":
			return -to_enemy * retreat_speed
		"strafe_left":
			return left * strafe_speed
		"strafe_right":
			return right * strafe_speed
		"hold", "idle":
			return Vector3.ZERO
		"patrol", "search":
			return _patrol_move_vector()
		_:
			return to_enemy * move_speed * 0.5

func _patrol_move_vector() -> Vector3:
	if _patrol_repath_left <= 0.0:
		_pick_new_patrol_target()
	var to_target := _direction_to(_patrol_target)
	if to_target.length_squared() <= 0.0001 or global_position.distance_to(_patrol_target) < 0.9:
		_pick_new_patrol_target()
		to_target = _direction_to(_patrol_target)
	return to_target * patrol_speed

func _pick_new_patrol_target() -> void:
	var offset := Vector3(
		_rng.randf_range(-patrol_radius, patrol_radius),
		0.0,
		_rng.randf_range(-patrol_radius, patrol_radius)
	)
	_patrol_target = _patrol_origin + offset
	_patrol_target.y = _spawn_y
	_patrol_repath_left = patrol_repath_seconds

func _apply_unstuck_override(move_vector: Vector3, target: Node3D) -> Vector3:
	if not enable_unstuck:
		return move_vector
	if _unstuck_time_left <= 0.0:
		return move_vector

	var forward := -global_basis.z
	if target != null:
		var to_enemy := _direction_to(target.global_position)
		if to_enemy.length_squared() > 0.0001:
			forward = to_enemy
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var lateral := Vector3.UP.cross(forward).normalized() * _unstuck_dir
	return (lateral * 0.9 + forward * 0.3).normalized() * maxf(strafe_speed, move_speed * 0.85)

func _update_stuck_detection(delta: float, requested_move: Vector3, target_blocked: bool) -> void:
	if not enable_unstuck:
		return
	if _unstuck_time_left > 0.0:
		return
	if requested_move.length_squared() < 0.001:
		_stuck_timer = maxf(0.0, _stuck_timer - delta)
		_stuck_check_timer = 0.0
		_stuck_ref_position = global_position
		return

	_stuck_check_timer += delta
	if _stuck_check_timer < stuck_check_interval:
		return

	var moved := global_position.distance_to(_stuck_ref_position)
	if moved < stuck_min_travel:
		_stuck_timer += _stuck_check_timer
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - _stuck_check_timer * 1.2)

	_stuck_check_timer = 0.0
	_stuck_ref_position = global_position

	if target_blocked and _stuck_timer >= stuck_trigger_seconds:
		_unstuck_time_left = unstuck_duration_seconds
		_unstuck_dir = 1.0 if _rng.randf() > 0.5 else -1.0
		if team == 2:
			_unstuck_dir *= -1.0
		_stuck_timer = 0.0

func _face_target(world_target: Vector3, delta: float) -> void:
	var from := rotation_node.global_position
	var to := world_target
	to.y = from.y
	var dir := to - from
	if dir.length() < 0.001:
		return

	var target_basis := Basis.looking_at(dir.normalized(), Vector3.UP, true)
	var current_q := rotation_node.global_basis.get_rotation_quaternion()
	var target_q := target_basis.get_rotation_quaternion()
	var t := clampf(delta * 8.0, 0.0, 1.0)
	rotation_node.global_basis = Basis(current_q.slerp(target_q, t))

func _direction_to(target: Vector3) -> Vector3:
	var d := target - global_position
	d.y = 0.0
	if d.length() < 0.001:
		return Vector3.ZERO
	return d.normalized()

func _closest_enemy() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(TANK_GROUP):
		if node == self:
			continue
		if not (node is Node3D):
			continue
		if node.has_method("is_dead") and bool(node.call("is_dead")):
			continue
		if node.has_method("get_team"):
			var node_team := int(node.call("get_team"))
			if node_team == team:
				continue
		var other := node as Node3D
		var d := global_position.distance_to(other.global_position)
		if d > perception_range:
			continue
		if d < best_dist:
			best_dist = d
			best = other
	return best

func build_percepts() -> Array:
	var p: Array = []
	if _is_dead:
		p.append("dead")
		return p
	if team == 1:
		p.append("team_1")
	else:
		p.append("team_2")
	var enemy := _closest_enemy()
	if enemy == null:
		p.append("no_enemy")
		return p

	p.append("enemy_visible")
	var blocked := not _has_line_of_sight_to(enemy)
	if blocked:
		p.append("enemy_blocked")
	var dist := global_position.distance_to(enemy.global_position)
	if dist <= shoot_range:
		p.append("enemy_in_range")
	if dist <= too_close_range:
		p.append("enemy_too_close")
	if _shoot_cooldown <= 0.0:
		p.append("can_shoot")

	var local_enemy := rotation_node.global_basis.inverse() * (enemy.global_position - rotation_node.global_position)
	local_enemy.y = 0.0
	if local_enemy.x < -0.3:
		p.append("enemy_left")
	elif local_enemy.x > 0.3:
		p.append("enemy_right")
	else:
		p.append("enemy_ahead")

	if _hp <= hit_points * 0.3:
		p.append("low_hp")
	if _stuck_timer > stuck_trigger_seconds * 0.6:
		p.append("stuck")
	if _unstuck_time_left > 0.0:
		p.append("unstuck_mode")

	return p

func perform_action(action: String) -> void:
	if _is_dead:
		return
	_current_action = action
	if action == "shoot":
		_try_shoot_target(_closest_enemy())

func _try_shoot_target(target: Node3D) -> void:
	if _is_dead:
		return
	if target == null:
		return
	if _shoot_cooldown > 0.0:
		return
	if global_position.distance_to(target.global_position) > shoot_range:
		return
	if not _has_line_of_sight_to(target):
		return
	_shoot_at_position(target.global_position)

func _has_line_of_sight_to(target: Node3D) -> bool:
	if target == null:
		return false
	var from := bullet_start_marker.global_position if bullet_start_marker != null else global_position + Vector3(0, 0.7, 0)
	var to := target.global_position + Vector3(0, 0.6, 0)

	var params := PhysicsRayQueryParameters3D.new()
	params.from = from
	params.to = to
	params.exclude = [get_rid()]
	params.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return true

	var collider_value: Variant = hit.get("collider")
	if typeof(collider_value) != TYPE_OBJECT:
		return false
	if collider_value == target:
		return true
	if collider_value is Node:
		return target.is_ancestor_of(collider_value as Node)
	return false

func _shoot_at_position(world_target: Variant) -> void:
	if typeof(world_target) != TYPE_VECTOR3:
		return
	var target_pos: Vector3 = world_target
	var bullet_node: Node = BULLET_SCENE.instantiate()
	var dir := target_pos - bullet_start_marker.global_position
	dir.y = 0.0
	if dir.length() < 0.001:
		return

	bullet_node.set("direction", dir.normalized())
	bullet_node.set("shooter_team", team)
	bullet_node.set("shooter_node", self)
	get_tree().current_scene.add_child(bullet_node)
	if bullet_node is Node3D:
		(bullet_node as Node3D).global_position = bullet_start_marker.global_position
	_shoot_cooldown = shoot_cooldown_seconds

func _get_3d_mouse_position():
	var mouse_2d_position := get_viewport().get_mouse_position()
	var current_camera := get_viewport().get_camera_3d()
	if current_camera == null:
		return null

	var params := PhysicsRayQueryParameters3D.new()
	params.from = current_camera.project_ray_origin(mouse_2d_position)
	params.to = current_camera.project_position(mouse_2d_position, 100.0)

	var worldspace := get_world_3d().direct_space_state
	var intersect := worldspace.intersect_ray(params)
	if intersect.is_empty():
		return null

	var pos_value: Variant = intersect.get("position")
	if typeof(pos_value) != TYPE_VECTOR3:
		return null
	var pos: Vector3 = pos_value
	pos.y = global_position.y
	return pos

func _track_percept_changes(force_send: bool) -> void:
	var signature := JSON.stringify(build_percepts())
	if force_send or signature != _percepts_signature:
		_percepts_signature = signature
		request_urgent_send()

func _apply_team_visual() -> void:
	if not has_node("rotationNode/CartoonTank"):
		return
	var root := $rotationNode/CartoonTank
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.7
	mat.metallic = 0.1
	mat.albedo_color = Color(0.25, 0.5, 1.0) if team == 1 else Color(1.0, 0.45, 0.2)
	_apply_material_recursive(root, mat)

func _apply_material_recursive(node: Node, material: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_material_recursive(child, material)

func receive_bullet_hit(damage: float, shooter_team: int = -1, _shooter_node: Node = null) -> void:
	if _is_dead:
		return
	if shooter_team == team:
		return
	_hp = maxf(0.0, _hp - maxf(damage, 0.0))
	if _hp <= 0.0:
		_die()

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	set_process(false)
	set_physics_process(false)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if rotation_node != null:
		rotation_node.visible = false
	emit_signal("action_received", agent_id, "dead")
	if respawn_enabled:
		_respawn_after_delay()
	else:
		if ws != null:
			ws.close()
		call_deferred("queue_free")

func _respawn_after_delay() -> void:
	await get_tree().create_timer(maxf(respawn_delay_seconds, 0.1)).timeout
	if not is_inside_tree():
		return

	_is_dead = false
	_hp = hit_points
	_current_action = "hold"
	_shoot_cooldown = shoot_cooldown_seconds * 0.6
	velocity = Vector3.ZERO
	_stuck_timer = 0.0
	_stuck_check_timer = 0.0
	_unstuck_time_left = 0.0
	global_position = _pick_respawn_position()
	_patrol_origin = global_position
	_pick_new_patrol_target()
	_stuck_ref_position = global_position
	collision_layer = _base_collision_layer
	collision_mask = _base_collision_mask
	if rotation_node != null:
		rotation_node.visible = true
	rotation_node.rotation = Vector3.ZERO
	set_process(true)
	set_physics_process(true)
	_track_percept_changes(true)

func _pick_respawn_position() -> Vector3:
	var candidate := Vector3(global_position.x, _spawn_y, global_position.z)
	for _i in range(12):
		var test_pos := Vector3(
			_rng.randf_range(respawn_min_x, respawn_max_x),
			_spawn_y,
			_rng.randf_range(respawn_min_z, respawn_max_z)
		)
		if _is_respawn_position_valid(test_pos):
			return test_pos
		candidate = test_pos
	return candidate

func _is_respawn_position_valid(pos: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group(TANK_GROUP):
		if node == self:
			continue
		if not (node is Node3D):
			continue
		if node.has_method("is_dead") and bool(node.call("is_dead")):
			continue
		if pos.distance_to((node as Node3D).global_position) < min_spawn_distance_from_other_tanks:
			return false
	return true

func get_team() -> int:
	return team

func is_dead() -> bool:
	return _is_dead
