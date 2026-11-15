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
var gather: GatherController
var _walk_phase := 0.0
var _face_target := Vector3.INF


func _ready() -> void:
	add_to_group(SaveSystem.PERSIST_GROUP)
	camera_rig.top_level = true
	camera_rig.global_position = global_position + Vector3(0, 1.45, 0)
	spring_arm.add_excluded_object(get_rid())
	yaw = rotation.y
	rotation.y = 0.0
	model.rotation.y = yaw
	gather = GatherController.new()
	gather.name = "Gather"
	add_child(gather)


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
	elif _face_target != Vector3.INF:
		var to := _face_target - global_position
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-to.x, -to.z), clampf(turn_speed * delta, 0.0, 1.0))
	_face_target = Vector3.INF


func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var before := _walk_phase
	_walk_phase += delta * speed * 2.6
	if is_on_floor() and speed > 0.8 and floori(before / PI) != floori(_walk_phase / PI):
		_footstep()
	if gather.active():
		model.set_windup(gather.ring_phase())
	var bob := sin(_walk_phase * 2.0) * 0.045 * clampf(speed / walk_speed, 0.0, 1.0)
	model.position.y = bob
	model.rotation.z = sin(_walk_phase) * 0.04 * clampf(speed / walk_speed, 0.0, 1.0)


## Menzildeki en yakın etkileşim noktasını otomatik hedefle. Fareyle nişan alırken
## ekranın ortasındaki imlece en yakın açıdaki hedef öncelikli (yoksa yine en yakını).
func _update_focus() -> void:
	var best: Interactable = null
	var best_d := INF
	if gather.active():
		# Oturum sürerken hedef sabit kalır.
		if focus != gather.target:
			focus = gather.target
			focus_changed.emit(focus)
		return
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var it := node as Interactable
		if not it.can_focus():
			continue
		var d := it.global_position.distance_to(global_position)
		if d < it.radius and d + it.focus_bias < best_d:
			best = it
			best_d = d + it.focus_bias
	if InputManager.is_aiming():
		var aimed := _aimed_target()
		if aimed != null:
			best = aimed
	if best != focus:
		focus = best
		focus_changed.emit(focus)


const AIM_MAX_ANGLE := 0.32   ## radyan; imlecin bu kadar yakınındaki hedef seçilir


func _aimed_target() -> Interactable:
	var origin := camera.global_position
	var fwd := -camera.global_basis.z
	var best: Interactable = null
	var best_a := AIM_MAX_ANGLE
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var it := node as Interactable
		if not it.can_focus() or it.global_position.distance_to(global_position) >= it.radius:
			continue
		var a := fwd.angle_to(it.global_position + Vector3(0, 0.4, 0) - origin)
		if a < best_a:
			best = it
			best_a = a
	return best


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if not event.is_action_pressed("interact") and not InputManager.is_click_interact(event):
		return
	if gather.active():
		gather.on_interact_pressed(gather.target)
	elif focus is Gatherable:
		gather.on_interact_pressed(focus as Gatherable)
	elif focus != null:
		focus.interact(self)
		interacted_with.emit(focus)
	else:
		return
	get_viewport().set_input_as_handled()


# --- Toplama animasyonu kancaları (GatherController çağırır) --------------------------
func set_held_tool(kind: String) -> void:
	model.set_held_tool(kind)


func play_swing() -> void:
	model.strike()


func play_pickup() -> void:
	model.pickup()


func face_towards(world_pos: Vector3) -> void:
	_face_target = world_pos


# --- Ayak sesleri: zemine göre çimen / taş / tahta ----------------------------------------
func _footstep() -> void:
	AudioManager.play_sfx_3d("footstep_" + surface_under(), global_position, -6.0)


func surface_under() -> String:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.4, 0), global_position + Vector3(0, -0.6, 0), 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return "grass"
	var col: Object = hit["collider"]
	if col.has_meta("surface"):
		return str(col.get_meta("surface"))
	# Arazi: dere kıyısındaki çakıllık ve dik yamaçlar taş, gerisi çimen.
	var p := global_position
	if ValleyShape.carve_weight(p.x, p.z) > 0.35 or (hit["normal"] as Vector3).y < 0.8:
		return "stone"
	return "grass"


# --- Kayıt (SaveSystem 'persist' grubu) ------------------------------------------------
func save_state(data: Dictionary) -> void:
	data["player"] = {"x": global_position.x, "y": global_position.y, "z": global_position.z, "yaw": yaw}


func load_state(data: Dictionary) -> void:
	var p: Dictionary = data.get("player", {})
	if p.has("x"):
		global_position = Vector3(p.x, p.y + 0.2, p.z)
		yaw = float(p.get("yaw", yaw))
		camera_rig.global_position = global_position + Vector3(0, 1.45, 0)
