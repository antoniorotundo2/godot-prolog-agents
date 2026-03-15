extends Control


const TEST_SIMPLE_AGENTS = preload("res://scenes/test_simple_agents.tscn")
const SOCCER_MAIN = preload("uid://bsboc2vy02xew")
const VEHICLE_TEST = preload("uid://b57mq8ckselat")
const SOCCER_TEST = preload("uid://8hmu0wgqrawq")
const TOP_DOWN_SCENE = preload("uid://cpgk5hbov1c3g")

func _on_button_pressed() -> void:
	get_tree().change_scene_to_packed(TEST_SIMPLE_AGENTS)


func _on_button_2_pressed() -> void:
	get_tree().change_scene_to_packed(SOCCER_TEST)


func _on_button_3_pressed() -> void:
	get_tree().change_scene_to_packed(VEHICLE_TEST)


func _on_button_4_pressed() -> void:
	get_tree().change_scene_to_packed(TOP_DOWN_SCENE)
