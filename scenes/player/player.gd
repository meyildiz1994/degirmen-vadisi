class_name Player
extends CharacterBody3D
## Üçüncü şahıs oyuncu: omuz arkası kamera, SpringArm3D ile duvara girmez.
## Girişi yalnızca InputManager'dan (soyut aksiyonlar) okur.

signal focus_changed(target: Interactable)
signal interacted_with(target: Interactable)

@export var walk_speed := 4.3
@export var acceleration := 11.0
@export var deceleration := 14.0
@export var turn_speed := 11.0
@export var gravity := 20.0
@export var pitch_min := -1.05
@export var pitch_max := 0.42
@export var camera_follow_speed := 14.0

@onready var camera_rig: Node3D = $CameraRig
@onready var pitch_pivot: Node3D = $CameraRig/Pitch
@onready var spring_arm: SpringArm3D = $CameraRig/Pitch/SpringArm3D
@onready var camera: Camera3D = $CameraRig/Pitch/SpringArm3D/Camera3D
@onready var model: Node3D = $Model

var yaw := 0.0
var pitch := -0.28
var focus: Interactable = null
var input_enabled := true
var _walk_phase := 0.0


func _ready() -> void:
	add_to_group(SaveSystem.PERSIST_GROUP)
	camera_rig.top_level = true
	camera_rig.global_position = global_position + Vector3(0, 1.45, 0)
	spring_arm.add_excluded_object(get_rid())
	yaw = rotation.y
	rotation.y = 0.0
	model.rotation.y = yaw


func _physics_process(delta: float) -> void:
	_update_camera_input(delta)
	_update_movement(delta)
	_update_focus()


func _process(delta: float) -> void:
	var target := global_position + Vector3(0, 1.45, 0)
	camera_rig.global_position = camera_rig.global_position.lerp(target, clampf(delta * camera_follow_speed, 0.0, 1.0))
	_animate(delta)


func _update_camera_input(delta: float) -> void:
	if not input_enabled:
		return
	var look := InputManager.consume_look(delta)
	yaw -= look.x
	pitch = clampf(pitch - look.y, pitch_min, pitch_max)
	camera_rig.rotation = Vector3(0, yaw, 0)
	pitch_pivot.rotation = Vector3(pitch, 0, 0)


func _update_movement(delta: float) -> void:
	var input := InputManager.get_move_vector() if input_enabled else Vector2.ZERO
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * walk_speed
	var hv := Vector3(velocity.x, 0, velocity.z)
	var rate := acceleration if target.length() > hv.length() else deceleration
	hv = hv.move_toward(target, rate * delta * walk_speed)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	if dir.length() > 0.05:
		var face := atan2(-dir.x, -dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, face, clampf(turn_speed * delta, 0.0, 1.0))


func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk_phase += delta * speed * 2.6
	var bob := sin(_walk_phase * 2.0) * 0.045 * clampf(speed / walk_speed, 0.0, 1.0)
	model.position.y = bob
	model.rotation.z = sin(_walk_phase) * 0.04 * clampf(speed / walk_speed, 0.0, 1.0)


## Menzildeki en yakın etkileşim noktasını otomatik hedefle.
func _update_focus() -> void:
	var best: Interactable = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var it := node as Interactable
		var d := it.global_position.distance_to(global_position)
		if d < it.radius and d < best_d:
			best = it
			best_d = d
	if best != focus:
		focus = best
		focus_changed.emit(focus)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("interact") and focus != null:
		focus.interact(self)
		interacted_with.emit(focus)
		get_viewport().set_input_as_handled()


# --- Kayıt (SaveSystem 'persist' grubu) ------------------------------------------------
func save_state(data: Dictionary) -> void:
	data["player"] = {"x": global_position.x, "y": global_position.y, "z": global_position.z, "yaw": yaw}


func load_state(data: Dictionary) -> void:
	var p: Dictionary = data.get("player", {})
	if p.has("x"):
		global_position = Vector3(p.x, p.y + 0.2, p.z)
		yaw = float(p.get("yaw", yaw))
		camera_rig.global_position = global_position + Vector3(0, 1.45, 0)
