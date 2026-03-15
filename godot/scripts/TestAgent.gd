extends "res://scripts/Agent.gd"

const AGENT_GROUP := "main_demo_agents"

@export_group("Logic")
@export_file("*.pl") var prolog_path: String = ""
@export var spawn_radius := 3.5
@export var arena_limit := 4.6

@export_group("Motion")
@export var max_move_speed := 2.7
@export var speed_acceleration := 7.5
@export var speed_deceleration := 9.5
@export var max_turn_speed_deg := 210.0
@export var turn_acceleration := 8.0
@export var separation_distance := 0.9
@export var separation_strength := 1.6

@export_group("Combat")
@export var attack_stop_time := 0.22
@export var attack_approach_distance := 1.1
@export var attack_cooldown := 0.45
@export var attack_damage := 22.0
@export var attack_knockback := 4.8
@export var attack_recoil := 1.2
@export var attack_stun_time := 0.2
@export var hit_velocity_decay := 14.0

@export_group("Health")
@export var max_hp := 100.0
@export var use_server_energy_as_life := true

@onready var visual: MeshInstance3D = $Visual
@onready var detection_area: Area3D = $DetectionArea
@onready var attack_area: Area3D = $AttackArea

var _rng := RandomNumberGenerator.new()
var _target_speed_factor := 0.0
var _current_speed := 0.0
var _target_turn := 0.0
var _current_turn := 0.0
var _wander_turn := 0.0
var _attack_hold := 0.0
var _attack_cooldown_left := 0.0
var _stun_left := 0.0
var _hit_velocity := Vector3.ZERO
var _hit_pulse := 0.0
var _tracked_enemies: Dictionary = {}
var _attackable_enemies: Dictionary = {}
var _food_target := Vector3.ZERO
var _goal_reached_pulse := 0.0
var _percepts_signature := ""
var _logic_id := "-"
var _hp := 100.0
var _is_dead := false

func _ready() -> void:
	_rng.randomize()
	_connect_sensor_signals()

func init_agent() -> void:
	add_to_group(AGENT_GROUP)
	_reset_spawn_pose()
	_assign_visual_color()
	_pick_new_food_target()
	_load_theory_from_path()
	_hp = max_hp
	_is_dead = false
	_attack_cooldown_left = 0.0
	_stun_left = 0.0
	_hit_velocity = Vector3.ZERO
	_hit_pulse = 0.0
	_refresh_percept_signature(true)

func get_logic_id() -> String:
	return _logic_id

func build_percepts() -> Array:
	var p: Array = []
	if _is_dead:
		return p
	if _has_enemy_in_detection():
		p.append("enemy")
	if not _attackable_enemies.is_empty():
		p.append("enemy_close")
	if _attack_cooldown_left <= 0.0 and not _attackable_enemies.is_empty():
		p.append("can_attack")
	if _stun_left > 0.0 or _hit_pulse > 0.0:
		p.append("under_attack")
	if _hp <= max_hp * 0.3:
		p.append("low_hp")
	if _is_near_arena_edge():
		p.append("obstacle")
	if _goal_reached_pulse > 0.0:
		p.append("goal_reached")
	else:
		p.append("see_food")
	return p

func perform_action(action: String) -> void:
	match action:
		"move_forward":
			_set_motion(1.0, 0.0)
		"turn_left":
			_set_motion(0.5, 1.0)
		"turn_right":
			_set_motion(0.5, -1.0)
		"attack":
			_command_attack()
		"flee":
			_command_flee()
		"rest", "idle":
			_set_motion(0.0, 0.0)
		"celebrate":
			_set_motion(0.0, 1.0)
		"wander":
			_command_wander()
		_:
			_command_wander()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if use_server_energy_as_life and get_energy() <= 0.0:
		_die("energy_depleted")
		return

	_prune_enemy_lists()
	_attack_hold = maxf(0.0, _attack_hold - delta)
	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
	_stun_left = maxf(0.0, _stun_left - delta)
	_hit_pulse = maxf(0.0, _hit_pulse - delta)
	_goal_reached_pulse = maxf(0.0, _goal_reached_pulse - delta)

	if _check_food_target_reached():
		_goal_reached_pulse = 0.35
		_refresh_percept_signature(true)

	if _stun_left > 0.0:
		_target_speed_factor = 0.0
		_target_turn = 0.0
	elif _attack_hold > 0.0:
		_target_speed_factor = 0.0

	if _is_near_arena_edge():
		_target_turn = _compute_turn_towards(-global_position)
		_target_speed_factor = maxf(_target_speed_factor, 0.45)

	_apply_motion(delta)
	_refresh_percept_signature(false)

func _apply_motion(delta: float) -> void:
	var target_speed := _target_speed_factor * max_move_speed
	var speed_step := speed_acceleration
	if absf(target_speed) < absf(_current_speed):
		speed_step = speed_deceleration
	_current_speed = move_toward(_current_speed, target_speed, speed_step * delta)
	_current_turn = move_toward(_current_turn, _target_turn, turn_acceleration * delta)

	rotate_y(deg_to_rad(max_turn_speed_deg) * _current_turn * delta)

	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()

	var desired_velocity := forward * _current_speed + _compute_separation_velocity()
	desired_velocity += _hit_velocity
	velocity.x = desired_velocity.x
	velocity.y = 0.0
	velocity.z = desired_velocity.z
	move_and_slide()
	_process_contact_attacks()
	_hit_velocity = _hit_velocity.move_toward(Vector3.ZERO, hit_velocity_decay * delta)

	global_position.y = 0.25

func _compute_separation_velocity() -> Vector3:
	if _tracked_enemies.is_empty():
		return Vector3.ZERO

	var push := Vector3.ZERO
	for enemy in _tracked_enemies.values():
		if not is_instance_valid(enemy):
			continue
		var enemy_node := enemy as Node3D
		if enemy_node == null:
			continue
		var away := global_position - enemy_node.global_position
		away.y = 0.0
		var dist := away.length()
		if dist <= 0.001 or dist >= separation_distance:
			continue
		var weight := (separation_distance - dist) / separation_distance
		push += away.normalized() * weight

	if push.length_squared() <= 0.0001:
		return Vector3.ZERO

	return push.normalized() * separation_strength

func _command_attack() -> void:
	if _is_dead:
		return
	var enemy := _closest_enemy(_tracked_enemies)
	if enemy == null:
		_command_wander()
		return

	var to_enemy := enemy.global_position - global_position
	to_enemy.y = 0.0
	if to_enemy.length_squared() <= 0.0001:
		_set_motion(0.0, 0.0)
		return

	_target_turn = _compute_turn_towards(to_enemy)
	if to_enemy.length() > attack_approach_distance:
		_target_speed_factor = 0.65
	else:
		_target_speed_factor = 0.2
		_attack_hold = attack_stop_time
	_try_attack_from_area()

func _command_flee() -> void:
	if _is_dead:
		return
	var enemy := _closest_enemy(_tracked_enemies)
	if enemy == null:
		_command_wander()
		return

	var away := global_position - enemy.global_position
	away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = -global_transform.basis.z
	_target_turn = _compute_turn_towards(away)
	_target_speed_factor = 1.0

func _command_wander() -> void:
	if _is_dead:
		return
	_wander_turn = clampf(_wander_turn + _rng.randf_range(-0.4, 0.4), -1.0, 1.0)
	_set_motion(0.75, _wander_turn)

func _set_motion(speed_factor: float, turn_factor: float) -> void:
	if _is_dead:
		return
	_target_speed_factor = clampf(speed_factor, -1.0, 1.0)
	_target_turn = clampf(turn_factor, -1.0, 1.0)

func _try_attack_from_area() -> void:
	if _is_dead:
		return
	if _attack_cooldown_left > 0.0:
		return
	var target := _closest_enemy(_attackable_enemies)
	if target == null:
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > attack_approach_distance * 1.55:
		return
	_apply_attack_hit(target, to_target)

func _process_contact_attacks() -> void:
	if _is_dead:
		return
	if last_action != "attack":
		return
	if _attack_cooldown_left > 0.0:
		return
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider_variant: Variant = collision.get_collider()
		if typeof(collider_variant) != TYPE_OBJECT:
			continue
		var enemy := collider_variant as Node3D
		if enemy == null:
			continue
		if not _is_enemy_candidate(enemy):
			continue
		var to_enemy := enemy.global_position - global_position
		to_enemy.y = 0.0
		_apply_attack_hit(enemy, to_enemy)
		break

func _apply_attack_hit(target: Node3D, hit_direction: Vector3) -> void:
	if _is_dead:
		return
	var dir := hit_direction
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		dir = -global_transform.basis.z
		dir.y = 0.0
	_attack_cooldown_left = attack_cooldown
	_attack_hold = maxf(_attack_hold, attack_stop_time * 0.65)
	if target.has_method("receive_attack_hit"):
		target.call(
			"receive_attack_hit",
			dir.normalized(),
			attack_knockback,
			attack_stun_time,
			attack_damage,
			agent_id
		)
	_hit_velocity -= dir.normalized() * attack_recoil
	_refresh_percept_signature(true)

func receive_attack_hit(
	hit_direction: Vector3,
	force: float,
	stun_seconds: float,
	damage: float = 0.0,
	_attacker_id: String = ""
) -> void:
	if _is_dead:
		return
	var dir := hit_direction
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		return
	_hit_velocity += dir.normalized() * force
	_stun_left = maxf(_stun_left, stun_seconds)
	_hit_pulse = 0.35
	_target_speed_factor = 0.0
	_apply_damage(maxf(damage, 0.0))
	_refresh_percept_signature(true)

func _apply_damage(amount: float) -> void:
	if _is_dead:
		return
	if amount <= 0.0:
		return
	_hp = maxf(0.0, _hp - amount)
	if _hp <= 0.0:
		_die("hp_depleted")

func _die(_reason: String) -> void:
	if _is_dead:
		return
	_is_dead = true
	_target_speed_factor = 0.0
	_target_turn = 0.0
	_current_speed = 0.0
	_current_turn = 0.0
	velocity = Vector3.ZERO
	_tracked_enemies.clear()
	_attackable_enemies.clear()
	_attack_hold = 0.0
	_attack_cooldown_left = 0.0
	_stun_left = 0.0
	_hit_velocity = Vector3.ZERO

	set_process(false)
	set_physics_process(false)

	if detection_area != null:
		detection_area.monitoring = false
		detection_area.monitorable = false
	if attack_area != null:
		attack_area.monitoring = false
		attack_area.monitorable = false

	collision_layer = 0
	collision_mask = 0
	if ws != null:
		ws.close()
	emit_signal("action_received", agent_id, "dead")
	call_deferred("queue_free")

func _compute_turn_towards(world_direction: Vector3) -> float:
	var target := world_direction
	target.y = 0.0
	if target.length_squared() <= 0.0001:
		return 0.0
	target = target.normalized()

	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return 0.0
	forward = forward.normalized()

	var angle := forward.signed_angle_to(target, Vector3.UP)
	return clampf(angle / PI, -1.0, 1.0)

func _closest_enemy(source: Dictionary) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for enemy in source.values():
		if not is_instance_valid(enemy):
			continue
		var enemy_node := enemy as Node3D
		if enemy_node == null:
			continue
		var d := global_position.distance_to(enemy_node.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy_node
	return best

func _has_enemy_in_detection() -> bool:
	return not _tracked_enemies.is_empty()

func _is_near_arena_edge() -> bool:
	return absf(global_position.x) > arena_limit or absf(global_position.z) > arena_limit

func _is_near_food_target() -> bool:
	var delta := _food_target - global_position
	delta.y = 0.0
	return delta.length() < 0.7

func _check_food_target_reached() -> bool:
	if not _is_near_food_target():
		return false
	_pick_new_food_target()
	return true

func _pick_new_food_target() -> void:
	_food_target = Vector3(
		_rng.randf_range(-arena_limit * 0.75, arena_limit * 0.75),
		0.25,
		_rng.randf_range(-arena_limit * 0.75, arena_limit * 0.75)
	)

func _reset_spawn_pose() -> void:
	var spawn := Vector3.ZERO
	var found := false
	for _i in range(10):
		var candidate := Vector3(
			_rng.randf_range(-spawn_radius, spawn_radius),
			0.25,
			_rng.randf_range(-spawn_radius, spawn_radius)
		)
		if _is_spawn_point_clear(candidate):
			spawn = candidate
			found = true
			break
	if not found:
		spawn = Vector3(
			_rng.randf_range(-spawn_radius, spawn_radius),
			0.25,
			_rng.randf_range(-spawn_radius, spawn_radius)
		)
	global_position = spawn
	rotation = Vector3(0.0, _rng.randf_range(-PI, PI), 0.0)
	velocity = Vector3.ZERO

func _is_spawn_point_clear(candidate: Vector3) -> bool:
	if manager == null:
		return true
	var manager_agents: Variant = manager.get("agents")
	if typeof(manager_agents) != TYPE_ARRAY:
		return true
	for other in manager_agents:
		if not is_instance_valid(other):
			continue
		if other == self:
			continue
		var other_node := other as Node3D
		if other_node == null:
			continue
		if other_node.global_position.distance_to(candidate) < 1.3:
			return false
	return true

func _assign_visual_color() -> void:
	if visual == null:
		return
	var mat := StandardMaterial3D.new()
	var lower := prolog_path.to_lower()
	if lower.contains("logic_a"):
		mat.albedo_color = Color(0.93, 0.62, 0.20)
	elif lower.contains("logic_b"):
		mat.albedo_color = Color(0.20, 0.85, 0.92)
	else:
		mat.albedo_color = Color(_rng.randf(), _rng.randf(), _rng.randf())
	mat.roughness = 0.65
	mat.metallic = 0.08
	visual.material_override = mat

func _load_theory_from_path() -> void:
	_logic_id = "-"
	if prolog_path.strip_edges() == "":
		set_theory("")
		return
	if not FileAccess.file_exists(prolog_path):
		push_warning("Missing prolog file: %s" % prolog_path)
		return
	var f := FileAccess.open(prolog_path, FileAccess.READ)
	if f == null:
		push_warning("Unable to open prolog file: %s" % prolog_path)
		return
	var content := f.get_as_text()
	set_theory(content)
	_logic_id = prolog_path.get_file().get_basename()

func _connect_sensor_signals() -> void:
	if detection_area != null:
		if not detection_area.body_entered.is_connected(_on_detection_body_entered):
			detection_area.body_entered.connect(_on_detection_body_entered)
		if not detection_area.body_exited.is_connected(_on_detection_body_exited):
			detection_area.body_exited.connect(_on_detection_body_exited)

	if attack_area != null:
		if not attack_area.body_entered.is_connected(_on_attack_body_entered):
			attack_area.body_entered.connect(_on_attack_body_entered)
		if not attack_area.body_exited.is_connected(_on_attack_body_exited):
			attack_area.body_exited.connect(_on_attack_body_exited)

func _on_detection_body_entered(body: Node3D) -> void:
	if not _is_enemy_candidate(body):
		return
	_tracked_enemies[body.get_instance_id()] = body
	_refresh_percept_signature(true)

func _on_detection_body_exited(body: Node3D) -> void:
	if body == null:
		return
	_tracked_enemies.erase(body.get_instance_id())
	_attackable_enemies.erase(body.get_instance_id())
	_refresh_percept_signature(true)

func _on_attack_body_entered(body: Node3D) -> void:
	if not _is_enemy_candidate(body):
		return
	_attackable_enemies[body.get_instance_id()] = body
	_refresh_percept_signature(true)

func _on_attack_body_exited(body: Node3D) -> void:
	if body == null:
		return
	_attackable_enemies.erase(body.get_instance_id())
	_refresh_percept_signature(true)

func _is_enemy_candidate(body: Node3D) -> bool:
	if body == null:
		return false
	if body == self:
		return false
	return body.is_in_group(AGENT_GROUP)

func _prune_enemy_lists() -> void:
	var dirty := false
	for id in _tracked_enemies.keys():
		if not is_instance_valid(_tracked_enemies[id]):
			_tracked_enemies.erase(id)
			dirty = true
	for id in _attackable_enemies.keys():
		if not is_instance_valid(_attackable_enemies[id]):
			_attackable_enemies.erase(id)
			dirty = true
	if dirty:
		_refresh_percept_signature(true)

func _refresh_percept_signature(force_send: bool) -> void:
	if _is_dead:
		return
	var signature := JSON.stringify(build_percepts())
	if force_send or signature != _percepts_signature:
		_percepts_signature = signature
		request_urgent_send()

func get_hp() -> float:
	return _hp
