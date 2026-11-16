class_name Player
extends CharacterBody3D
## Üçüncü şahıs oyuncu: omuz arkası kamera, SpringArm3D ile duvara girmez.
## Girişi yalnızca InputManager'dan (soyut aksiyonlar) okur.

signal focus_changed(target: Interactable)
signal interacted_with(target: Interactable)
signal health_changed(health: int)
signal downed_changed(downed: bool)
signal attacked(target: Node3D)

const MAX_HEALTH := 5
const DOWNED_SECONDS := 9.0       ## yalnızken bu kadar sonra atölyede kendine gelir
const REVIVE_SECONDS := 2.2       ## arkadaş yanında durursa kalkış süresi
const REVIVE_RANGE := 2.4
const REGEN_DELAY := 6.0
const REGEN_EVERY := 3.5
const LEASH := 15.0               ## iki kişilikte oyuncular en fazla bu kadar uzaklaşır
const HAND_DAMAGE := 1.0

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
## Girişin kaynağı (1. oyuncu: tüm yerel cihazlar, 2. oyuncu: kendi gamepad'i).
var pinput := PlayerInput.new()
## 0: ana oyuncu (kamera, kayıt), 1: 2. oyuncu.
var index := 0
## İki kişilikte diğer oyuncu (kamera ikisini kadrajlar, ip mesafesi).
var partner: Player = null
## 2. oyuncu kamerayı 1. oyuncudan paylaşır.
var camera_owner: Player = null
var respawn_point := Vector3.INF
var health := MAX_HEALTH
var downed := false
var revive := 0.0                 ## 0..1 arkadaşın kaldırma ilerlemesi
var _downed_t := 0.0
var _since_hurt := 99.0
var _regen_t := 0.0
var _attack_cd := 0.0
var _knock := Vector3.ZERO
var _invuln := 0.0
var _focus_live := false


func _ready() -> void:
	add_to_group(&"players")
	if index == 0:
		add_to_group(SaveSystem.PERSIST_GROUP)
	else:
		camera.current = false
	camera_rig.top_level = true
	camera_rig.global_position = global_position + Vector3(0, 1.45, 0)
	spring_arm.add_excluded_object(get_rid())
	yaw = rotation.y
	rotation.y = 0.0
	model.rotation.y = yaw
	gather = GatherController.new()
	gather.name = "Gather"
	add_child(gather)


## Hedef (ör. vadiden çıkan sel ya da dağılan leke) yok olduysa bırak.
## (Silinmiş nesne null'a eşit görünebildiği için doğrudan geçerlilik bakılır.)
func _drop_freed_focus() -> void:
	if not is_instance_valid(focus):
		var had := _focus_live
		focus = null
		_focus_live = false
		if had:
			focus_changed.emit(null)
	else:
		_focus_live = true
	if not is_instance_valid(hovered):
		hovered = null


func _physics_process(delta: float) -> void:
	_drop_freed_focus()
	_update_camera_input(delta)
	_update_movement(delta)
	_update_focus()
	_update_combat(delta)


func _process(delta: float) -> void:
	_drop_freed_focus()
	var target := global_position + Vector3(0, 1.45, 0)
	var arm := 4.3
	if partner != null and index == 0:
		# İki kişilik: kamera ikisinin ortasına bakar, aradaki mesafe büyüdükçe geri çekilir.
		target = (global_position + partner.global_position) * 0.5 + Vector3(0, 1.45, 0)
		arm = clampf(4.3 + global_position.distance_to(partner.global_position) * 0.55, 4.3, 12.0)
	spring_arm.spring_length = lerpf(spring_arm.spring_length, arm, clampf(delta * 3.0, 0.0, 1.0))
	camera_rig.global_position = camera_rig.global_position.lerp(target, clampf(delta * camera_follow_speed, 0.0, 1.0))
	_animate(delta)


func _update_camera_input(delta: float) -> void:
	if camera_owner != null:
		yaw = camera_owner.yaw  # hareket yönü ortak kameraya göre
		return
	if not input_enabled:
		return
	var look := pinput.consume_look(delta)
	yaw -= look.x
	pitch = clampf(pitch - look.y, pitch_min, pitch_max)
	camera_rig.rotation = Vector3(0, yaw, 0)
	pitch_pivot.rotation = Vector3(pitch, 0, 0)


func _update_movement(delta: float) -> void:
	var input := pinput.move_vector() if input_enabled and not downed else Vector2.ZERO
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	if partner != null and not partner.downed:
		# İp: arkadaştan fazla uzaklaşan yön kesilir (ikisi de ekranda kalsın).
		var away := global_position - partner.global_position
		away.y = 0.0
		if away.length() > LEASH and dir.dot(away) > 0.0:
			dir -= away.normalized() * dir.dot(away.normalized())
	var target := dir * walk_speed + _knock
	_knock = _knock.move_toward(Vector3.ZERO, delta * 14.0)
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
	model.rotation.x = lerpf(model.rotation.x, -1.3 if downed else 0.0, clampf(delta * 8.0, 0.0, 1.0))
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
	if downed:
		if focus != null:
			focus = null
			focus_changed.emit(null)
		return
	hovered = _hovered_target() if pinput.is_pointer_mode() and input_enabled else null
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
	if not input_enabled or downed:
		return
	var click := pinput.is_click_interact(event)
	if not pinput.is_interact_event(event) and not click:
		return
	# Fareyle: oturum sürerken her tık vuruştur; yoksa yalnızca imlecin altındaki hedef.
	var target := focus
	if click and not gather.active():
		if hovered == null:
			return
		target = hovered
	if target is ValleyEnemy and not gather.active():
		try_attack(target as ValleyEnemy)
	elif gather.active():
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
	elif focus is ValleyEnemy:
		t = best_weapon()
	elif focus is Gatherable and not (focus as Gatherable).is_hand():
		var g := focus as Gatherable
		t = GameState.inventory.best_tool(g.tool_kind(), g.resource_id)
	if t == null:
		model.set_held_tool("")
	else:
		model.set_held_tool(t.kind, t.head, ItemMemory.wear_level(t))


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


# --- Mücadele: vuruş, can, sersemleme ------------------------------------------------------
## En güçlü alet silah olur (balta ya da kazma); alet yoksa yumrukla (zayıf).
func best_weapon() -> ToolItem:
	var best: ToolItem = null
	for t: ToolItem in GameState.inventory.tools:
		if best == null or t.effective_power() > best.effective_power():
			best = t
	return best


static func weapon_damage(t: ToolItem) -> float:
	return HAND_DAMAGE if t == null else 1.0 + t.effective_power() * 0.25


func try_attack(blot: ValleyEnemy) -> bool:
	if _attack_cd > 0.0 or downed or not is_instance_valid(blot) or not blot.alive():
		return false
	var t := best_weapon()
	_attack_cd = (t.swing_time() if t != null else 0.42) + 0.1
	face_towards(blot.global_position)
	play_swing(false)
	if t != null:
		t.wear(1)
		GameState.inventory.notify_tool_changed()
	blot.take_hit(weapon_damage(t), self)
	attacked.emit(blot)
	return true


func take_damage(amount: int, from: Vector3) -> void:
	if downed or _invuln > 0.0 or amount <= 0:
		return
	health = maxi(health - amount, 0)
	_since_hurt = 0.0
	_invuln = 0.6
	var away := global_position - from
	away.y = 0.0
	_knock = away.normalized() * 5.0 if away.length() > 0.01 else Vector3.ZERO
	model.hurt()
	AudioManager.play_sfx_3d("player_hurt", global_position)
	if index == 0 or camera_owner == null:
		_impact = 0.16
	PlatformServices.vibrate(60)
	gather.stop()
	health_changed.emit(health)
	if health <= 0:
		_set_downed(true)


func _set_downed(v: bool) -> void:
	if downed == v:
		return
	downed = v
	revive = 0.0
	_downed_t = 0.0
	if v:
		gather.stop()
	else:
		health = MAX_HEALTH
		_invuln = 2.0
		health_changed.emit(health)
	downed_changed.emit(v)


func _update_combat(delta: float) -> void:
	_drop_freed_focus()
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_invuln = maxf(_invuln - delta, 0.0)
	if downed:
		_downed_t += delta
		var helper := partner != null and not partner.downed \
			and partner.global_position.distance_to(global_position) < REVIVE_RANGE
		if helper:
			revive = minf(revive + delta / REVIVE_SECONDS, 1.0)
			if revive >= 1.0:
				_set_downed(false)
				health = 3
				health_changed.emit(health)
				return
		else:
			revive = maxf(revive - delta * 0.5, 0.0)
		if _downed_t >= DOWNED_SECONDS:
			_wake_at_home()
		return
	# Basılı tutunca leke dövülmeye devam eder (dokunmatikte rahat).
	if focus is ValleyEnemy and input_enabled and pinput.interact_held() and not gather.active():
		try_attack(focus as ValleyEnemy)
	_since_hurt += delta
	if health < MAX_HEALTH and _since_hurt > REGEN_DELAY:
		_regen_t += delta
		if _regen_t >= REGEN_EVERY:
			_regen_t = 0.0
			health += 1
			health_changed.emit(health)


## Yalnız kalınca ya da kimse kaldırmazsa: atölyenin önünde kendine gelir.
func _wake_at_home() -> void:
	if respawn_point != Vector3.INF:
		var off := Vector3(0.9 * index, 0, 0)
		global_position = respawn_point + off
		velocity = Vector3.ZERO
		if index == 0:
			camera_rig.global_position = global_position + Vector3(0, 1.45, 0)
	_set_downed(false)


func heal_full() -> void:
	health = MAX_HEALTH
	health_changed.emit(health)


# --- Kayıt (SaveSystem 'persist' grubu) ------------------------------------------------
func save_state(data: Dictionary) -> void:
	if index != 0:
		return
	data["player"] = {"x": global_position.x, "y": global_position.y, "z": global_position.z, "yaw": yaw}


func load_state(data: Dictionary) -> void:
	if index != 0:
		return
	var p: Dictionary = data.get("player", {})
	if p.has("x"):
		global_position = Vector3(p.x, p.y + 0.2, p.z)
		yaw = float(p.get("yaw", yaw))
		camera_rig.global_position = global_position + Vector3(0, 1.45, 0)
