extends Node
## Tek giriş sistemi, üç cihaz. Oyun mantığı yalnızca InputMap aksiyonlarını
## (move_*, look_*, interact, inventory, pause) ve bu düğümün vektörlerini bilir.
## Dokunmatik kontroller de aksiyonları basarak çalışır; cihaz farkı burada kalır.

signal device_changed(device: int)
signal touch_preview_changed(enabled: bool)

enum Device { KEYBOARD_MOUSE, GAMEPAD, TOUCH }

const GAMEPAD_AXIS_THRESHOLD := 0.35

@export var mouse_sensitivity := 0.0022   ## radyan / piksel
@export var touch_sensitivity := 0.0055   ## radyan / piksel (taban çözünürlükte)
@export var gamepad_look_speed := 2.4     ## radyan / saniye
@export var invert_y := false

var device: int = Device.KEYBOARD_MOUSE
var touch_preview := false   ## PC'de dokunmatik arayüzü fareyle denemek için (F2)
var _look_delta := Vector2.ZERO
var _stick := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameState.is_mobile or (DisplayServer.is_touchscreen_available() and OS.has_feature("web")):
		device = Device.TOUCH


func is_touch() -> bool:
	return device == Device.TOUCH


func _set_device(d: int) -> void:
	if d == device:
		return
	device = d
	if d != Device.KEYBOARD_MOUSE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	device_changed.emit(d)


func _input(event: InputEvent) -> void:
	# --- Hangi cihaz kullanılıyor? -------------------------------------------
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_device(Device.TOUCH)
	elif event is InputEventJoypadButton:
		_set_device(Device.GAMEPAD)
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > GAMEPAD_AXIS_THRESHOLD:
			_set_device(Device.GAMEPAD)
	elif event is InputEventKey or event is InputEventMouseButton:
		if not touch_preview:
			_set_device(Device.KEYBOARD_MOUSE)
	elif event is InputEventMouseMotion and not touch_preview:
		if event.relative.length() > 2.0 and device == Device.GAMEPAD:
			_set_device(Device.KEYBOARD_MOUSE)

	# --- Fareyle bakış (yalnızca fare yakalanmışken) ---------------------------
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_delta += event.relative * mouse_sensitivity

	if event.is_action_pressed("debug_quality"):
		GameState.cycle_quality()
	if event.is_action_pressed("debug_touch_preview"):
		set_touch_preview(not touch_preview)


func _unhandled_input(event: InputEvent) -> void:
	# Oyun alanına tıklayınca fareyi yakala (UI tıklamaları önce tüketilir).
	if device == Device.KEYBOARD_MOUSE and not touch_preview and not get_tree().paused:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all_virtual()


func set_touch_preview(enabled: bool) -> void:
	touch_preview = enabled
	Input.emulate_touch_from_mouse = enabled
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_device(Device.TOUCH)
	else:
		release_all_virtual()
		_set_device(Device.KEYBOARD_MOUSE)
	touch_preview_changed.emit(enabled)


func release_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Oyun mantığına açılan arayüz -----------------------------------------------
## -1..1 hareket vektörü (x: sağ, y: geri). Klavye, sol çubuk ve sanal joystick birleşik.
func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


## Bu karedeki bakış değişimi (radyan). Fare + dokunmatik sürükleme + sağ çubuk.
func consume_look(delta: float) -> Vector2:
	var look := _look_delta
	_look_delta = Vector2.ZERO
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	look += stick * gamepad_look_speed * delta
	if invert_y:
		look.y = -look.y
	return look


# --- Dokunmatik kontrollerin kullandığı yardımcılar ---------------------------------
func add_touch_look(relative: Vector2) -> void:
	_look_delta += relative * touch_sensitivity


## Sanal joystick, gamepad çubuğu gibi aksiyonlara güç değeriyle basar.
func set_virtual_stick(v: Vector2) -> void:
	_stick = v.limit_length(1.0)
	_press_strength("move_right", maxf(_stick.x, 0.0))
	_press_strength("move_left", maxf(-_stick.x, 0.0))
	_press_strength("move_back", maxf(_stick.y, 0.0))
	_press_strength("move_forward", maxf(-_stick.y, 0.0))


func _press_strength(action: String, strength: float) -> void:
	if strength > 0.02:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


## Dokunmatik buton → gerçek InputEventAction; oyun mantığı farkı görmez.
func press_action(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


func release_all_virtual() -> void:
	set_virtual_stick(Vector2.ZERO)


# --- Ekrandaki ipuçları ------------------------------------------------------------
## Aktif cihaza göre tuş ipucu: "E" / "A" / "" (dokunmatikte ikon çizilir).
func glyph_for(action: String) -> String:
	match device:
		Device.GAMEPAD:
			return {"interact": "A", "inventory": "Y", "pause": "Start"}.get(action, "?")
		Device.TOUCH:
			return ""
		_:
			return {"interact": "E", "inventory": "Tab", "pause": "Esc"}.get(action, "?")
