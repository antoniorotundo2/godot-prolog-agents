extends VehicleBody3D

@onready var front_left: VehicleWheel3D = $FrontLeft
@onready var front_right: VehicleWheel3D = $FrontRight
@onready var rear_right: VehicleWheel3D = $RearRight
@onready var rear_left: VehicleWheel3D = $RearLeft


@export var use_player_input := true
@export var max_engine_force := 1800.0
@export var max_brake_force := 65.0
@export var max_steer_angle_deg := 28.0
@export var steer_response := 6.0
@export var throttle_response := 4.0
@export var brake_response := 8.0
@export var reverse_force_factor := 0.55

@export_group("Lane Follow")
@export var use_lane_follow := true
@export var manual_throttle_when_lane_follow := true
@export var path_lookahead := 4.0
@export var min_path_lookahead := 1.8
@export var max_path_lookahead := 5.5
@export var lookahead_speed_factor := 0.25
@export var path_snap_distance := 6.0
@export var path_release_distance := 10.0
@export var min_path_alignment := 0.35
@export var cruise_speed := 18.0
@export var curve_speed := 10.0

@export_group("Steering PID")
@export var use_steer_pid := true
@export var pid_kp := 2.2
@export var pid_ki := 0.08
@export var pid_kd := 0.55
@export var pid_integral_limit := 1.4
@export var pid_derivative_filter := 0.2
@export var pid_heading_weight := 0.75
@export var pid_cross_track_weight := 0.25
@export var cross_track_angle_gain := 0.35
@export var pid_deadzone := 0.012
@export var pid_integral_active_error := 0.18
@export var max_steer_command := 0.9

@export_group("Straight Stabilization")
@export var straight_curvature_threshold := 0.035
@export var straight_heading_threshold_deg := 5.0
@export var straight_cross_track_threshold := 0.55
@export var straight_steer_damping := 5.5
@export var curvature_speed_gain := 12.0

@export var wheel_friction:float = 10.5
@export var suspension_stiff_value : float = 50.0

@export_group("Stability Control")
@export var roll_influence : float = 0.5
var anti_roll_torque:Vector3
var downforce:Vector3
@export var anti_roll_force:float = 20.0
@export var downforce_factor:float = 50.0

var _cmd_throttle := 0.0
var _cmd_brake := 0.0
var _cmd_steer := 0.0

var _throttle := 0.0
var _brake := 0.0
var _steer := 0.0
var _lane_paths: Array[Path3D] = []
var _active_lane_path: Path3D = null
var _pid_integral := 0.0
var _pid_prev_error := 0.0
var _pid_d_filtered := 0.0
var _pid_path_id := -1

func _ready() -> void:
	for wheel in [front_left, front_right, rear_left, rear_right]:
		wheel.wheel_friction_slip = wheel_friction
		wheel.suspension_stiffness = suspension_stiff_value
		wheel.wheel_roll_influence = roll_influence
	_cache_lane_paths()


func _physics_process(delta: float) -> void:
	if use_player_input:
		_update_player_command()
	elif use_lane_follow:
		_update_lane_follow_command(delta)

	_throttle = move_toward(_throttle, _cmd_throttle, throttle_response * delta)
	_brake = move_toward(_brake, _cmd_brake, brake_response * delta)
	_steer = move_toward(_steer, _cmd_steer, steer_response * delta)

	engine_force = _throttle * max_engine_force
	brake = _brake * max_brake_force
	steering = _steer * deg_to_rad(max_steer_angle_deg)
	handle_anti_roll()

func _cache_lane_paths() -> void:
	_lane_paths.clear()
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	_collect_lane_paths(scene_root)

func _collect_lane_paths(node: Node) -> void:
	if node is Path3D:
		_lane_paths.append(node as Path3D)
	for child in node.get_children():
		_collect_lane_paths(child)

func _update_lane_follow_command(delta: float) -> void:
	var path := _get_closest_lane_path()
	if path == null:
		_reset_steering_pid()
		_cmd_steer = 0.0
		if manual_throttle_when_lane_follow:
			_update_manual_longitudinal_command()
		else:
			_cmd_throttle = 0.0
			_cmd_brake = 0.35
		return

	var curve := path.curve
	if curve == null or curve.point_count < 2:
		_reset_steering_pid()
		_cmd_steer = 0.0
		if manual_throttle_when_lane_follow:
			_update_manual_longitudinal_command()
		else:
			_cmd_throttle = 0.0
			_cmd_brake = 0.35
		return

	var local_pos := path.to_local(global_position)
	var closest_offset := curve.get_closest_offset(local_pos)
	var local_closest := curve.sample_baked(closest_offset, true)
	var world_closest := path.to_global(local_closest)
	var path_error := world_closest.distance_to(global_position)
	var forward_speed := maxf(0.0, linear_velocity.dot(-global_basis.z))
	var dynamic_lookahead := clampf(
		forward_speed * lookahead_speed_factor + path_lookahead,
		min_path_lookahead,
		max_path_lookahead
	)
	# When far from the lane center, reduce lookahead to avoid early cutting.
	if path_error > 1.4:
		dynamic_lookahead *= 0.55
	var target_offset := minf(closest_offset + dynamic_lookahead, curve.get_baked_length())
	var local_target := curve.sample_baked(target_offset, true)
	var world_target := path.to_global(local_target)

	if use_steer_pid:
		var path_id := path.get_instance_id()
		if _pid_path_id != path_id:
			_pid_path_id = path_id
			_reset_steering_pid()
		var tangent_offset := minf(closest_offset + 1.0, curve.get_baked_length())
		var local_tangent := curve.sample_baked(tangent_offset, true)
		var world_tangent := path.to_global(local_tangent)
		var tangent_ahead_offset := minf(closest_offset + 3.5, curve.get_baked_length())
		var local_tangent_ahead := curve.sample_baked(tangent_ahead_offset, true)
		var world_tangent_ahead := path.to_global(local_tangent_ahead)
		var path_forward := (world_tangent - world_closest)
		var path_forward_ahead := (world_tangent_ahead - world_tangent)
		var curvature := _compute_path_curvature(path_forward, path_forward_ahead, 2.5)
		_cmd_steer = _compute_pid_steer(world_closest, path_forward, delta, curvature, forward_speed)
	else:
		steer_towards_point(world_target)

	var curve_factor := clampf(_estimate_local_curve_factor(path, curve, closest_offset), 0.0, 1.0)
	var target_speed := lerpf(cruise_speed, curve_speed, curve_factor)
	if manual_throttle_when_lane_follow:
		_update_manual_longitudinal_command()
	else:
		if forward_speed < target_speed:
			_cmd_throttle = 1.0
			_cmd_brake = 0.0
		else:
			_cmd_throttle = 0.0
			_cmd_brake = clampf((forward_speed - target_speed) / maxf(target_speed, 0.1), 0.0, 1.0)

func _get_closest_lane_path() -> Path3D:
	if _lane_paths.is_empty():
		_cache_lane_paths()
	if _lane_paths.is_empty():
		return null

	if _active_lane_path != null and _is_path_still_valid(_active_lane_path):
		return _active_lane_path

	var best_path: Path3D = null
	var best_dist := INF
	for path in _lane_paths:
		if path == null or path.curve == null:
			continue
		var local_pos := path.to_local(global_position)
		var local_closest := path.curve.get_closest_point(local_pos)
		var world_closest := path.to_global(local_closest)
		var d := world_closest.distance_to(global_position)
		var alignment := _path_alignment(path, local_pos)
		if alignment < min_path_alignment:
			continue
		if d < best_dist:
			best_dist = d
			best_path = path

	if best_dist > path_snap_distance:
		_active_lane_path = null
		return null
	_active_lane_path = best_path
	return best_path

func _is_path_still_valid(path: Path3D) -> bool:
	if path == null or path.curve == null:
		return false
	var local_pos := path.to_local(global_position)
	var local_closest := path.curve.get_closest_point(local_pos)
	var world_closest := path.to_global(local_closest)
	return world_closest.distance_to(global_position) <= path_release_distance

func _path_alignment(path: Path3D, local_pos: Vector3) -> float:
	var curve := path.curve
	if curve == null:
		return -1.0
	var offset := curve.get_closest_offset(local_pos)
	var next_offset := minf(offset + 1.0, curve.get_baked_length())
	var p0 := path.to_global(curve.sample_baked(offset, true))
	var p1 := path.to_global(curve.sample_baked(next_offset, true))
	var tangent := (p1 - p0)
	tangent.y = 0.0
	if tangent.length() < 0.01:
		return 0.0
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return 0.0
	return tangent.normalized().dot(forward.normalized())

func _reset_steering_pid() -> void:
	_pid_integral = 0.0
	_pid_prev_error = 0.0
	_pid_d_filtered = 0.0
	_pid_path_id = -1

func _compute_pid_steer(world_closest: Vector3, path_forward: Vector3, delta: float, curvature: float, forward_speed: float) -> float:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return 0.0
	forward = forward.normalized()

	path_forward.y = 0.0
	if path_forward.length() < 0.001:
		return 0.0
	path_forward = path_forward.normalized()

	var heading_error := forward.signed_angle_to(path_forward, Vector3.UP)

	var to_path := world_closest - global_position
	to_path.y = 0.0
	var cross_track_signed := -to_path.dot(global_basis.x)
	var cross_track_angle := atan(cross_track_signed * cross_track_angle_gain)

	var error := heading_error * pid_heading_weight + cross_track_angle * pid_cross_track_weight
	if absf(error) < pid_deadzone:
		error = 0.0
	var dt := maxf(delta, 0.0001)

	if absf(error) < pid_integral_active_error and forward_speed > 0.5:
		_pid_integral = clampf(_pid_integral + error * dt, -pid_integral_limit, pid_integral_limit)
	else:
		_pid_integral = move_toward(_pid_integral, 0.0, dt * 1.8)

	var d_raw := (error - _pid_prev_error) / dt
	_pid_d_filtered = lerpf(_pid_d_filtered, d_raw, pid_derivative_filter)
	_pid_prev_error = error

	var steer_angle_cmd := pid_kp * error + pid_ki * _pid_integral + pid_kd * _pid_d_filtered
	var max_steer_rad := deg_to_rad(max_steer_angle_deg)
	if max_steer_rad <= 0.0001:
		return 0.0
	var steer_cmd := clampf(steer_angle_cmd / max_steer_rad, -max_steer_command, max_steer_command)

	var straight_heading_threshold := deg_to_rad(straight_heading_threshold_deg)
	if curvature < straight_curvature_threshold and absf(heading_error) < straight_heading_threshold and absf(cross_track_signed) < straight_cross_track_threshold:
		steer_cmd = move_toward(steer_cmd, 0.0, straight_steer_damping * dt)

	return steer_cmd

func _compute_path_curvature(path_forward: Vector3, path_forward_ahead: Vector3, arc_len: float) -> float:
	path_forward.y = 0.0
	path_forward_ahead.y = 0.0
	if path_forward.length() < 0.001 or path_forward_ahead.length() < 0.001:
		return 0.0
	var a := path_forward.normalized()
	var b := path_forward_ahead.normalized()
	var delta_heading := absf(a.signed_angle_to(b, Vector3.UP))
	return delta_heading / maxf(arc_len, 0.001)

func _estimate_local_curve_factor(path: Path3D, curve: Curve3D, offset: float) -> float:
	var off1 := minf(offset + 2.5, curve.get_baked_length())
	var off2 := minf(offset + 5.0, curve.get_baked_length())
	var p0 := path.to_global(curve.sample_baked(offset, true))
	var p1 := path.to_global(curve.sample_baked(off1, true))
	var p2 := path.to_global(curve.sample_baked(off2, true))
	var v1 := p1 - p0
	var v2 := p2 - p1
	var k := _compute_path_curvature(v1, v2, 2.5)
	return clampf(k * curvature_speed_gain, 0.0, 1.0)

func _update_player_command() -> void:
	var forward_pressed := Input.is_action_pressed("ui_up")
	var down_pressed := Input.is_action_pressed("ui_down")
	var left_pressed := Input.is_action_pressed("ui_left")
	var right_pressed := Input.is_action_pressed("ui_right")
	var handbrake_pressed := Input.is_action_pressed("ui_select")

	var forward_speed := linear_velocity.dot(-global_basis.z)

	_cmd_throttle = 0.0
	_cmd_brake = 0.0
	_cmd_steer = Input.get_axis("ui_right", "ui_left")

	if forward_pressed:
		_cmd_throttle = 1.0

	if down_pressed:
		if forward_speed > 1.5:
			_cmd_brake = 1.0
		else:
			_cmd_throttle = -reverse_force_factor

	if handbrake_pressed:
		_cmd_brake = 1.0

	if absf(_cmd_steer) < 0.001 and not left_pressed and not right_pressed:
		_cmd_steer = 0.0

func _update_manual_longitudinal_command() -> void:
	var forward_pressed := Input.is_action_pressed("ui_up")
	var down_pressed := Input.is_action_pressed("ui_down")
	var handbrake_pressed := Input.is_action_pressed("ui_select")
	var forward_speed := linear_velocity.dot(-global_basis.z)

	_cmd_throttle = 0.0
	_cmd_brake = 0.0

	if forward_pressed:
		_cmd_throttle = 1.0

	if down_pressed:
		if forward_speed > 1.5:
			_cmd_brake = 1.0
		else:
			_cmd_throttle = -reverse_force_factor

	if handbrake_pressed:
		_cmd_brake = 1.0

func set_drive_command(throttle: float, brake_strength: float, steer: float) -> void:
	use_player_input = false
	_cmd_throttle = clampf(throttle, -1.0, 1.0)
	_cmd_brake = clampf(brake_strength, 0.0, 1.0)
	_cmd_steer = clampf(steer, -1.0, 1.0)

func steer_towards_point(world_point: Vector3) -> void:
	var to_target := world_point - global_position
	to_target.y = 0.0
	if to_target.length() < 0.1:
		return

	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return

	var signed_angle := forward.normalized().signed_angle_to(to_target.normalized(), Vector3.UP)
	var max_angle := deg_to_rad(max_steer_angle_deg)
	_cmd_steer = clampf(signed_angle / max_angle, -1.0, 1.0)

func handle_anti_roll():
	anti_roll_torque = -global_transform.basis.z * global_rotation.z * anti_roll_force * max_engine_force
	apply_torque(anti_roll_torque)
	
	downforce = -global_transform.basis.y * linear_velocity * downforce_factor
	apply_central_force(downforce)
	
	
