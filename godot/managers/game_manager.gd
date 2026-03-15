extends Node

const PALLA_SCENE = preload("uid://8udripon4lkl")

@onready var points_panel: Control = $"../GUIContainer/PointsPanel"
@onready var start_ball_position: Marker3D = $"../StartBallPosition"


var team1Points = 0
var team2Points = 0

@export_group("Field Bounds")
@export var out_bounds_x := 6.4
@export var out_bounds_z := 4.2
@export var out_bounds_min_y := -0.7
@export var out_bounds_max_y := 2.5

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	var ball := _get_ball()
	if ball == null:
		return
	if _is_ball_out_of_field(ball):
		resetBall(ball)

func onGoal(team):
	if team == 0:
		print("Team 2 ha fatto goal")
		team2Points+=1
	else:
		team1Points+=1
		print("Team 1 ha fatto goal")
	
	points_panel.update_points(team1Points, team2Points)

func resetGame():
	team1Points = 0
	team2Points = 0
	points_panel.update_points(team1Points, team2Points)
	var ball := _get_ball()
	if ball == null:
		var newPalla: Palla = PALLA_SCENE.instantiate()
		get_parent().add_child(newPalla)
		ball = newPalla
	resetBall(ball)
	_reset_players_positions()

func resetBall(ball:Palla):
	ball.freeze = true
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = start_ball_position.global_position
	ball.freeze = false

func _on_porta_goal_on_goal(team: int, palla:Palla) -> void:
	onGoal(team)
	resetBall(palla)
	_reset_players_positions()

func _on_porta_goal_2_on_goal(team: int, palla:Palla) -> void:
	onGoal(team)
	resetBall(palla)
	_reset_players_positions()

func _on_restart_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
	
func _on_d_button_on_pressed() -> void:
	
	var newPalla:Palla = PALLA_SCENE.instantiate()
	get_parent().add_child(newPalla)
	newPalla.global_position = start_ball_position.global_position
	newPalla.global_position.y = 2

func _get_ball() -> Palla:
	var parent := get_parent()
	if parent == null:
		return null
	var node := parent.get_node_or_null("Palla")
	if node is Palla:
		return node as Palla
	return null

func _reset_players_positions() -> void:
	for node in get_tree().get_nodes_in_group("soccer_test_players"):
		if node == null:
			continue
		if node.has_method("reset_to_initial_position"):
			node.call("reset_to_initial_position")

func _is_ball_out_of_field(ball: Palla) -> bool:
	var p := ball.global_position
	if absf(p.x) > out_bounds_x:
		return true
	if absf(p.z) > out_bounds_z:
		return true
	if p.y < out_bounds_min_y or p.y > out_bounds_max_y:
		return true
	return false
	
