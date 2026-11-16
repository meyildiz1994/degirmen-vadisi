class_name PlayerInput
extends RefCounted
## Bir oyuncunun girişi. 1. oyuncu (pad < 0) tüm cihazları InputManager üzerinden okur
## (klavye/fare, dokunmatik ve ona ayrılan gamepad). 2. oyuncu yalnızca kendi gamepad'ini
## okur. Oyuncu kodu yalnızca bu arayüzü bilir; ileride çevrimiçi oyuncu için ağdan gelen
## girişi taşıyan bir alt sınıf aynı yere takılabilir.

const DEADZONE := 0.25
const INTERACT_BUTTON := JOY_BUTTON_A

var pad := -1


static func for_pad(device: int) -> PlayerInput:
	var p := PlayerInput.new()
	p.pad = device
	return p


func is_local_primary() -> bool:
	return pad < 0


## -1..1 hareket vektörü (x: sağ, y: geri).
func move_vector() -> Vector2:
	if pad < 0:
		return InputManager.get_move_vector()
	var v := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
	if v.length() < DEADZONE:
		v = Vector2.ZERO
	else:
		v = v.normalized() * inverse_lerp(DEADZONE, 1.0, minf(v.length(), 1.0))
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT):
		v.x -= 1.0
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT):
		v.x += 1.0
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP):
		v.y -= 1.0
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN):
		v.y += 1.0
	return v.limit_length(1.0)


## Kamera ortak: yalnızca 1. oyuncu çevirir.
func consume_look(delta: float) -> Vector2:
	if pad < 0:
		return InputManager.consume_look(delta)
	return Vector2.ZERO


func interact_held() -> bool:
	if pad < 0:
		return InputManager.is_interact_held()
	return Input.is_joy_button_pressed(pad, INTERACT_BUTTON)


## Bu olay bu oyuncunun "etkileşim" basışı mı?
func is_interact_event(event: InputEvent) -> bool:
	if pad < 0:
		return event.is_action_pressed("interact")
	return event is InputEventJoypadButton and event.device == pad and event.pressed \
		and event.button_index == INTERACT_BUTTON


func is_click_interact(event: InputEvent) -> bool:
	return pad < 0 and InputManager.is_click_interact(event)


func is_pointer_mode() -> bool:
	return pad < 0 and InputManager.is_pointer_mode()
