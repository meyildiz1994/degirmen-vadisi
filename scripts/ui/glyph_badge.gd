class_name GlyphBadge
extends Control
## Aktif cihaza göre değişen tuş ipucu: "E" (klavye), "A" (gamepad), dokunma ikonu.

@export var action := "interact"

var _text := ""


func _ready() -> void:
	custom_minimum_size = Vector2(52, 52)
	InputManager.device_changed.connect(func(_d): refresh())
	refresh()


func refresh() -> void:
	_text = InputManager.glyph_for(action)
	custom_minimum_size.x = maxf(52.0, 30.0 + _text.length() * 14.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var ink := Palette.INK
	if InputManager.device == InputManager.Device.TOUCH:
		# Dokunma ikonu: iç içe halkalar + nokta
		draw_circle(c, 22.0, Color(Palette.SUNSET_LIGHT, 0.9))
		draw_arc(c, 18.0, 0.0, TAU, 28, Color(ink, 0.8), 2.5, true)
		draw_arc(c, 11.0, 0.0, TAU, 20, Color(ink, 0.5), 2.0, true)
		draw_circle(c, 5.0, ink)
		return
	var gamepad := InputManager.device == InputManager.Device.GAMEPAD
	var fill := Palette.MOSS_LIGHT if gamepad else Palette.SUNSET_LIGHT
	var r := Rect2(Vector2(2, 4), size - Vector2(4, 8))
	if gamepad:
		draw_circle(c, 22.0, fill)
		draw_arc(c, 22.0, 0.0, TAU, 32, Color(ink, 0.8), 2.5, true)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = Color(ink, 0.8)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		draw_style_box(sb, r)
	var font := get_theme_default_font()
	var fs := 26
	var ts := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.32), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
