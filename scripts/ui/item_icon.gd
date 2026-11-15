@tool
class_name ItemIcon
extends Control
## Metinsiz ipuçları ve heybe için kodla çizilen suluboya ikonlar.
## icon: malzeme/tohum kimliği (oak, stone, acorn...) ya da özel ikon
## (axe, pickaxe, workshop, tree, rock, hand, arrow, plus, check, seed).

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


func _shape() -> String:
	if Engine.is_editor_hint():
		return icon
	if Materials.is_material(icon) or Materials.is_seed(icon):
		return Materials.icon(icon)
	return icon


func _color() -> Color:
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
