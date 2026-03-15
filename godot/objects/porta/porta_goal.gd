extends Node3D
class_name PortaGoal

signal on_goal(team:int, ball:Palla)

@export_enum("Squadra 1", "Squadra 2") var team: int

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body is Palla:
		on_goal.emit(team, body)
