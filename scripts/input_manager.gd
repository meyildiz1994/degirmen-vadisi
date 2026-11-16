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
var _dragging_look := false
## Oyuncu fareyle en az bir kez etrafa baktı mı (ipucu kartı için).
var mouse_looked := false
## İki kişilik oyunda 2. oyuncunun gamepad'i (-1: yok). Bu cihazın olayları 1. oyuncunun
## aksiyonlarına, cihaz algılamasına ve bakışına karışmaz.
var p2_pad := -1
## 1. oyuncunun en son kullandığı gamepad (katılma sırasında ayırt etmek için).
var last_pad := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameState.is_mobile or (DisplayServer.is_touchscreen_available() and OS.has_feature("web")):
		device = Device.TOUCH
	else:
		CursorArt.apply()


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
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and p2_pad >= 0 and event.device == p2_pad:
		return  # 2. oyuncunun gamepad'i: kendi PlayerInput'u okur
	if event is InputEventJoypadButton:
		last_pad = event.device
	# --- Hangi cihaz kullanılıyor? -------------------------------------------
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_device(Device.TOUCH)
	elif event is InputEventJoypadButton:
		_set_device(Device.GAMEPAD)
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > GAMEPAD_AXIS_THRESHOLD:
			_set_device(Device.GAMEPAD)
	elif event is InputEventKey or event is InputEventMouseButton:
		# Dokunmatikten türetilen fare olayları cihazı değiştirmesin
		if not touch_preview and event.device != InputEvent.DEVICE_ID_EMULATION:
			_set_device(Device.KEYBOARD_MOUSE)
	elif event is InputEventMouseMotion and not touch_preview:
		if event.relative.length() > 2.0 and device == Device.GAMEPAD:
			_set_device(Device.KEYBOARD_MOUSE)

	# --- Fareyle bakış: sağ tuş basılıyken sürükle (imleç serbest kalır) ---------
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_dragging_look = false
	if event is InputEventMouseMotion and (_dragging_look or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		_look_delta += event.relative * mouse_sensitivity
		if _dragging_look and event.relative.length() > 3.0:
			mouse_looked = true

	if event.is_action_pressed("debug_quality"):
		GameState.cycle_quality()
	if event.is_action_pressed("debug_touch_preview"):
		set_touch_preview(not touch_preview)


func _unhandled_input(event: InputEvent) -> void:
	# Oyun alanında sağ tuşa basınca bakış başlar (arayüz tıklamaları önce tüketilir).
	if is_pointer_mode() and not get_tree().paused:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging_look = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all_virtual()
		_dragging_look = false


## 2. oyuncuya bir gamepad ayır (-1: ayrılmış gamepad'i geri bırak). Oyun aksiyonlarındaki
## gamepad olayları 1. oyuncuya kalan gamepad'e bağlanır; menü (ui_*) aksiyonları ortak kalır.
func set_p2_pad(device: int) -> void:
	p2_pad = device
	var p1_pad := -1
	if device >= 0:
		p1_pad = 99  # 1. oyuncunun gamepad'i yoksa: hiçbir gerçek cihaz
		for d: int in Input.get_connected_joypads():
			if d != device:
				p1_pad = d
				break
	for action: StringName in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue
		var events := InputMap.action_get_events(action)
		var changed := false
		for ev: InputEvent in events:
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				ev.device = p1_pad
				changed = true
		if changed:
			InputMap.action_erase_events(action)
			for ev: InputEvent in events:
				InputMap.action_add_event(action, ev)
	if device >= 0 and device == last_pad:
		last_pad = -1
		if self.device == Device.GAMEPAD:
			_set_device(Device.TOUCH if GameState.is_mobile else Device.KEYBOARD_MOUSE)


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
	_dragging_look = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Oyun mantığına açılan arayüz -----------------------------------------------
## Klavye/fare: imleç serbest, sol tık imlecin altındaki şeyle etkileşir, sağ tuşla sürüklemek
## kamerayı çevirir. Dokunmatikten türetilen fare olayları ve dokunmatik önizleme sayılmaz,
## böylece telefonda her dokunuş etkileşim olmaz.
func is_pointer_mode() -> bool:
	return device == Device.KEYBOARD_MOUSE and not touch_preview


func is_click_interact(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
		and event.device != InputEvent.DEVICE_ID_EMULATION and is_pointer_mode()


## Etkileşim basılı mı (E / A / dokunmatik buton ya da sol tık).
func is_interact_held() -> bool:
	return Input.is_action_pressed("interact") or (is_pointer_mode() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))


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
			return {"interact": "A", "inventory": "Y", "pause": "Start", "quest_log": "↑"}.get(action, "?")
		Device.TOUCH:
			return ""
		_:
			return {"interact": "E", "inventory": "Tab", "pause": "Esc", "quest_log": "J"}.get(action, "?")


## Klavye/farede etkileşim ipucuna fare ikonu da eklensin mi (sol tık da çalışır).
func shows_mouse_hint(action: String) -> bool:
	return action == "interact" and device == Device.KEYBOARD_MOUSE and not touch_preview
