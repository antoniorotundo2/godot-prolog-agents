extends PathFollow3D

@export_group("Motion")
@export var max_speed := 22.0
@export var acceleration := 10.0
@export var brake_deceleration := 18.0
@export var natural_deceleration := 4.5
@export var allow_reverse := false
@export var reverse_speed_factor := 0.4

@export_group("Scene References")
@export var vehicle_body_path: NodePath = NodePath("Car")
@export var distance_sensor_path: NodePath = NodePath("DistanceSensor")
@export var area_distance_sensor_path: NodePath = NodePath("AreaDistanceSensor")
@export var right_precedence_sensor_path: NodePath = NodePath("AreaRightPrecedenceSensor")
@export var cross_area_path: NodePath

@export_group("Path Routing")
@export var general_prefix := "generalpath"
@export var cross_prefix := "crosspath"
@export var connect_distance := 10.0
@export var cross_exit_distance := 1.8
@export var end_reconnect_distance := 4.0
@export var min_connection_alignment := 0.25
@export var min_switch_interval := 0.25
@export var min_travel_before_end_check := 0.6
@export var wait_turn_command_timeout := 0.8
@export var fallback_random_turn := false

@export_group("Distance Slowdown")
@export var use_distance_slowdown := true
@export var use_area_distance_sensor := true
@export var slowdown_start_distance := 0.0
@export var full_stop_distance := 1.0
@export var min_speed_factor_when_close := 0.0
@export var obstacle_brake_deceleration := 28.0
@export var prolog_vehicle_very_close_distance := 1.8
@export var prolog_vehicle_close_distance := 4.5
@export var use_vehicle_only_sensor_mask := true
@export_range(1, 32, 1) var vehicle_sensor_layer_bit := 2

@export_group("Vehicle Separation")
@export var enforce_lane_separation := true
@export var min_vehicle_gap := 2.4
@export var separation_slow_distance := 6.5
@export var separation_brake_deceleration := 52.0

@export_group("Right Priority")
@export var use_right_precedence_sensor := true
@export var right_precedence_only_in_intersection := true
@export var right_precedence_managed_by_prolog := true
@export var right_precedence_brake_deceleration := 52.0

@export_group("Intersection Guard")
@export var use_intersection_guard := true
@export var intersection_guard_id := ""
@export var intersection_deadlock_threshold_seconds := 1.2
@export var intersection_random_wait_min_seconds := 1.0
@export var intersection_random_wait_max_seconds := 2.4
@export var intersection_unblock_duration_seconds := 1.2
@export var intersection_unblock_speed_factor := 0.8
@export var intersection_stop_speed_threshold := 0.35
@export var intersection_min_blocked_vehicles := 2
@export var intersection_guard_force_stop := true
@export var intersection_guard_brake_deceleration := 62.0

@export_group("Traffic Light")
@export var enforce_signal_compliance := true
@export var signal_managed_by_prolog := true
@export var semaphore_area_name := "SemaphoreAreaVisibility"
@export var signal_brake_deceleration := 44.0
@export var signal_stop_memory_seconds := 0.6
@export var use_signal_prediction := true
@export var signal_prediction_distance := 7.0
@export var signal_prediction_radius := 18.0

@export_group("Prolog Agent")
@export var use_prolog_agent := true
@export var use_manual_input_when_offline := true
@export var ws_url := "ws://127.0.0.1:8080/ws"
@export var agent_id := ""
@export var send_interval := 0.08
@export var send_urgent_on_sensor_events := true
@export var debug_agent_io := false
@export_file("*.pl") var prolog_path: String = ""

var _speed := 0.0
var _direction := 1
var _rng := RandomNumberGenerator.new()

var _vehicle_body: PhysicsBody3D = null
var _distance_sensor: RayCast3D = null
var _area_distance_sensor: Area3D = null
var _right_precedence_sensor: Area3D = null
var _cross_area: Area3D = null
var _inside_cross_area := false
var _intersection_locked := false
var _intersection_wait := 0.0
var _switch_cooldown := 0.0
var _distance_since_switch := 0.0
var _pending_turn_command := ""

var _general_paths: Array[Path3D] = []
var _cross_paths: Array[Path3D] = []
var _active_path: Path3D = null

var _semaphore_by_area: Dictionary = {}
var _active_semaphore_areas: Dictionary = {}
var _vehicles_in_area_sensor: Dictionary = {}
var _vehicles_on_right_precedence_sensor: Dictionary = {}

var ws: WebSocketPeer = null
var connected := false
var _agent_elapsed := 0.0
var _energy := 100.0
var _last_action := "idle"
var _theory_text := ""
var _theory_sent := false
var _theory_dirty := false
var _prolog_speed_factor := 0.0
var _urgent_send_requested := false
var _signal_stop_memory := 0.0
var _intersection_wait_seconds := 0.0
var _intersection_guard_deadlock_risk := false
var _intersection_guard_queue_size := 0
var _intersection_unblock_active_seconds := 0.0
var _intersection_unblock_target_wait_seconds := 0.0
const VEHICLE_GROUP := "lane_vehicles"

func _ready() -> void:
	_rng.randomize()
	_intersection_unblock_target_wait_seconds = _sample_intersection_wait_threshold()
	add_to_group(VEHICLE_GROUP)
	_active_path = get_parent() as Path3D
	_vehicle_body = get_node_or_null(vehicle_body_path) as PhysicsBody3D

	_bind_distance_sensor()
	_bind_area_distance_sensor()
	_bind_right_precedence_sensor()
	_configure_vehicle_sensor_layer()
	_collect_paths()
	_bind_cross_area()
	_bind_semaphore_areas()

	if agent_id.strip_edges() == "":
		agent_id = str(get_path()).replace("/", "_")

	if use_prolog_agent:
		_load_theory_from_path()
		_build_ws()
		_connect_ws()

func _exit_tree() -> void:
	remove_from_group(VEHICLE_GROUP)

func _process(delta: float) -> void:
	_tick_agent_connection(delta)

func _physics_process(delta: float) -> void:
	_switch_cooldown = maxf(0.0, _switch_cooldown - delta)
	var had_signal_stop_memory := _signal_stop_memory > 0.0
	_signal_stop_memory = maxf(0.0, _signal_stop_memory - delta)
	if _must_stop_for_light():
		_signal_stop_memory = maxf(_signal_stop_memory, signal_stop_memory_seconds)
		if not had_signal_stop_memory:
			_request_urgent_send()

	if _inside_cross_area and _is_general_path(_active_path) and not _intersection_locked:
		_intersection_wait += delta
	else:
		_intersection_wait = 0.0

	_update_intersection_guard(delta)
	_update_speed(delta)
	_advance_on_active_path(delta)
	_handle_path_transitions()

func _update_speed(delta: float) -> void:
	var target_speed := 0.0
	var speed_step := natural_deceleration
	var intersection_unblock_active := use_intersection_guard and _inside_cross_area and _intersection_unblock_active_seconds > 0.0

	if _use_prolog_drive_control():
		var prolog_factor := clampf(_prolog_speed_factor, -1.0, 1.0)
		if prolog_factor > 0.001:
			target_speed = max_speed * prolog_factor
			speed_step = acceleration
			if target_speed < _speed:
				speed_step = maxf(speed_step, brake_deceleration)
		elif prolog_factor < -0.001:
			if allow_reverse:
				target_speed = -max_speed * reverse_speed_factor * absf(prolog_factor)
			else:
				target_speed = 0.0
			speed_step = brake_deceleration
		else:
			target_speed = 0.0
			speed_step = brake_deceleration
	else:
		var up := Input.is_action_pressed("ui_up")
		var down := Input.is_action_pressed("ui_down")

		if up:
			target_speed = max_speed
			speed_step = acceleration
		elif down:
			if allow_reverse:
				target_speed = -max_speed * reverse_speed_factor
			else:
				target_speed = 0.0
			speed_step = brake_deceleration

	if use_distance_slowdown and target_speed > 0.0:
		var obstacle_cap := _compute_obstacle_speed_cap()
		if target_speed > obstacle_cap:
			target_speed = obstacle_cap
			speed_step = maxf(speed_step, obstacle_brake_deceleration)

	if enforce_lane_separation and target_speed > 0.0:
		var lane_cap := _compute_lane_separation_speed_cap()
		if target_speed > lane_cap:
			target_speed = lane_cap
			speed_step = maxf(speed_step, separation_brake_deceleration)

	if intersection_unblock_active:
		var unblock_factor := clampf(intersection_unblock_speed_factor, 0.15, 1.0)
		var unblock_speed := max_speed * unblock_factor
		if target_speed < unblock_speed:
			target_speed = unblock_speed
		speed_step = maxf(speed_step, acceleration)

	if use_right_precedence_sensor and not right_precedence_managed_by_prolog and not intersection_unblock_active and target_speed > 0.0 and _must_yield_to_right():
		target_speed = 0.0
		speed_step = maxf(speed_step, right_precedence_brake_deceleration)

	if enforce_signal_compliance and not signal_managed_by_prolog and not intersection_unblock_active and target_speed > 0.0 and _must_stop_for_light():
		target_speed = 0.0
		speed_step = maxf(speed_step, signal_brake_deceleration)

	_speed = move_toward(_speed, target_speed, speed_step * delta)

func _advance_on_active_path(delta: float) -> void:
	if _active_path == null or _active_path.curve == null:
		return
	var length := _active_path.curve.get_baked_length()
	if length <= 0.001:
		return
	var old_progress := progress
	var next_progress := clampf(progress + (_speed * float(_direction) * delta), 0.0, length)
	if enforce_lane_separation:
		next_progress = _apply_safe_progress_limit(next_progress)
	progress = next_progress
	_distance_since_switch += absf(progress - old_progress)

func _handle_path_transitions() -> void:
	if _active_path == null:
		return

	if _switch_cooldown > 0.0:
		return

	if _should_hold_for_red_light():
		return

	if _inside_cross_area and _is_general_path(_active_path) and not _intersection_locked:
		var turn_command := _resolve_turn_command_for_intersection()
		if turn_command != "" and _switch_to_cross_path_by_command(turn_command):
			_intersection_locked = true
			_pending_turn_command = ""
			return

	if _is_cross_path(_active_path):
		if _can_evaluate_path_end() and _is_near_target_end(_active_path, cross_exit_distance):
			_switch_to_nearest_general_from_current_end()
			return

	if _is_general_path(_active_path):
		if _can_evaluate_path_end() and _is_near_target_end(_active_path, end_reconnect_distance):
			if _inside_cross_area or _has_cross_candidate_near_endpoint():
				return
			_switch_to_nearest_general_from_current_end()

func _resolve_turn_command_for_intersection() -> String:
	var command := _normalize_turn_command(_pending_turn_command)
	if command != "":
		return command

	if use_prolog_agent and connected and _intersection_wait < wait_turn_command_timeout:
		return ""

	if fallback_random_turn:
		return "random"

	return ""

func _switch_to_cross_path_by_command(command: String) -> bool:
	var source_point := _target_endpoint_world(_active_path)
	var candidates := _gather_cross_candidates(source_point)
	if candidates.is_empty():
		return false

	var picked := _pick_cross_candidate(candidates, command)
	if picked.is_empty():
		return false

	_set_active_path(
		picked["path"] as Path3D,
		float(picked["start_offset"]),
		int(picked["direction"])
	)
	_switch_cooldown = min_switch_interval
	return true

func _gather_cross_candidates(source_point: Vector3) -> Array:
	var candidates: Array = []
	var from_forward := _forward_at_target_endpoint(_active_path, _direction)

	for path in _cross_paths:
		if path == null or path.curve == null:
			continue
		var endpoint_info := _best_endpoint_for_position(path, source_point)
		var distance := float(endpoint_info["distance"])
		if distance > connect_distance:
			continue

		var direction := int(endpoint_info["direction"])
		var to_forward := _forward_from_endpoint(path, direction)
		var turn_label := _classify_turn(from_forward, to_forward)
		candidates.append({
			"path": path,
			"start_offset": float(endpoint_info["offset"]),
			"direction": direction,
			"turn": turn_label,
			"distance": distance
		})

	return candidates

func _pick_cross_candidate(candidates: Array, command: String) -> Dictionary:
	var normalized := _normalize_turn_command(command)
	var filtered: Array = []

	if normalized != "" and normalized != "random":
		for candidate in candidates:
			if str(candidate["turn"]) == normalized:
				filtered.append(candidate)
		if filtered.is_empty():
			filtered = candidates
	else:
		filtered = candidates

	if filtered.is_empty():
		return {}

	return filtered[_rng.randi_range(0, filtered.size() - 1)]

func _classify_turn(current_forward: Vector3, candidate_forward: Vector3) -> String:
	if current_forward.length() < 0.001 or candidate_forward.length() < 0.001:
		return "random"

	var angle_rad := current_forward.signed_angle_to(candidate_forward, Vector3.UP)
	var angle_deg := rad_to_deg(angle_rad)
	var abs_angle := absf(angle_deg)

	if abs_angle >= 145.0:
		return "u_turn"
	if abs_angle <= 28.0:
		return "straight"
	if angle_deg > 0.0:
		return "left"
	return "right"

func _normalize_turn_command(value: String) -> String:
	var action := value.strip_edges().to_lower()
	match action:
		"turn_left", "choose_left", "left":
			return "left"
		"turn_right", "choose_right", "right":
			return "right"
		"go_straight", "choose_straight", "straight":
			return "straight"
		"u_turn", "choose_u_turn":
			return "u_turn"
		"turn_random", "choose_random_turn", "random_turn", "random":
			return "random"
		_:
			return ""

func _switch_to_nearest_general_from_current_end() -> void:
	var current := _active_path
	if current == null or current.curve == null or _general_paths.is_empty():
		return

	var target_end := _target_endpoint_world(current)
	var current_forward := _forward_at_target_endpoint(current, _direction)
	var best_path: Path3D = null
	var best_offset := 0.0
	var best_direction := 1
	var best_score := INF
	var best_distance := INF

	for path in _general_paths:
		if path == null or path.curve == null:
			continue
		if path == current:
			continue
		var endpoint_options := _endpoint_options_for_target(path, target_end)
		for endpoint_info in endpoint_options:
			var distance := float(endpoint_info["distance"])
			var direction := int(endpoint_info["direction"])
			var candidate_forward := _forward_from_endpoint(path, direction)
			var alignment := 1.0
			if current_forward.length() > 0.001 and candidate_forward.length() > 0.001:
				alignment = current_forward.dot(candidate_forward)
			if alignment < min_connection_alignment:
				continue
			var score := distance + (1.0 - alignment) * 3.0
			if score < best_score:
				best_score = score
				best_distance = distance
				best_path = path
				best_offset = float(endpoint_info["offset"])
				best_direction = direction

	if best_path == null:
		return
	if best_distance > connect_distance * 2.0:
		return

	_set_active_path(best_path, best_offset, best_direction)
	_switch_cooldown = min_switch_interval

func _should_hold_for_red_light() -> bool:
	if not enforce_signal_compliance:
		return false
	if not _is_general_path(_active_path):
		return false
	if not _must_stop_for_light_or_memory():
		return false
	var hold_threshold := maxf(end_reconnect_distance, cross_exit_distance)
	hold_threshold = maxf(hold_threshold, signal_prediction_distance)
	hold_threshold = maxf(hold_threshold, 0.5)
	return _is_near_target_end(_active_path, hold_threshold)

func _set_active_path(path: Path3D, start_offset: float, direction: int) -> void:
	if path == null:
		return

	if get_parent() != path:
		var previous_parent := get_parent()
		if previous_parent != null:
			previous_parent.remove_child(self)
		path.add_child(self)

	_active_path = path
	_direction = 1 if direction >= 0 else -1

	if _active_path.curve != null:
		var length := _active_path.curve.get_baked_length()
		progress = clampf(start_offset, 0.0, length)
	else:
		progress = 0.0

	if enforce_lane_separation:
		progress = _enforce_min_gap_on_path(progress)

	_distance_since_switch = 0.0

func _can_evaluate_path_end() -> bool:
	return _distance_since_switch >= min_travel_before_end_check

func _is_near_target_end(path: Path3D, threshold: float) -> bool:
	if path == null or path.curve == null:
		return false
	var length := path.curve.get_baked_length()
	if _direction > 0:
		return length - progress <= threshold
	return progress <= threshold

func _target_endpoint_world(path: Path3D) -> Vector3:
	if path == null or path.curve == null:
		return global_position
	var length := path.curve.get_baked_length()
	var target_offset := length if _direction > 0 else 0.0
	return path.to_global(path.curve.sample_baked(target_offset, true))

func _best_endpoint_for_position(path: Path3D, world_pos: Vector3) -> Dictionary:
	var length := path.curve.get_baked_length()
	var start_world := path.to_global(path.curve.sample_baked(0.0, true))
	var end_world := path.to_global(path.curve.sample_baked(length, true))
	var d_start := world_pos.distance_to(start_world)
	var d_end := world_pos.distance_to(end_world)

	if d_start <= d_end:
		return {
			"distance": d_start,
			"offset": 0.0,
			"direction": 1
		}
	return {
		"distance": d_end,
		"offset": length,
		"direction": -1
	}

func _endpoint_options_for_target(path: Path3D, world_pos: Vector3) -> Array:
	if path == null or path.curve == null:
		return []
	var length := path.curve.get_baked_length()
	var start_world := path.to_global(path.curve.sample_baked(0.0, true))
	var end_world := path.to_global(path.curve.sample_baked(length, true))
	return [
		{
			"distance": world_pos.distance_to(start_world),
			"offset": 0.0,
			"direction": 1
		},
		{
			"distance": world_pos.distance_to(end_world),
			"offset": length,
			"direction": -1
		}
	]

func _has_cross_candidate_near_endpoint() -> bool:
	if _active_path == null:
		return false
	var source_point := _target_endpoint_world(_active_path)
	return not _gather_cross_candidates(source_point).is_empty()

func _forward_at_target_endpoint(path: Path3D, direction: int) -> Vector3:
	if path == null or path.curve == null:
		return Vector3.ZERO

	var length := path.curve.get_baked_length()
	var step := clampf(length * 0.08, 0.4, 2.4)
	if length < step:
		step = length * 0.5
	if step <= 0.001:
		return Vector3.ZERO

	if direction >= 0:
		var a := path.to_global(path.curve.sample_baked(maxf(length - step, 0.0), true))
		var b := path.to_global(path.curve.sample_baked(length, true))
		return _flat_normalized(b - a)

	var c := path.to_global(path.curve.sample_baked(minf(step, length), true))
	var d := path.to_global(path.curve.sample_baked(0.0, true))
	return _flat_normalized(d - c)

func _forward_from_endpoint(path: Path3D, direction: int) -> Vector3:
	if path == null or path.curve == null:
		return Vector3.ZERO

	var length := path.curve.get_baked_length()
	var step := clampf(length * 0.08, 0.35, 2.0)
	if length < step:
		step = length * 0.5
	if step <= 0.001:
		return Vector3.ZERO

	if direction >= 0:
		var start := path.to_global(path.curve.sample_baked(0.0, true))
		var after := path.to_global(path.curve.sample_baked(step, true))
		return _flat_normalized(after - start)

	var from_end := path.to_global(path.curve.sample_baked(length, true))
	var before_end := path.to_global(path.curve.sample_baked(maxf(length - step, 0.0), true))
	return _flat_normalized(before_end - from_end)

func _flat_normalized(v: Vector3) -> Vector3:
	v.y = 0.0
	if v.length() < 0.001:
		return Vector3.ZERO
	return v.normalized()

func _collect_paths() -> void:
	_general_paths.clear()
	_cross_paths.clear()
	var root := get_tree().current_scene
	if root == null:
		return
	_collect_paths_recursive(root)

func _collect_paths_recursive(node: Node) -> void:
	if node is Path3D:
		var path := node as Path3D
		var lower := path.name.to_lower()
		if lower.begins_with(general_prefix.to_lower()):
			_general_paths.append(path)
		elif lower.begins_with(cross_prefix.to_lower()):
			_cross_paths.append(path)

	for child in node.get_children():
		_collect_paths_recursive(child)

func _bind_cross_area() -> void:
	if cross_area_path != NodePath():
		_cross_area = get_node_or_null(cross_area_path) as Area3D
	if _cross_area == null:
		var root := get_tree().current_scene
		if root != null:
			_cross_area = _find_area_by_name(root, "crossarea")
	if _cross_area == null:
		return
	if not _cross_area.body_entered.is_connected(_on_cross_area_body_entered):
		_cross_area.body_entered.connect(_on_cross_area_body_entered)
	if not _cross_area.body_exited.is_connected(_on_cross_area_body_exited):
		_cross_area.body_exited.connect(_on_cross_area_body_exited)

func _bind_distance_sensor() -> void:
	if distance_sensor_path != NodePath():
		_distance_sensor = get_node_or_null(distance_sensor_path) as RayCast3D
	if _distance_sensor == null:
		_distance_sensor = _find_raycast_by_name(self, "distancesensor")
	if _distance_sensor == null:
		return
	_distance_sensor.enabled = true
	if use_vehicle_only_sensor_mask:
		_distance_sensor.collide_with_bodies = true
		_distance_sensor.collide_with_areas = false
		_distance_sensor.collision_mask = 0
		_distance_sensor.set_collision_mask_value(vehicle_sensor_layer_bit, true)
	if _vehicle_body != null:
		_distance_sensor.add_exception(_vehicle_body)

func _bind_area_distance_sensor() -> void:
	if not use_area_distance_sensor:
		return

	if area_distance_sensor_path != NodePath():
		_area_distance_sensor = get_node_or_null(area_distance_sensor_path) as Area3D
	if _area_distance_sensor == null:
		_area_distance_sensor = _find_area_by_name(self, "areadistancesensor")
	if _area_distance_sensor == null:
		return

	_area_distance_sensor.monitoring = true
	_area_distance_sensor.monitorable = true
	if use_vehicle_only_sensor_mask:
		_area_distance_sensor.collision_mask = 0
		_area_distance_sensor.set_collision_mask_value(vehicle_sensor_layer_bit, true)
	if not _area_distance_sensor.body_entered.is_connected(_on_area_distance_sensor_body_entered):
		_area_distance_sensor.body_entered.connect(_on_area_distance_sensor_body_entered)
	if not _area_distance_sensor.body_exited.is_connected(_on_area_distance_sensor_body_exited):
		_area_distance_sensor.body_exited.connect(_on_area_distance_sensor_body_exited)

func _bind_right_precedence_sensor() -> void:
	if not use_right_precedence_sensor:
		return

	if right_precedence_sensor_path != NodePath():
		_right_precedence_sensor = get_node_or_null(right_precedence_sensor_path) as Area3D
	if _right_precedence_sensor == null:
		_right_precedence_sensor = _find_area_by_name(self, "arearightprecedencesensor")
	if _right_precedence_sensor == null:
		return

	_right_precedence_sensor.monitoring = true
	_right_precedence_sensor.monitorable = true
	if use_vehicle_only_sensor_mask:
		_right_precedence_sensor.collision_mask = 0
		_right_precedence_sensor.set_collision_mask_value(vehicle_sensor_layer_bit, true)
	if not _right_precedence_sensor.body_entered.is_connected(_on_right_precedence_sensor_body_entered):
		_right_precedence_sensor.body_entered.connect(_on_right_precedence_sensor_body_entered)
	if not _right_precedence_sensor.body_exited.is_connected(_on_right_precedence_sensor_body_exited):
		_right_precedence_sensor.body_exited.connect(_on_right_precedence_sensor_body_exited)

func _configure_vehicle_sensor_layer() -> void:
	var body := _vehicle_body as CollisionObject3D
	if body == null:
		return
	body.set_collision_layer_value(1, true)
	body.set_collision_layer_value(vehicle_sensor_layer_bit, true)

func _bind_semaphore_areas() -> void:
	_semaphore_by_area.clear()
	_active_semaphore_areas.clear()
	var root := get_tree().current_scene
	if root == null:
		return
	_bind_semaphore_areas_recursive(root)

func _bind_semaphore_areas_recursive(node: Node) -> void:
	if node is StreetSemaphore:
		var semaphore := node as StreetSemaphore
		var area := semaphore.get_node_or_null(semaphore_area_name) as Area3D
		if area == null:
			area = _find_area_by_name(semaphore, semaphore_area_name)
		if area == null:
			area = _find_first_area(semaphore)
		if area != null:
			area.monitoring = true
			area.monitorable = true
			area.set_collision_mask_value(1, true)
			area.set_collision_mask_value(vehicle_sensor_layer_bit, true)
			_semaphore_by_area[area] = semaphore
			var entered := Callable(self, "_on_semaphore_area_body_entered").bind(area)
			var exited := Callable(self, "_on_semaphore_area_body_exited").bind(area)
			if not area.body_entered.is_connected(entered):
				area.body_entered.connect(entered)
			if not area.body_exited.is_connected(exited):
				area.body_exited.connect(exited)

	for child in node.get_children():
		_bind_semaphore_areas_recursive(child)

func _find_raycast_by_name(node: Node, ray_name: String) -> RayCast3D:
	if node is RayCast3D and node.name.to_lower() == ray_name.to_lower():
		return node as RayCast3D
	for child in node.get_children():
		var found := _find_raycast_by_name(child, ray_name)
		if found != null:
			return found
	return null

func _find_area_by_name(node: Node, area_name: String) -> Area3D:
	if node is Area3D and node.name.to_lower() == area_name.to_lower():
		return node as Area3D
	for child in node.get_children():
		var found := _find_area_by_name(child, area_name)
		if found != null:
			return found
	return null

func _find_first_area(node: Node) -> Area3D:
	if node is Area3D:
		return node as Area3D
	for child in node.get_children():
		var found := _find_first_area(child)
		if found != null:
			return found
	return null

func _on_cross_area_body_entered(body: Node3D) -> void:
	if not _is_this_vehicle(body):
		return
	_inside_cross_area = true
	_intersection_wait = 0.0
	_reset_intersection_unblock_state()

func _on_cross_area_body_exited(body: Node3D) -> void:
	if not _is_this_vehicle(body):
		return
	_inside_cross_area = false
	_intersection_locked = false
	_intersection_wait = 0.0
	_reset_intersection_unblock_state()
	_pending_turn_command = ""

func _on_semaphore_area_body_entered(body: Node3D, area: Area3D) -> void:
	if not _is_this_vehicle(body):
		return
	_active_semaphore_areas[area] = true
	if _must_stop_for_light():
		_signal_stop_memory = signal_stop_memory_seconds
	if debug_agent_io:
		print("[%s] entered semaphore area, light=%s" % [agent_id, _get_current_light_label()])
	_request_urgent_send()

func _on_semaphore_area_body_exited(body: Node3D, area: Area3D) -> void:
	if not _is_this_vehicle(body):
		return
	_active_semaphore_areas.erase(area)
	if debug_agent_io:
		print("[%s] exited semaphore area" % [agent_id])
	_request_urgent_send()

func _on_area_distance_sensor_body_entered(body: Node3D) -> void:
	if not _is_relevant_obstacle(body):
		return
	_vehicles_in_area_sensor[body.get_instance_id()] = body
	_request_urgent_send()

func _on_area_distance_sensor_body_exited(body: Node3D) -> void:
	_vehicles_in_area_sensor.erase(body.get_instance_id())
	_request_urgent_send()

func _on_right_precedence_sensor_body_entered(body: Node3D) -> void:
	if not _is_relevant_obstacle(body):
		return
	_vehicles_on_right_precedence_sensor[body.get_instance_id()] = body
	if debug_agent_io:
		print("[%s] right-priority sensor entered: %s" % [agent_id, body.name])
	_request_urgent_send()

func _on_right_precedence_sensor_body_exited(body: Node3D) -> void:
	_vehicles_on_right_precedence_sensor.erase(body.get_instance_id())
	if debug_agent_io:
		print("[%s] right-priority sensor exited: %s" % [agent_id, body.name])
	_request_urgent_send()

func _update_intersection_guard(delta: float) -> void:
	var previous_deadlock_risk := _intersection_guard_deadlock_risk
	_intersection_guard_deadlock_risk = false
	_intersection_guard_queue_size = 0

	if not use_intersection_guard:
		_reset_intersection_unblock_state()
		return

	if not _inside_cross_area:
		_reset_intersection_unblock_state()
		return

	if _intersection_unblock_target_wait_seconds <= 0.0:
		_intersection_unblock_target_wait_seconds = _sample_intersection_wait_threshold()

	_intersection_guard_queue_size = _count_vehicles_in_same_intersection()

	if _intersection_unblock_active_seconds > 0.0:
		_intersection_unblock_active_seconds = maxf(0.0, _intersection_unblock_active_seconds - delta)
	else:
		if absf(_speed) <= intersection_stop_speed_threshold:
			_intersection_wait_seconds += delta
		else:
			_intersection_wait_seconds = 0.0
			_intersection_unblock_target_wait_seconds = _sample_intersection_wait_threshold()

		if _intersection_wait_seconds >= _intersection_unblock_target_wait_seconds:
			_intersection_guard_deadlock_risk = true
			_intersection_unblock_active_seconds = maxf(intersection_unblock_duration_seconds, 0.2)
			_intersection_wait_seconds = 0.0
			_intersection_unblock_target_wait_seconds = _sample_intersection_wait_threshold()
			if debug_agent_io:
				print("[%s] intersection unblock activated for %.2fs" % [agent_id, _intersection_unblock_active_seconds])

	if _intersection_guard_deadlock_risk != previous_deadlock_risk:
		_request_urgent_send()

func _sample_intersection_wait_threshold() -> float:
	var min_wait := maxf(0.1, intersection_random_wait_min_seconds)
	var max_wait := maxf(min_wait, intersection_random_wait_max_seconds)
	return _rng.randf_range(min_wait, max_wait)

func _reset_intersection_unblock_state() -> void:
	_intersection_wait_seconds = 0.0
	_intersection_guard_deadlock_risk = false
	_intersection_guard_queue_size = 0
	_intersection_unblock_active_seconds = 0.0
	_intersection_unblock_target_wait_seconds = _sample_intersection_wait_threshold()

func _get_intersection_guard_key() -> String:
	var configured := intersection_guard_id.strip_edges()
	if configured != "":
		return configured
	if _cross_area != null:
		return str(_cross_area.get_path())
	return "default_intersection"

func _count_vehicles_in_same_intersection() -> int:
	var key := _get_intersection_guard_key()
	var count := 0
	for node_variant in get_tree().get_nodes_in_group(VEHICLE_GROUP):
		var node := node_variant as Node
		if node == null:
			continue
		if not node.has_method("is_inside_intersection"):
			continue
		if not bool(node.call("is_inside_intersection")):
			continue
		if not node.has_method("get_intersection_guard_key"):
			continue
		var other_key := str(node.call("get_intersection_guard_key"))
		if other_key != key:
			continue
		count += 1
	return count

func _must_stop_for_light() -> bool:
	var light := _get_current_light_label()
	return light == "red" or light == "yellow"

func _must_stop_for_light_or_memory() -> bool:
	return _must_stop_for_light() or _signal_stop_memory > 0.0

func _get_current_light_label() -> String:
	var semaphore := _get_closest_active_semaphore()
	if semaphore == null:
		semaphore = _get_predicted_semaphore_for_approach()
	if semaphore == null:
		return ""
	match int(semaphore.status):
		0:
			return "red"
		1:
			return "yellow"
		2:
			return "green"
		_:
			return ""

func _get_closest_active_semaphore() -> StreetSemaphore:
	var best: StreetSemaphore = null
	var best_distance := INF

	for area in _active_semaphore_areas.keys():
		if not _active_semaphore_areas[area]:
			continue
		var semaphore := _semaphore_by_area.get(area) as StreetSemaphore
		if semaphore == null:
			continue
		var distance := semaphore.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = semaphore

	return best

func _get_predicted_semaphore_for_approach() -> StreetSemaphore:
	if not use_signal_prediction:
		return null
	if not _is_general_path(_active_path):
		return null
	if not _is_near_target_end(_active_path, signal_prediction_distance):
		return null

	var target := _target_endpoint_world(_active_path)
	var best: StreetSemaphore = null
	var best_distance := INF
	var seen: Dictionary = {}

	for area in _semaphore_by_area.keys():
		var semaphore := _semaphore_by_area.get(area) as StreetSemaphore
		if semaphore == null:
			continue
		var key := semaphore.get_instance_id()
		if seen.has(key):
			continue
		seen[key] = true
		var distance := semaphore.global_position.distance_to(target)
		if distance < best_distance:
			best_distance = distance
			best = semaphore

	if best == null:
		return null
	if best_distance > signal_prediction_radius:
		return null

	return best

func _compute_obstacle_speed_cap() -> float:
	var distance := _get_front_obstacle_distance()
	if distance < 0.0:
		return max_speed

	var sensor_length := _distance_sensor.target_position.length()
	var start_distance := slowdown_start_distance if slowdown_start_distance > 0.0 else sensor_length
	start_distance = maxf(start_distance, 0.05)
	var stop_distance := clampf(full_stop_distance, 0.0, start_distance - 0.01)

	if distance <= stop_distance:
		return max_speed * clampf(min_speed_factor_when_close, 0.0, 1.0)
	if distance >= start_distance:
		return max_speed

	var t := inverse_lerp(stop_distance, start_distance, distance)
	var factor := lerpf(min_speed_factor_when_close, 1.0, t)
	return max_speed * clampf(factor, 0.0, 1.0)

func _compute_lane_separation_speed_cap() -> float:
	var lead_distance := _distance_to_leader_on_same_path()
	if lead_distance < 0.0:
		return max_speed

	var stop_distance := maxf(min_vehicle_gap, 0.2)
	var slow_distance := maxf(separation_slow_distance, stop_distance + 0.5)

	if lead_distance <= stop_distance:
		return 0.0
	if lead_distance >= slow_distance:
		return max_speed

	var t := inverse_lerp(stop_distance, slow_distance, lead_distance)
	return max_speed * clampf(t, 0.0, 1.0)

func _apply_safe_progress_limit(next_progress: float) -> float:
	var leader_progress := _leader_progress_on_same_path()
	if leader_progress < 0.0:
		return next_progress

	var path_length := 0.0
	if _active_path != null and _active_path.curve != null:
		path_length = _active_path.curve.get_baked_length()

	var safe_gap := maxf(min_vehicle_gap, 0.1)
	if _direction > 0:
		var max_progress := leader_progress - safe_gap
		return clampf(minf(next_progress, max_progress), 0.0, path_length)
	var min_progress := leader_progress + safe_gap
	return clampf(maxf(next_progress, min_progress), 0.0, path_length)

func _distance_to_leader_on_same_path() -> float:
	var leader_progress := _leader_progress_on_same_path()
	if leader_progress < 0.0:
		return -1.0
	return absf(leader_progress - progress)

func _leader_progress_on_same_path() -> float:
	if _active_path == null:
		return -1.0

	var best_delta := INF
	var leader_progress := -1.0
	for node in get_tree().get_nodes_in_group(VEHICLE_GROUP):
		if node == self:
			continue
		if not (node is PathFollow3D):
			continue
		if not node.has_method("get_active_lane_path"):
			continue
		if not node.has_method("get_lane_direction"):
			continue
		var other_path := node.call("get_active_lane_path") as Path3D
		if other_path != _active_path:
			continue
		var other_direction := int(node.call("get_lane_direction"))
		if other_direction != _direction:
			continue

		var other_progress := (node as PathFollow3D).progress
		var delta := (other_progress - progress) * float(_direction)
		if delta <= 0.0:
			if absf(delta) <= 0.05 and node.get_instance_id() < get_instance_id():
				delta = 0.001
			else:
				continue
		if delta < best_delta:
			best_delta = delta
			leader_progress = other_progress

	return leader_progress

func _enforce_min_gap_on_path(current_progress: float) -> float:
	if _active_path == null or _active_path.curve == null:
		return current_progress
	var leader_progress := _leader_progress_on_same_path()
	if leader_progress < 0.0:
		return current_progress

	var path_length := _active_path.curve.get_baked_length()
	var safe_gap := maxf(min_vehicle_gap, 0.1)
	if _direction > 0:
		return clampf(minf(current_progress, leader_progress - safe_gap), 0.0, path_length)
	return clampf(maxf(current_progress, leader_progress + safe_gap), 0.0, path_length)

func _get_front_obstacle_distance() -> float:
	if _distance_sensor == null:
		return -1.0
	if not _distance_sensor.is_colliding():
		return -1.0

	var collider := _distance_sensor.get_collider() as Node
	if not _is_relevant_obstacle(collider):
		return -1.0

	var hit := _distance_sensor.get_collision_point()
	return _distance_sensor.global_position.distance_to(hit)

func _is_relevant_obstacle(collider: Node) -> bool:
	if collider == null:
		return false
	if collider == self:
		return false
	if is_ancestor_of(collider):
		return false

	var node := collider
	while node != null:
		if node == self:
			return false
		if node is CharacterBody3D or node is VehicleBody3D:
			return true
		node = node.get_parent()
	return false

func _is_this_vehicle(node: Node3D) -> bool:
	if node == null:
		return false
	if _vehicle_body == null:
		return node == self or is_ancestor_of(node) or node.is_ancestor_of(self)
	if node == _vehicle_body:
		return true
	return _vehicle_body.is_ancestor_of(node) or node.is_ancestor_of(_vehicle_body)

func _request_urgent_send() -> void:
	if not send_urgent_on_sensor_events:
		return
	_urgent_send_requested = true

func _has_area_vehicle_ahead() -> bool:
	if _vehicles_in_area_sensor.is_empty():
		return false
	var stale_ids: Array = []
	for id in _vehicles_in_area_sensor.keys():
		var node := _vehicles_in_area_sensor[id] as Node
		if node == null or not is_instance_valid(node):
			stale_ids.append(id)
			continue
		if _is_relevant_obstacle(node):
			return true
		stale_ids.append(id)
	for stale in stale_ids:
		_vehicles_in_area_sensor.erase(stale)
	return false

func _must_yield_to_right() -> bool:
	if not use_right_precedence_sensor:
		return false
	if use_intersection_guard and _inside_cross_area and _intersection_unblock_active_seconds > 0.0:
		return false
	if right_precedence_only_in_intersection and not _inside_cross_area:
		return false
	return _has_vehicle_on_right_precedence_sensor()

func _has_vehicle_on_right_precedence_sensor() -> bool:
	if _vehicles_on_right_precedence_sensor.is_empty():
		return false
	var stale_ids: Array = []
	for id in _vehicles_on_right_precedence_sensor.keys():
		var node := _vehicles_on_right_precedence_sensor[id] as Node
		if node == null or not is_instance_valid(node):
			stale_ids.append(id)
			continue
		if _is_relevant_obstacle(node):
			return true
		stale_ids.append(id)
	for stale in stale_ids:
		_vehicles_on_right_precedence_sensor.erase(stale)
	return false

func _use_prolog_drive_control() -> bool:
	if not use_prolog_agent:
		return false
	if connected:
		return true
	return not use_manual_input_when_offline

func _tick_agent_connection(delta: float) -> void:
	if not use_prolog_agent:
		return
	if ws == null:
		return

	ws.poll()
	connected = ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	if not connected:
		return

	_agent_elapsed += delta
	if _urgent_send_requested or _agent_elapsed >= send_interval:
		_agent_elapsed = 0.0
		_urgent_send_requested = false
		_send_agent_percepts()

	while ws.get_available_packet_count() > 0:
		var packet := ws.get_packet()
		if not ws.was_string_packet():
			continue
		_handle_agent_message(packet.get_string_from_utf8())

func _build_ws() -> void:
	ws = WebSocketPeer.new()

func _connect_ws() -> void:
	if ws_url.strip_edges() == "":
		return
	var err := ws.connect_to_url(ws_url)
	if err != OK:
		push_warning("WebSocket connect error for %s: %s url: %s" % [agent_id, err, ws_url])

func reconnect(url: String) -> void:
	ws_url = url
	connected = false
	_theory_sent = false
	if ws != null:
		ws.close()
	_build_ws()
	_connect_ws()

func _handle_agent_message(text: String) -> void:
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
		_energy = float(data["energy"])
	if data.has("action"):
		var action := str(data["action"])
		_apply_prolog_action(action)
		if debug_agent_io:
			print("[%s] action=%s energy=%s" % [agent_id, action, str(_energy)])

func _send_agent_percepts() -> void:
	var payload := {
		"agent": agent_id,
		"percepts": _build_agent_percepts()
	}
	if _theory_text != "" and (_theory_dirty or not _theory_sent):
		payload["theory"] = _theory_text
		_theory_sent = true
		_theory_dirty = false

	var text := JSON.stringify(payload)
	if ws.has_method("send_text"):
		ws.send_text(text)
	else:
		ws.put_packet(text.to_utf8_buffer())
	if debug_agent_io:
		print("[%s] percepts=%s" % [agent_id, str(payload["percepts"])])

func _build_agent_percepts() -> Array:
	var percepts: Array = []

	var light := _get_current_light_label()
	if light == "":
		percepts.append("light_none")
	else:
		percepts.append("light_" + light)
	if _must_stop_for_light_or_memory():
		percepts.append("must_stop_signal")

	if _inside_cross_area:
		percepts.append("at_intersection")
		var turns := _available_turn_labels()
		for turn_label in turns:
			percepts.append("can_turn_" + turn_label)

	if _must_yield_to_right():
		percepts.append("yield_to_right")

	if use_intersection_guard:
		if _intersection_guard_deadlock_risk:
			percepts.append("deadlock_risk")
		if _intersection_unblock_active_seconds > 0.0:
			percepts.append("intersection_unblock")
		if _intersection_guard_queue_size >= intersection_min_blocked_vehicles:
			percepts.append("intersection_congested")
		if _inside_cross_area and _intersection_wait_seconds >= intersection_deadlock_threshold_seconds:
			percepts.append("stopped_long_in_intersection")

	var front_distance := _get_front_obstacle_distance()
	var area_vehicle := use_area_distance_sensor and _has_area_vehicle_ahead()
	if front_distance >= 0.0 or area_vehicle:
		percepts.append("vehicle_ahead")
		if area_vehicle:
			percepts.append("vehicle_in_area_sensor")
		if front_distance >= 0.0:
			var very_close_threshold := maxf(full_stop_distance, prolog_vehicle_very_close_distance)
			var close_threshold := maxf(very_close_threshold + 0.25, prolog_vehicle_close_distance)
			if front_distance <= very_close_threshold:
				percepts.append("vehicle_very_close")
			elif front_distance <= close_threshold:
				percepts.append("vehicle_close")
		elif area_vehicle:
			percepts.append("vehicle_close")

	if _speed <= 0.2:
		percepts.append("vehicle_stopped")
	else:
		percepts.append("vehicle_moving")

	if _is_general_path(_active_path):
		percepts.append("on_general_path")
	elif _is_cross_path(_active_path):
		percepts.append("on_cross_path")

	return percepts

func _available_turn_labels() -> Array:
	if _active_path == null or not _is_general_path(_active_path):
		return []
	var source_point := _target_endpoint_world(_active_path)
	var candidates := _gather_cross_candidates(source_point)
	var labels: Array = []
	for candidate in candidates:
		var turn_label := str(candidate["turn"])
		if turn_label == "":
			continue
		if not labels.has(turn_label):
			labels.append(turn_label)
	return labels

func _apply_prolog_action(action: String) -> void:
	var normalized := action.strip_edges().to_lower()
	_last_action = normalized

	match normalized:
		"drive", "accelerate", "move_forward":
			_prolog_speed_factor = 1.0
		"cruise":
			_prolog_speed_factor = 0.7
		"slow", "slow_down":
			_prolog_speed_factor = 0.2
		"reverse":
			_prolog_speed_factor = -1.0
		"stop", "idle", "wait", "hold", "brake", "rest":
			_prolog_speed_factor = 0.0
		"turn_left", "choose_left", "left":
			_pending_turn_command = "left"
		"turn_right", "choose_right", "right":
			_pending_turn_command = "right"
		"go_straight", "choose_straight", "straight":
			_pending_turn_command = "straight"
		"u_turn", "choose_u_turn":
			_pending_turn_command = "u_turn"
		"turn_random", "choose_random_turn", "random_turn":
			_pending_turn_command = "random"
		_:
			pass

func set_theory(text: String) -> void:
	_theory_text = text
	_theory_dirty = true
	_theory_sent = false

func _load_theory_from_path() -> void:
	if prolog_path == "":
		return
	if not FileAccess.file_exists(prolog_path):
		push_warning("Missing prolog file: %s" % prolog_path)
		return
	var f := FileAccess.open(prolog_path, FileAccess.READ)
	if f == null:
		push_warning("Unable to open prolog file: %s" % prolog_path)
		return
	set_theory(f.get_as_text())

func get_energy() -> float:
	return _energy

func get_last_action() -> String:
	return _last_action

func get_active_lane_path() -> Path3D:
	return _active_path

func get_lane_direction() -> int:
	return _direction

func is_inside_intersection() -> bool:
	return _inside_cross_area

func get_intersection_guard_key() -> String:
	return _get_intersection_guard_key()

func get_intersection_wait_seconds() -> float:
	return _intersection_wait_seconds

func get_vehicle_speed_mps() -> float:
	return absf(_speed)

func get_distance_to_intersection_exit() -> float:
	if _active_path == null or _active_path.curve == null:
		return INF
	var length := _active_path.curve.get_baked_length()
	if _direction > 0:
		return maxf(0.0, length - progress)
	return maxf(0.0, progress)

func _is_general_path(path: Path3D) -> bool:
	if path == null:
		return false
	return path.name.to_lower().begins_with(general_prefix.to_lower())

func _is_cross_path(path: Path3D) -> bool:
	if path == null:
		return false
	return path.name.to_lower().begins_with(cross_prefix.to_lower())
