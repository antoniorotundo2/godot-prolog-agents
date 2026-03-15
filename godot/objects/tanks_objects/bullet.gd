extends Area3D

@export var speed := 22.0
@export var life_seconds := 2.0
@export var damage := 24.0

var direction := Vector3.ZERO
var shooter_team := -1
var shooter_node: Node = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	await get_tree().create_timer(life_seconds).timeout
	queue_free()

func _physics_process(delta: float) -> void:
	if direction.length_squared() <= 0.0001:
		return
	global_position += direction.normalized() * speed * delta

func _on_body_entered(body: Node) -> void:
	if body == shooter_node:
		return
	if body.has_method("receive_bullet_hit"):
		body.call("receive_bullet_hit", damage, shooter_team, shooter_node)
	queue_free()
