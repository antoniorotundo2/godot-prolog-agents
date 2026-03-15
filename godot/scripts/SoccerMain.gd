extends Node3D

const LeftAgentScene = preload("res://scenes/SoccerAgentLeft.tscn")
const RightAgentScene = preload("res://scenes/SoccerAgentRight.tscn")

var agents: Array = []
var agent_actions := {}
var agent_counter := 0

var score_left := 0
var score_right := 0
var goal_line := 9.0

var ws_url := "ws://127.0.0.1:8080/ws"

@onready var ball: RigidBody3D = $Ball
@onready var ui_label: Label = $UI/InfoLabel
@onready var ws_url_field: LineEdit = $UI/WsUrl

func _ready() -> void:
	ws_url_field.text = ws_url
	ws_url_field.text_submitted.connect(_on_ws_url_entered)
	ws_url_field.focus_exited.connect(_on_ws_url_focus_exited)

	spawn_agent(LeftAgentScene)
	spawn_agent(RightAgentScene)
	update_ui()

func _process(_delta: float) -> void:
	check_goal()

func _on_ws_url_entered(text: String) -> void:
	apply_ws_url(text)

func _on_ws_url_focus_exited() -> void:
	apply_ws_url(ws_url_field.text)

func apply_ws_url(text: String) -> void:
	if text == "" or text == ws_url:
		return
	ws_url = text
	for a in agents:
		a.reconnect(ws_url)
	update_ui()

func spawn_agent(scene: PackedScene) -> void:
	var a = scene.instantiate()
	$Agents.add_child(a)
	agent_counter += 1
	var id = "Agent_%d" % agent_counter
	a.setup(id, self, ws_url)
	if a.has_method("init_agent"):
		a.init_agent()
	a.action_received.connect(_on_agent_action)
	agents.append(a)
	agent_actions[id] = "idle"

func _on_agent_action(agent_id: String, action: String) -> void:
	agent_actions[agent_id] = action
	update_ui()

func update_ui() -> void:
	var lines: Array[String] = []
	lines.append("Score: Left %d - Right %d" % [score_left, score_right])
	lines.append("WS: %s" % ws_url)
	for a in agents:
		var action = agent_actions.get(a.agent_id, "-")
		lines.append("%s | action: %s" % [a.agent_id, action])
	ui_label.text = "\n".join(lines)

func check_goal() -> void:
	if ball == null:
		return
	if ball.position.x > goal_line:
		score_left += 1
		reset_round()
	elif ball.position.x < -goal_line:
		score_right += 1
		reset_round()

func reset_round() -> void:
	if ball != null:
		ball.linear_velocity = Vector3.ZERO
		ball.angular_velocity = Vector3.ZERO
		ball.position = Vector3(0, 0.5, 0)
	for a in agents:
		if a.has_method("reset_position"):
			a.reset_position()
	update_ui()

func get_ball() -> RigidBody3D:
	return ball

func get_own_goal_pos(side: String) -> Vector3:
	if side == "left":
		return Vector3(-goal_line, 0.5, 0)
	return Vector3(goal_line, 0.5, 0)

func get_opp_goal_pos(side: String) -> Vector3:
	if side == "left":
		return Vector3(goal_line, 0.5, 0)
	return Vector3(-goal_line, 0.5, 0)

func is_enemy_near(a) -> bool:
	for other in agents:
		if other == a:
			continue
		if other.position.distance_to(a.position) < 2.2:
			return true
	return false
