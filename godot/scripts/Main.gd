extends Node3D

const TestAgentSceneA = preload("res://scenes/TestAgentA.tscn")
const TestAgentSceneB = preload("res://scenes/TestAgentB.tscn")

var agents: Array = []
var agent_actions := {}
var agent_logic := {}
var agent_counter := 0
var ws_url := "ws://127.0.0.1:8080/ws"


@onready var ui_label: Label = $UI/InfoLabel
@onready var ws_url_field: LineEdit = $UI/WsUrl
@onready var spawn_a_button: Button = $UI/SpawnAButton
@onready var spawn_b_button: Button = $UI/SpawnBButton

func _ready() -> void:
	ws_url_field.text = ws_url
	ws_url_field.text_submitted.connect(_on_ws_url_entered)
	ws_url_field.focus_exited.connect(_on_ws_url_focus_exited)
	spawn_a_button.pressed.connect(_on_spawn_a_pressed)
	spawn_b_button.pressed.connect(_on_spawn_b_pressed)

	spawn_agent(TestAgentSceneA)
	spawn_agent(TestAgentSceneB)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		spawn_agent(TestAgentSceneA)

func _on_spawn_a_pressed() -> void:
	spawn_agent(TestAgentSceneA)

func _on_spawn_b_pressed() -> void:
	spawn_agent(TestAgentSceneB)

func _on_ws_url_entered(text: String) -> void:
	apply_ws_url(text)

func _on_ws_url_focus_exited() -> void:
	apply_ws_url(ws_url_field.text)

func apply_ws_url(text: String) -> void:
	if text == "" or text == ws_url:
		return
	ws_url = text
	_prune_dead_agents()
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
	var logic_id = "-"
	if a.has_method("get_logic_id"):
		logic_id = a.get_logic_id()
	agent_logic[id] = logic_id
	update_ui()

func _on_agent_action(agent_id: String, action: String) -> void:
	agent_actions[agent_id] = action
	update_ui()

func update_ui() -> void:
	_prune_dead_agents()
	var lines: Array[String] = []
	lines.append("Agents: %d (Space/Enter -> Logic A)" % agents.size())
	lines.append("WS: %s" % ws_url)
	for a in agents:
		if not is_instance_valid(a):
			continue
		var action = agent_actions.get(a.agent_id, "-")
		var energy = int(a.get_energy())
		var logic_id = agent_logic.get(a.agent_id, "-")
		var hp_text := "-"
		if a.has_method("get_hp"):
			hp_text = str(int(a.get_hp()))
		lines.append(
			"%s | logic: %s | action: %s | hp: %s | energy: %d" %
			[a.agent_id, logic_id, action, hp_text, energy]
		)
	ui_label.text = "\n".join(lines)

func is_enemy_near(a) -> bool:
	_prune_dead_agents()
	for other in agents:
		if not is_instance_valid(other):
			continue
		if other == a:
			continue
		if other.position.distance_to(a.position) < 1.5:
			return true
	return false

func _prune_dead_agents() -> void:
	var alive: Array = []
	var alive_ids := {}
	for a in agents:
		if not is_instance_valid(a):
			continue
		alive.append(a)
		alive_ids[a.agent_id] = true
	agents = alive

	for id in agent_actions.keys():
		if not alive_ids.has(id):
			agent_actions.erase(id)
	for id in agent_logic.keys():
		if not alive_ids.has(id):
			agent_logic.erase(id)


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
