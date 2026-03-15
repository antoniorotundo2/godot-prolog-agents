extends Control

@onready var points_team_1: Label = $Panel/PointsTeam1
@onready var points_team_2: Label = $Panel/PointsTeam2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	points_team_1.text = "0"
	points_team_2.text = "0"


func update_points(team1Points:int, team2Points:int ):
	points_team_1.text = str(team1Points)
	points_team_2.text = str(team2Points)
