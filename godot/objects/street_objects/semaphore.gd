extends Node3D
class_name StreetSemaphore

signal on_change(status:int)

@export var is_master:bool = false
@export var is_parent:bool = false
@export var parentSemaphore:StreetSemaphore
@export var masterSemaphore:StreetSemaphore
@export var red_duration:float = 12.0
@export var yellow_duration:float = 4.0
@export var green_duration:float = 8.0

@onready var timer: Timer = $Timer
@onready var mesh: MeshInstance3D = $mesh

var status = 0 #0 red, 1 yellow 2 green
var _slave_transition_token:int = 0

func _ready() -> void:
	mesh.set_surface_override_material(1, mesh.get_surface_override_material(1).duplicate())
	mesh.set_surface_override_material(2, mesh.get_surface_override_material(2).duplicate())
	mesh.set_surface_override_material(3, mesh.get_surface_override_material(3).duplicate())
	
	mesh.get_surface_override_material(1).emission_enabled = false
	mesh.get_surface_override_material(2).emission_enabled = false
	mesh.get_surface_override_material(3).emission_enabled = false
	
	if is_master:
		print(name, " sono il master")
		if red_duration < (green_duration + yellow_duration):
			push_warning("%s: red_duration < green_duration + yellow_duration, gli slave potrebbero essere forzati a rosso prima del previsto." % name)
		if parentSemaphore == null:
			push_warning("%s: parentSemaphore non assegnato." % name)
		switch_status.call_deferred(0)
		timer.start(red_duration)
	elif !is_parent:
		timer.queue_free()
		print(name, " sono uno slave")
		if masterSemaphore == null:
			push_warning("%s: masterSemaphore non assegnato." % name)
		else:
			masterSemaphore.on_change.connect(on_status_master_change)
	else:
		timer.queue_free()
		print(name, " sono il fratello")

func updateColor():
	mesh.get_surface_override_material(1).emission_enabled = false
	mesh.get_surface_override_material(2).emission_enabled = false
	mesh.get_surface_override_material(3).emission_enabled = false
	if status == 0:
		mesh.get_surface_override_material(1).emission_enabled = true
	elif status == 1:
		mesh.get_surface_override_material(2).emission_enabled = true
	else:
		mesh.get_surface_override_material(3).emission_enabled = true

func switch_status(newStatus:int):
	status = newStatus
	if is_master:
		if parentSemaphore != null:
			parentSemaphore.switch_status(newStatus)
		on_change.emit(newStatus)
	updateColor()
	
func on_status_master_change(newstatus:int):
	_slave_transition_token += 1
	var token := _slave_transition_token

	if newstatus == 0:
		switch_status(2)
		await get_tree().create_timer(maxf(green_duration, 0.0)).timeout
		if token != _slave_transition_token:
			return
		switch_status(1)
	elif newstatus == 2:
		switch_status(0)

	

func _on_timer_timeout() -> void:
	if is_master:
		if status == 0:
			timer.start(green_duration)
			switch_status(2)
		elif status == 1:
			timer.start(red_duration)
			switch_status(0)
		else:
			timer.start(yellow_duration)
			switch_status(1)
