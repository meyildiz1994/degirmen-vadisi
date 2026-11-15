extends Button
## Görev ikonu: suluboya lekesi üzerinde kâğıt rulo. Okunmamış görev varsa
## köşede nabız gibi atan "!" bildirim rozeti çıkar.

var has_new := false:
	set(v):
		has_new = v
		queue_redraw()

var _t := 0.0


func _ready() -> void:
	add_to_group(&"touch_ui")
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(68, 68)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)


func _process(delta: float) -> void:
	if has_new:
		_t += delta
		queue_redraw()


func _blob(center: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		var rr := r * (1.0 + 0.06 * sin(a * 3.0 + 1.3) + 0.04 * sin(a * 7.0))
		pts.append(center + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(Palette.INK, 0.6), 2.0, true)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	var hover := is_hovered() or button_pressed
	_blob(c + Vector2(3, 4), r, Color(Palette.EARTH, 0.22))
	_blob(c, r * (0.95 if is_pressed() else 1.0), Color(Palette.SUNSET_LIGHT if hover else Palette.PAPER, 0.95))
	# Kâğıt rulo (görev parşömeni)
	var w := r * 0.9
	var h := r * 1.05
	var body := Rect2(c - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	draw_rect(body, Palette.PAPER.lerp(Palette.SAND, 0.35))
	draw_rect(body, Color(Palette.INK, 0.8), false, 2.0)
	for y in [body.position.y, body.end.y]:
		var rr := Rect2(Vector2(body.position.x - 4, y - 4), Vector2(w + 8, 8))
		draw_rect(rr, Palette.WOOD)
		draw_rect(rr, Color(Palette.INK, 0.8), false, 1.5)
	for i in 3:
		var y := body.position.y + h * (0.3 + i * 0.2)
		draw_line(Vector2(body.position.x + 6, y), Vector2(body.end.x - (6 if i < 2 else 14), y), Color(Palette.INK, 0.55), 2.0)
	if has_new:
		var pulse := 1.0 + 0.12 * sin(_t * 5.0)
		var bc := c + Vector2(r * 0.72, -r * 0.72)
		draw_circle(bc, 13.0 * pulse, Palette.SCARF)
		draw_arc(bc, 13.0 * pulse, 0.0, TAU, 24, Color(Palette.PAPER, 0.9), 2.0, true)
		var font := get_theme_default_font()
		draw_string(font, bc + Vector2(-3.5, 7), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Palette.PAPER)
