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
## Fare imlecinin altındaki hedef (yalnızca klavye/fare ile).
var hovered: Interactable = null
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
	else:
		model.end_session()
	_update_held()
	_update_impact_shake(delta)
	var bob := sin(_walk_phase * 2.0) * 0.045 * clampf(speed / walk_speed, 0.0, 1.0)
	model.position.y = bob
	model.rotation.z = sin(_walk_phase) * 0.04 * clampf(speed / walk_speed, 0.0, 1.0)


## Menzildeki en yakın etkileşim noktasını otomatik hedefle. Fare imleci menzildeki
## bir hedefin üstündeyse o hedef öncelikli (sol tıkla etkileşilir).
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
	hovered = _hovered_target() if InputManager.is_pointer_mode() and input_enabled else null
	if hovered != null:
		best = hovered
	if best != focus:
		focus = best
		focus_changed.emit(focus)


const HOVER_PX := 80.0   ## 720p'de imlecin hedefe en fazla bu kadar piksel uzak olması


func _hovered_target() -> Interactable:
	var vp := get_viewport()
	var mouse := vp.get_mouse_position()
	var limit := HOVER_PX * vp.get_visible_rect().size.y / 720.0
	var best: Interactable = null
	var best_d := limit
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var it := node as Interactable
		if not it.can_focus() or it.global_position.distance_to(global_position) >= it.radius:
			continue
		var p := it.global_position + Vector3(0, 0.4, 0)
		if camera.is_position_behind(p):
			continue
		var d := camera.unproject_position(p).distance_to(mouse)
		if d < best_d:
			best = it
			best_d = d
	return best


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	var click := InputManager.is_click_interact(event)
	if not event.is_action_pressed("interact") and not click:
		return
	# Fareyle: oturum sürerken her tık vuruştur; yoksa yalnızca imlecin altındaki hedef.
	var target := focus
	if click and not gather.active():
		if hovered == null:
			return
		target = hovered
	if gather.active():
		gather.on_interact_pressed(gather.target)
	elif target is Gatherable:
		gather.on_interact_pressed(target as Gatherable)
	elif target != null:
		target.interact(self)
		interacted_with.emit(target)
	else:
		return
	get_viewport().set_input_as_handled()


# --- Toplama animasyonu kancaları (GatherController çağırır) --------------------------
## Elde ne var: oturumdaki alet, yoksa odaktaki kaynağın istediği en iyi alet.
## Böylece oyuncu bir ağaca yaklaşınca baltasını eline alır ("baltam var" görünür).
func _update_held() -> void:
	var t: ToolItem = null
	if gather.active():
		t = gather.tool
	elif focus is Gatherable and not (focus as Gatherable).is_hand():
		var g := focus as Gatherable
		t = GameState.inventory.best_tool(g.tool_kind(), g.resource_id)
	if t == null:
		model.set_held_tool("")
	else:
		model.set_held_tool(t.kind, t.head)


func set_held_tool(_kind: String) -> void:
	_update_held()


func play_swing(sweet := false) -> void:
	model.strike(sweet)
	_impact = 0.16 if sweet else 0.11


var _impact := 0.0


## Darbe anında kamerada çok kısa, küçük bir sarsıntı (rahatsız etmeyecek kadar).
func _update_impact_shake(delta: float) -> void:
	if _impact <= 0.0:
		return
	_impact = maxf(_impact - delta, 0.0)
	var k := _impact / 0.16
	camera.h_offset = sin(_impact * 170.0) * 0.035 * k
	camera.v_offset = cos(_impact * 130.0) * 0.03 * k
	if _impact <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


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
