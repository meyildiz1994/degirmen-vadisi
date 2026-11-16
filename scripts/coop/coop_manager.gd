class_name CoopManager
extends Node
## İki kişilik yerel oyun (aynı ekran). 1. oyuncu klavye/fare, dokunmatik ya da kendi
## gamepad'i; 2. oyuncu duraklatma menüsünden "2. oyuncu katılsın" seçilince bir
## gamepad'de A'ya basarak katılır. Kamera ikisini birlikte kadrajlar, heybe ortaktır.
## Girişler PlayerInput ile ayrıldığından ileride çevrimiçi bir oyuncu da buraya
## (ağdan beslenen bir PlayerInput ile) eklenebilir.

signal joined(p2: Player)
signal left
signal waiting_changed(waiting: bool)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## 2. oyuncu: yosun yeşili tunik, ayçiçeği sarısı atkı.
const P2_TUNIC := Color(0.30, 0.60, 0.34)
const P2_SCARF := Color(0.98, 0.76, 0.28)
const WAIT_SECONDS := 30.0

var world: Node3D
var p1: Player
var p2: Player = null
var hud: CanvasLayer
var gather_world: GatherWorld
var waiting := false
var _wait_t := 0.0
var _guard := 0.0


func setup(w: Node3D, player: Player, h: CanvasLayer, gw: GatherWorld) -> void:
	world = w
	p1 = player
	hud = h
	gather_world = gw
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection)


func is_active() -> bool:
	return p2 != null


func players() -> Array[Player]:
	var out: Array[Player] = [p1]
	if p2 != null:
		out.append(p2)
	return out


## Menüden: bir sonraki gamepad "A" basışı 2. oyuncuyu katar.
func start_waiting() -> void:
	waiting = true
	_wait_t = WAIT_SECONDS
	_guard = 0.35   # menüyü kapatan A basışı sayılmasın
	waiting_changed.emit(true)


func cancel_waiting() -> void:
	if waiting:
		waiting = false
		waiting_changed.emit(false)


func _process(delta: float) -> void:
	_guard = maxf(_guard - delta, 0.0)
	if waiting and not get_tree().paused:
		_wait_t -= delta
		if _wait_t <= 0.0:
			cancel_waiting()


func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton) or not event.pressed:
		return
	if waiting and _guard <= 0.0 and event.button_index == JOY_BUTTON_A and not get_tree().paused:
		# İki gamepad varsa 1. oyuncunun kullandığı gamepad katılmaz.
		var pads := Input.get_connected_joypads()
		if pads.size() > 1 and InputManager.device == InputManager.Device.GAMEPAD and event.device == InputManager.last_pad:
			return
		join(event.device)
		get_viewport().set_input_as_handled()
	elif p2 != null and event.device == p2.pinput.pad and event.button_index == JOY_BUTTON_START:
		hud.set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func join(device: int) -> Player:
	if p2 != null:
		return p2
	cancel_waiting()
	InputManager.set_p2_pad(device)
	p2 = PLAYER_SCENE.instantiate() as Player
	p2.name = "Player2"
	p2.index = 1
	p2.pinput = PlayerInput.for_pad(device)
	p2.camera_owner = p1
	p2.respawn_point = p1.respawn_point
	(p2.get_node("CameraRig/Pitch/SpringArm3D/Camera3D") as Camera3D).current = false
	var model := p2.get_node("Model")
	model.tunic = P2_TUNIC
	model.scarf = P2_SCARF
	var side := Basis(Vector3.UP, p1.yaw) * Vector3(1.3, 0, 0.4)
	var pos := p1.global_position + side
	pos.y = ValleyShape.height(pos.x, pos.z) + 0.3
	p2.position = pos
	world.add_child(p2)
	p2.yaw = p1.yaw
	p2.model.rotation.y = p1.model.rotation.y
	p1.partner = p2
	p2.partner = p1
	var cur := world.get_viewport().get_camera_3d()
	if cur == null or cur == p2.camera:
		p1.camera.make_current()
	gather_world.add_player(p2)
	hud.add_player(p2)
	AudioManager.play_sfx("coop_join")
	joined.emit(p2)
	return p2


func leave() -> void:
	if p2 == null:
		return
	cancel_waiting()
	hud.remove_player(p2)
	gather_world.remove_player(p2)
	p1.partner = null
	p2.queue_free()
	p2 = null
	InputManager.set_p2_pad(-1)
	p1.camera.make_current()
	left.emit()


## 2. oyuncunun gamepad'i çıkarılırsa oyun ondan ayrılır (1. oyuncu devam eder).
func _on_joy_connection(device: int, connected: bool) -> void:
	if not connected and p2 != null and device == p2.pinput.pad:
		leave()
