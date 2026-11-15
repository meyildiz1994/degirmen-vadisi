@tool
class_name ItemIcon
extends Control
## Metinsiz ipuçları ve heybe için kodla çizilen suluboya ikonlar.
## icon: malzeme/tohum kimliği (oak, stone, acorn...) ya da özel ikon
## (axe, pickaxe, workshop, tree, rock, hand, arrow, plus, check, seed).
## Cihaza göre değişen kontrol ikonları: move, look, interact, inventory
## (klavye/fare, gamepad ya da dokunmatik hangisi kullanılıyorsa onu çizer).

@export var icon := "stone":
	set(v):
		icon = v
		queue_redraw()
@export var tint := Color.WHITE:
	set(v):
		tint = v
		queue_redraw()
@export var dimmed := false:
	set(v):
		dimmed = v
		queue_redraw()

const INK := Color(0.30, 0.20, 0.14)


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(56, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	if not Engine.is_editor_hint():
		InputManager.device_changed.connect(func(_d): queue_redraw())


func _shape() -> String:
	if Engine.is_editor_hint():
		return icon
	if ":" in icon:  # parça: "beam:oak" → kalıbın şekli, malzemenin rengi
		return str(Crafting.mold(icon.get_slice(":", 0)).get("icon", "lump"))
	if Materials.is_material(icon) or Materials.is_seed(icon):
		return Materials.icon(icon)
	return icon


func _color() -> Color:
	if not Engine.is_editor_hint() and ":" in icon:
		return Materials.color(icon.get_slice(":", 1)) * tint
	if not Engine.is_editor_hint() and (Materials.is_material(icon) or Materials.is_seed(icon)):
		return Materials.color(icon) * tint
	return tint


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var k := s / 56.0
	var a := 0.45 if dimmed else 1.0
	var col := _color()
	col.a *= a
	var ink := Color(INK, 0.85 * a)
	if not Engine.is_editor_hint() and icon in ["move", "look", "interact", "inventory"]:
		_control_icon(c, k, ink, a)
		return
	match _shape():
		"arrow":
			_arrow(c, k, ink)
			return
		"plus":
			draw_line(c - Vector2(10, 0) * k, c + Vector2(10, 0) * k, ink, 4.0 * k)
			draw_line(c - Vector2(0, 10) * k, c + Vector2(0, 10) * k, ink, 4.0 * k)
			return
		"check":
			draw_polyline(PackedVector2Array([c + Vector2(-12, 0) * k, c + Vector2(-3, 9) * k, c + Vector2(13, -10) * k]), Color(Palette.MOSS_DARK, a), 5.0 * k, true)
			return
		"crack":
			var zig := PackedVector2Array([c + Vector2(-4, -16) * k, c + Vector2(3, -6) * k, c + Vector2(-5, 2) * k, c + Vector2(4, 9) * k, c + Vector2(-1, 16) * k])
			draw_polyline(zig, Color(Palette.SUNSET.darkened(0.2), a), 5.0 * k, true)
			return
	# Suluboya zemin lekesi
	_blob(c, 24.0 * k, Color(Palette.PAPER.lerp(col, 0.18), 0.9 * a))
	match _shape():
		"log": _log(c, k, col, ink)
		"branch": _branch(c, k, col, ink)
		"stone", "rock": _stone(c, k, col if _shape() == "stone" else Color(Palette.STONE, a), ink)
		"ore": _stone(c, k, Color(Palette.STONE, a), ink, col)
		"lump": _lump(c, k, col, ink)
		"reed": _reed(c, k, col, ink)
		"acorn": _acorn(c, k, col, ink)
		"cone", "seed": _cone(c, k, col if _shape() == "cone" else Color(Palette.WOOD, a), ink)
		"axe": _tool(c, k, true, ink, a)
		"pickaxe": _tool(c, k, false, ink, a)
		"workshop": _workshop(c, k, ink, a)
		"tree": _tree(c, k, ink, a)
		"hand": _hand(c, k, ink, a)
		"bridge": _bridge(c, k, ink, a)
		"mill": _mill(c, k, ink, a)
		"mold_handle": _handle_icon(c, k, col, ink)
		"mold_beam": _beam(c, k, col, ink)
		"mold_connector": _connector(c, k, col, ink)
		"mold_paddle": _paddle(c, k, col, ink)
		"mold_gear": _gear(c, k, col, ink)
		"mold_block": _block(c, k, col, ink)
		"mold_axle": _axle(c, k, col, ink)
		_: _lump(c, k, col, ink)


func _blob(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var ang := TAU * i / 20.0
		var rr := r * (1.0 + 0.07 * sin(ang * 3.0 + 1.3) + 0.05 * sin(ang * 5.0))
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	draw_colored_polygon(pts, col)


func _poly(pts: PackedVector2Array, fill: Color, ink: Color, w := 2.0) -> void:
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, ink, w, true)


func _log(c: Vector2, k: float, col: Color, ink: Color) -> void:
	var r := Rect2(c + Vector2(-16, -8) * k, Vector2(28, 16) * k)
	draw_rect(r, col)
	draw_rect(r, ink, false, 2.0 * k)
	draw_circle(c + Vector2(13, 0) * k, 8.5 * k, col.lightened(0.35))
	draw_arc(c + Vector2(13, 0) * k, 8.5 * k, 0, TAU, 18, ink, 2.0 * k, true)
	draw_arc(c + Vector2(13, 0) * k, 4.0 * k, 0, TAU, 12, Color(ink, ink.a * 0.6), 1.5 * k, true)


func _branch(c: Vector2, k: float, col: Color, ink: Color) -> void:
	draw_line(c + Vector2(-16, 12) * k, c + Vector2(15, -12) * k, ink, 6.0 * k)
	draw_line(c + Vector2(-16, 12) * k, c + Vector2(15, -12) * k, col, 3.5 * k)
	draw_line(c + Vector2(0, 0) * k, c + Vector2(-4, -13) * k, col, 3.0 * k)
	draw_circle(c + Vector2(-5, -15) * k, 5.0 * k, Palette.MOSS_LIGHT)
	draw_circle(c + Vector2(16, -13) * k, 4.0 * k, Palette.MOSS_LIGHT)


func _stone(c: Vector2, k: float, col: Color, ink: Color, spot := Color(0, 0, 0, 0)) -> void:
	var pts := PackedVector2Array([c + Vector2(-17, 9) * k, c + Vector2(-12, -6) * k, c + Vector2(-2, -12) * k,
		c + Vector2(11, -8) * k, c + Vector2(17, 4) * k, c + Vector2(9, 12) * k, c + Vector2(-8, 13) * k])
	_poly(pts, col, ink, 2.0 * k)
	draw_line(c + Vector2(-6, -4) * k, c + Vector2(3, -6) * k, Color(1, 1, 1, 0.45), 2.0 * k)
	if spot.a > 0.0:
		draw_circle(c + Vector2(-5, 3) * k, 4.0 * k, spot)
		draw_circle(c + Vector2(6, -1) * k, 3.2 * k, spot)
		draw_circle(c + Vector2(4, 7) * k, 2.4 * k, spot)


func _lump(c: Vector2, k: float, col: Color, ink: Color) -> void:
	draw_circle(c + Vector2(0, 2) * k, 14.0 * k, col)
	draw_arc(c + Vector2(0, 2) * k, 14.0 * k, 0, TAU, 24, ink, 2.0 * k, true)
	draw_circle(c + Vector2(-5, -3) * k, 4.0 * k, col.lightened(0.3))


func _reed(c: Vector2, k: float, col: Color, ink: Color) -> void:
	for i in 3:
		var x := (i - 1) * 7.0
		draw_line(c + Vector2(x, 16) * k, c + Vector2(x * 1.3, -10) * k, Palette.MOSS_DARK, 2.5 * k)
		draw_rect(Rect2(c + Vector2(x * 1.3 - 3, -16) * k, Vector2(6, 11) * k), Palette.WOOD)
	draw_line(c + Vector2(-9, 6) * k, c + Vector2(9, 6) * k, col, 4.0 * k)
	draw_line(c + Vector2(-9, 6) * k, c + Vector2(9, 6) * k, ink, 1.0 * k)


func _acorn(c: Vector2, k: float, col: Color, ink: Color) -> void:
	draw_circle(c + Vector2(0, 4) * k, 11.0 * k, col.lightened(0.15))
	draw_arc(c + Vector2(0, 4) * k, 11.0 * k, 0, TAU, 20, ink, 2.0 * k, true)
	var cap := PackedVector2Array([c + Vector2(-13, -2) * k, c + Vector2(-9, -11) * k, c + Vector2(9, -11) * k, c + Vector2(13, -2) * k])
	_poly(cap, col.darkened(0.35), ink, 2.0 * k)
	draw_line(c + Vector2(0, -11) * k, c + Vector2(3, -17) * k, ink, 2.5 * k)


func _cone(c: Vector2, k: float, col: Color, ink: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -16) * k, c + Vector2(11, 0) * k, c + Vector2(6, 14) * k, c + Vector2(-6, 14) * k, c + Vector2(-11, 0) * k])
	_poly(pts, col, ink, 2.0 * k)
	for y: float in [-6.0, 2.0, 9.0]:
		draw_line(c + Vector2(-8, y) * k, c + Vector2(8, y) * k, Color(ink, ink.a * 0.6), 1.5 * k)


func _tool(c: Vector2, k: float, axe: bool, ink: Color, a: float) -> void:
	draw_line(c + Vector2(-13, 16) * k, c + Vector2(10, -12) * k, ink, 6.0 * k)
	draw_line(c + Vector2(-13, 16) * k, c + Vector2(10, -12) * k, Color(Palette.WOOD, a), 3.5 * k)
	var stone := Color(Palette.STONE, a)
	if axe:
		var head := PackedVector2Array([c + Vector2(4, -16) * k, c + Vector2(18, -18) * k, c + Vector2(20, -2) * k, c + Vector2(9, -5) * k])
		_poly(head, stone, ink, 2.0 * k)
	else:
		var head := PackedVector2Array([c + Vector2(-6, -18) * k, c + Vector2(8, -14) * k, c + Vector2(22, -2) * k, c + Vector2(19, 1) * k, c + Vector2(7, -8) * k, c + Vector2(-5, -12) * k])
		_poly(head, stone, ink, 2.0 * k)
	draw_line(c + Vector2(5, -9) * k, c + Vector2(10, -13) * k, Color(Palette.REED, a), 4.0 * k)


func _workshop(c: Vector2, k: float, ink: Color, a: float) -> void:
	var wall := Rect2(c + Vector2(-14, -2) * k, Vector2(28, 17) * k)
	draw_rect(wall, Color(Palette.WOOD, a))
	draw_rect(wall, ink, false, 2.0 * k)
	var roof := PackedVector2Array([c + Vector2(-19, -1) * k, c + Vector2(0, -18) * k, c + Vector2(19, -1) * k])
	_poly(roof, Color(Palette.ROOF, a), ink, 2.0 * k)
	draw_rect(Rect2(c + Vector2(-4, 4) * k, Vector2(8, 11) * k), Color(Palette.INK, 0.8 * a))
	draw_rect(Rect2(c + Vector2(8, -15) * k, Vector2(5, 8) * k), Color(Palette.STONE, a))


func _tree(c: Vector2, k: float, ink: Color, a: float) -> void:
	draw_rect(Rect2(c + Vector2(-3, 2) * k, Vector2(6, 15) * k), Color(Palette.WOOD_DARK, a))
	for p: Vector2 in [Vector2(0, -8), Vector2(-8, -2), Vector2(8, -2), Vector2(0, -14)]:
		draw_circle(c + p * k, 9.0 * k, Color(Palette.MOSS, a))
	draw_arc(c + Vector2(0, -6) * k, 15.0 * k, PI * 0.95, TAU + 0.05, 20, Color(ink, ink.a * 0.5), 1.5 * k, true)


func _hand(c: Vector2, k: float, ink: Color, a: float) -> void:
	var skin := Color(Palette.SKIN, a)
	draw_rect(Rect2(c + Vector2(-10, -2) * k, Vector2(20, 16) * k), skin)
	for i in 4:
		draw_rect(Rect2(c + Vector2(-10 + i * 5, -14 + absf(i - 1.5) * 2.0) * k, Vector2(4.5, 14) * k), skin)
	draw_rect(Rect2(c + Vector2(10, 0) * k, Vector2(6, 5) * k).abs(), skin)
	draw_rect(Rect2(c + Vector2(-10, -2) * k, Vector2(20, 16) * k), ink, false, 1.5 * k)


func _arrow(c: Vector2, k: float, ink: Color) -> void:
	draw_line(c + Vector2(-14, 0) * k, c + Vector2(10, 0) * k, ink, 4.0 * k)
	draw_colored_polygon(PackedVector2Array([c + Vector2(16, 0) * k, c + Vector2(6, -8) * k, c + Vector2(6, 8) * k]), ink)


# --- Cihaza göre kontrol ikonları ---------------------------------------------------
func _control_icon(c: Vector2, k: float, ink: Color, a: float) -> void:
	var dev: int = InputManager.device
	var touch: bool = dev == InputManager.Device.TOUCH
	var pad: bool = dev == InputManager.Device.GAMEPAD
	match icon:
		"move":
			if touch:
				_touch_stick(c, k, ink, a, true)
			elif pad:
				_pad_stick(c, k, ink, a, "L")
			else:
				_keycap(c + Vector2(0, -12) * k, k * 0.72, "W", ink, a)
				for i in 3:
					_keycap(c + Vector2(-21 + i * 21, 11) * k, k * 0.72, ["A", "S", "D"][i], ink, a)
		"look":
			if touch:
				_touch_stick(c, k, ink, a, false)
			elif pad:
				_pad_stick(c, k, ink, a, "R")
			else:
				_mouse(c, k, ink, a)
		_:
			var g: String = InputManager.glyph_for(icon)
			if touch:
				_tap(c, k, ink, a)
			elif pad:
				draw_circle(c, 18.0 * k, Color(Palette.MOSS_LIGHT, a))
				draw_arc(c, 18.0 * k, 0, TAU, 28, ink, 2.0 * k, true)
				_text(c, g, int(24 * k), ink)
			else:
				_keycap(c, k * (1.0 if g.length() < 2 else 1.3), g, ink, a)


func _keycap(c: Vector2, k: float, label: String, ink: Color, a: float) -> void:
	var w := maxf(28.0, 16.0 + label.length() * 11.0) * k
	var r := Rect2(c - Vector2(w, 28.0 * k) * 0.5, Vector2(w, 28.0 * k))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.SUNSET_LIGHT, a)
	sb.border_color = ink
	sb.set_border_width_all(maxi(1, int(2.0 * k)))
	sb.set_corner_radius_all(int(7 * k))
	draw_style_box(sb, r)
	_text(c, label, int(22 * k), ink)


func _text(c: Vector2, t: String, fs: int, ink: Color) -> void:
	var font := get_theme_default_font()
	var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.33), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


func _pad_stick(c: Vector2, k: float, ink: Color, a: float, side: String) -> void:
	draw_circle(c, 19.0 * k, Color(Palette.PAPER.darkened(0.08), a))
	draw_arc(c, 19.0 * k, 0, TAU, 28, ink, 2.0 * k, true)
	draw_circle(c, 10.0 * k, Color(Palette.MOSS_LIGHT, a))
	draw_arc(c, 10.0 * k, 0, TAU, 20, ink, 1.5 * k, true)
	_text(c, side, int(16 * k), ink)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var tip := c + d * 26.0 * k
		var side_v := Vector2(-d.y, d.x) * 4.0 * k
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 6.0 * k + side_v, tip - d * 6.0 * k - side_v]), ink)


func _touch_stick(c: Vector2, k: float, ink: Color, a: float, joystick: bool) -> void:
	if joystick:
		draw_arc(c, 20.0 * k, 0, TAU, 28, Color(ink, ink.a * 0.7), 2.0 * k, true)
		draw_circle(c + Vector2(7, -5) * k, 9.0 * k, Color(Palette.SUNSET_LIGHT, a))
		draw_arc(c + Vector2(7, -5) * k, 9.0 * k, 0, TAU, 18, ink, 1.5 * k, true)
	else:
		draw_line(c + Vector2(-18, 6) * k, c + Vector2(14, 6) * k, ink, 2.5 * k)
		draw_colored_polygon(PackedVector2Array([c + Vector2(20, 6) * k, c + Vector2(12, 0) * k, c + Vector2(12, 12) * k]), ink)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-24, 6) * k, c + Vector2(-16, 0) * k, c + Vector2(-16, 12) * k]), ink)
		draw_circle(c + Vector2(0, -6) * k, 8.0 * k, Color(Palette.SUNSET_LIGHT, a))
		draw_arc(c + Vector2(0, -6) * k, 8.0 * k, 0, TAU, 18, ink, 1.5 * k, true)


func _tap(c: Vector2, k: float, ink: Color, a: float) -> void:
	draw_circle(c, 20.0 * k, Color(Palette.SUNSET_LIGHT, 0.9 * a))
	draw_arc(c, 16.0 * k, 0, TAU, 28, Color(ink, ink.a * 0.8), 2.5 * k, true)
	draw_arc(c, 10.0 * k, 0, TAU, 20, Color(ink, ink.a * 0.5), 2.0 * k, true)
	draw_circle(c, 4.5 * k, ink)


func _mouse(c: Vector2, k: float, ink: Color, a: float) -> void:
	var body := Rect2(c + Vector2(-11, -16) * k, Vector2(22, 32) * k)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.PAPER, a)
	sb.border_color = ink
	sb.set_border_width_all(maxi(1, int(2.0 * k)))
	sb.set_corner_radius_all(int(11 * k))
	draw_style_box(sb, body)
	draw_line(c + Vector2(0, -16) * k, c + Vector2(0, -4) * k, ink, 1.5 * k)
	for s: float in [-1.0, 1.0]:
		var tip := c + Vector2(s * 25.0, 0) * k
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-s * 7, -5) * k, tip + Vector2(-s * 7, 5) * k]), ink)


# --- Kalıp / parça ikonları (renk = malzeme; kalıp listesinde nötr ahşap) ---------------
func _neutral(col: Color) -> Color:
	return Color(Palette.WOOD_OLD, col.a) if icon.begins_with("mold_") else col


func _handle_icon(c: Vector2, k: float, col: Color, ink: Color) -> void:
	col = _neutral(col)
	draw_line(c + Vector2(-14, 15) * k, c + Vector2(13, -14) * k, ink, 8.0 * k)
	draw_line(c + Vector2(-14, 15) * k, c + Vector2(13, -14) * k, col, 5.0 * k)
	draw_line(c + Vector2(-10, 11) * k, c + Vector2(-5, 6) * k, Color(Palette.REED, col.a), 6.0 * k)


func _beam(c: Vector2, k: float, col: Color, ink: Color) -> void:
	col = _neutral(col)
	var pts := PackedVector2Array([c + Vector2(-20, -2) * k, c + Vector2(14, -10) * k, c + Vector2(20, -4) * k, c + Vector2(-14, 4) * k])
	_poly(pts, col.lightened(0.15), ink, 2.0 * k)
	var front := PackedVector2Array([c + Vector2(-14, 4) * k, c + Vector2(20, -4) * k, c + Vector2(20, 4) * k, c + Vector2(-14, 12) * k])
	_poly(front, col, ink, 2.0 * k)
	draw_line(c + Vector2(-8, 8) * k, c + Vector2(12, 3) * k, Color(ink, ink.a * 0.4), 1.2 * k)


func _connector(c: Vector2, k: float, col: Color, ink: Color) -> void:
	col = _neutral(col)
	draw_arc(c + Vector2(-6, 0) * k, 10.0 * k, 0, TAU, 20, ink, 6.5 * k, true)
	draw_arc(c + Vector2(-6, 0) * k, 10.0 * k, 0, TAU, 20, col, 4.0 * k, true)
	draw_arc(c + Vector2(7, 0) * k, 10.0 * k, 0, TAU, 20, ink, 6.5 * k, true)
	draw_arc(c + Vector2(7, 0) * k, 10.0 * k, 0, TAU, 20, col, 4.0 * k, true)


func _paddle(c: Vector2, k: float, col: Color, ink: Color) -> void:
	col = _neutral(col)
	draw_line(c + Vector2(0, 18) * k, c + Vector2(0, -2) * k, ink, 5.0 * k)
	var blade := Rect2(c + Vector2(-11, -18) * k, Vector2(22, 20) * k)
	draw_rect(blade, col)
	draw_rect(blade, ink, false, 2.0 * k)
	draw_line(c + Vector2(-6, -14) * k, c + Vector2(-6, -2) * k, Color(ink, ink.a * 0.35), 1.2 * k)


func _gear(c: Vector2, k: float, col: Color, ink: Color) -> void:
	col = _neutral(col)
	var pts := PackedVector2Array()
	for i in 24:
		var ang := TAU * i / 24.0
		var r := (17.0 if i % 3 != 0 else 12.5) * k
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	_poly(pts, col, ink, 2.0 * k)
	draw_circle(c, 5.0 * k, Color(Palette.PAPER, col.a))
	draw_arc(c, 5.0 * k, 0, TAU, 14, ink, 1.5 * k, true)


## Duvar taşı: üst üste iki sıra blok, aralarında harç çizgisi.
func _block(c: Vector2, k: float, col: Color, ink: Color) -> void:
	col = _neutral(col)
	var mortar := Color(Palette.CLAY.lightened(0.3), col.a)
	for row in 2:
		var y := (-14.0 + row * 14.0)
		var off := 0.0 if row == 0 else -8.0
		for i in 2:
			var r := Rect2(c + Vector2(-18 + off + i * 18, y) * k, Vector2(17, 12) * k)
			draw_rect(r, col.lightened(0.08 * i))
			draw_rect(r, ink, false, 1.8 * k)
	draw_line(c + Vector2(-20, -1) * k, c + Vector2(20, -1) * k, mortar, 2.0 * k)


## Aks: uzun silindir, uçlarında halka.
func _axle(c: Vector2, k: float, col: Color, ink: Color) -> void:
	col = _neutral(col)
	draw_line(c + Vector2(-19, 10) * k, c + Vector2(19, -10) * k, ink, 10.0 * k)
	draw_line(c + Vector2(-19, 10) * k, c + Vector2(19, -10) * k, col, 7.0 * k)
	for p: Vector2 in [Vector2(-13, 7), Vector2(13, -7)]:
		draw_circle(c + p * k, 6.0 * k, ink)
		draw_circle(c + p * k, 4.5 * k, col.darkened(0.15))


## Kemerli küçük köprü: iki ayak, kalas sırası, altında su çizgisi.
func _bridge(c: Vector2, k: float, ink: Color, a: float) -> void:
	draw_line(c + Vector2(-22, 12) * k, c + Vector2(22, 12) * k, Color(Palette.SKY, a), 5.0 * k)
	var deck := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		deck.append(c + Vector2(lerpf(-20, 20, t), -2 - sin(t * PI) * 7.0) * k)
	draw_polyline(deck, ink, 7.0 * k, true)
	draw_polyline(deck, Color(Palette.WOOD, a), 4.5 * k, true)
	for x: float in [-14.0, 14.0]:
		var top := c + Vector2(x, -2 - sin((x + 20.0) / 40.0 * PI) * 7.0) * k
		draw_line(top, c + Vector2(x, 12) * k, ink, 5.0 * k)
		draw_line(top, c + Vector2(x, 12) * k, Color(Palette.STONE, a), 3.0 * k)


## Değirmen: taş gövde, sivri çatı ve yanda kürekli çark.
func _mill(c: Vector2, k: float, ink: Color, a: float) -> void:
	var wall := Rect2(c + Vector2(-15, -4) * k, Vector2(20, 19) * k)
	draw_rect(wall, Color(Palette.STONE, a))
	draw_rect(wall, ink, false, 2.0 * k)
	var roof := PackedVector2Array([c + Vector2(-19, -3) * k, c + Vector2(-5, -18) * k, c + Vector2(9, -3) * k])
	_poly(roof, Color(Palette.ROOF, a), ink, 2.0 * k)
	var w := c + Vector2(12, 5) * k
	draw_circle(w, 9.0 * k, Color(Palette.WOOD, a))
	for i in 6:
		var d := Vector2.from_angle(i * TAU / 6.0)
		draw_line(w, w + d * 12.0 * k, ink, 2.5 * k)
	draw_arc(w, 9.0 * k, 0, TAU, 20, ink, 2.0 * k, true)
	draw_rect(Rect2(c + Vector2(-9, 5) * k, Vector2(6, 10) * k), Color(Palette.INK, 0.8 * a))
