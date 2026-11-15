extends Control
## Dokunmatik kontroller: sol yarıda dinamik sanal joystick, sağ yarıda sürükleyerek kamera,
## sağ altta büyük "Etkileşim" butonu, üstte envanter ve duraklat butonları.
## Hepsi InputManager üzerinden aksiyon basar; oyun mantığı dokunmatiği bilmez.
## Çoklu dokunuş indeksleri tek tek takip edilir.

const STICK_RADIUS := 88.0
const KNOB_RADIUS := 40.0
const INTERACT_RADIUS := 80.0   ## 160 px çap (taban 720p) — 48 px sınırının çok üstünde
const SMALL_RADIUS := 40.0      ## 80 px çap

var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_index := -1
var _button_index := {}          ## dokunuş indeksi -> buton adı
var _pressed := {}               ## buton adı -> bool
var _margins := Vector4(16, 16, 16, 16)
var _has_focus := false
var _blob_cache := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	InputManager.device_changed.connect(func(_d): _update_visibility())
	get_viewport().size_changed.connect(_update_margins)
	_update_margins()
	_update_visibility()


func set_interact_available(available: bool) -> void:
	_has_focus = available
	queue_redraw()


func _update_margins() -> void:
	_margins = SafeArea.compute_margins(get_viewport())
	queue_redraw()


func _update_visibility() -> void:
	var show_touch := InputManager.is_touch()
	if visible and not show_touch:
		_release_all()
	visible = show_touch


# --- Yerleşim ------------------------------------------------------------------
func _interact_center() -> Vector2:
	return Vector2(size.x - _margins.z - INTERACT_RADIUS - 24.0, size.y - _margins.w - INTERACT_RADIUS - 24.0)

func _inventory_center() -> Vector2:
	return Vector2(_margins.x + SMALL_RADIUS + 12.0, _margins.y + SMALL_RADIUS + 8.0)

func _pause_center() -> Vector2:
	return _inventory_center() + Vector2(SMALL_RADIUS * 2.0 + 22.0, 0)

func _stick_rest() -> Vector2:
	return Vector2(_margins.x + STICK_RADIUS + 50.0, size.y - _margins.w - STICK_RADIUS - 40.0)


func _button_at(p: Vector2) -> String:
	if p.distance_to(_interact_center()) <= INTERACT_RADIUS + 14.0:
		return "interact"
	if p.distance_to(_inventory_center()) <= SMALL_RADIUS + 10.0:
		return "inventory"
	if p.distance_to(_pause_center()) <= SMALL_RADIUS + 10.0:
		return "pause"
	return ""


# --- Giriş -----------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var local := make_input_local(event) as InputEventScreenTouch
		if local.pressed:
			_on_touch_down(local.index, local.position)
		else:
			_on_touch_up(local.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var local := make_input_local(event) as InputEventScreenDrag
		if local.index == _stick_index:
			_stick_pos = local.position
			var v := (_stick_pos - _stick_origin) / STICK_RADIUS
			InputManager.set_virtual_stick(v.limit_length(1.0))
			queue_redraw()
		elif local.index == _look_index:
			InputManager.add_touch_look(local.relative)
		get_viewport().set_input_as_handled()


func _on_touch_down(index: int, p: Vector2) -> void:
	var b := _button_at(p)
	if b != "":
		_button_index[index] = b
		_pressed[b] = true
		InputManager.press_action(b, true)
		PlatformServices.vibrate(15)
	elif p.x < size.x * 0.5 and _stick_index == -1:
		_stick_index = index
		_stick_origin = p
		_stick_pos = p
	elif p.x >= size.x * 0.5 and _look_index == -1:
		_look_index = index
	queue_redraw()


func _on_touch_up(index: int) -> void:
	if _button_index.has(index):
		var b: String = _button_index[index]
		_button_index.erase(index)
		_pressed[b] = false
		InputManager.press_action(b, false)
	if index == _stick_index:
		_stick_index = -1
		InputManager.set_virtual_stick(Vector2.ZERO)
	if index == _look_index:
		_look_index = -1
	queue_redraw()


func _release_all() -> void:
	for i in _button_index.keys():
		_on_touch_up(i)
	_stick_index = -1
	_look_index = -1
	InputManager.set_virtual_stick(Vector2.ZERO)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_PAUSED:
		_release_all()


# --- Çizim (suluboya lekesi butonlar) -------------------------------------------------
func _blob_points(center: Vector2, radius: float, seed_value: int) -> PackedVector2Array:
	var key := "%d_%d" % [int(radius), seed_value]
	if not _blob_cache.has(key):
		var n := FastNoiseLite.new()
		n.seed = seed_value
		n.frequency = 0.9
		var pts := PackedVector2Array()
		for i in 40:
			var a := TAU * i / 40.0
			var r := radius * (1.0 + n.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0) * 0.12)
			pts.append(Vector2(cos(a), sin(a)) * r)
		_blob_cache[key] = pts
	var out := PackedVector2Array()
	for q in _blob_cache[key]:
		out.append(center + q)
	return out


func _draw_blob(center: Vector2, radius: float, fill: Color, seed_value: int) -> void:
	draw_colored_polygon(_blob_points(center + Vector2(3, 4), radius * 1.04, seed_value + 1), Color(Palette.EARTH, fill.a * 0.25))
	var pts := _blob_points(center, radius, seed_value)
	draw_colored_polygon(pts, fill)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(Palette.INK, 0.55 * fill.a + 0.2), 2.5, true)


func _draw_label(center: Vector2, key: String, font_size: int, alpha := 1.0) -> void:
	var font := get_theme_default_font()
	var text := tr(key)
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, center + Vector2(-ts.x * 0.5, font_size * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(Palette.INK, alpha))


func _draw() -> void:
	# Joystick
	var origin := _stick_origin if _stick_index != -1 else _stick_rest()
	var knob := _stick_pos if _stick_index != -1 else origin
	var off := (knob - origin).limit_length(STICK_RADIUS)
	var a := 0.75 if _stick_index != -1 else 0.35
	_draw_blob(origin, STICK_RADIUS, Color(Palette.PAPER, a), 11)
	_draw_blob(origin + off, KNOB_RADIUS, Color(Palette.SUNSET_LIGHT, a + 0.15), 12)
	# Etkileşim butonu
	var ic := _interact_center()
	var ia := 0.95 if _has_focus else 0.55
	var fill := Palette.SUNSET if _pressed.get("interact", false) else Palette.SUNSET_LIGHT
	_draw_blob(ic, INTERACT_RADIUS * (0.94 if _pressed.get("interact", false) else 1.0), Color(fill, ia), 21)
	_draw_label(ic, "TOUCH_INTERACT", 30, ia)
	# Envanter ve duraklat
	var inv := _inventory_center()
	_draw_blob(inv, SMALL_RADIUS, Color(Palette.PAPER, 0.85), 31)
	_draw_label(inv, "TOUCH_INVENTORY", 22)
	var pc := _pause_center()
	_draw_blob(pc, SMALL_RADIUS, Color(Palette.PAPER, 0.85), 41)
	draw_rect(Rect2(pc + Vector2(-10, -12), Vector2(7, 24)), Palette.INK)
	draw_rect(Rect2(pc + Vector2(3, -12), Vector2(7, 24)), Palette.INK)
