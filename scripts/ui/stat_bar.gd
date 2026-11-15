class_name StatBar
extends Control
## Suluboya istatistik çubuğu (0-10): fırça darbesi gibi hafif dalgalı dolgu.

@export var value := 5.0:
	set(v):
		value = v
		queue_redraw()
@export var color := Color(0.36, 0.62, 0.27)
@export var neutral := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var h := size.y
	draw_rect(Rect2(Vector2(0, h * 0.2), Vector2(size.x, h * 0.6)), Color(Palette.EARTH, 0.18))
	var w := size.x * clampf(value / 10.0, 0.0, 1.0)
	var col := Palette.SKY if neutral else (color if value >= 4.0 else Palette.SUNSET)
	var pts := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var x := w * i / steps
		pts.append(Vector2(x, h * 0.12 + sin(i * 1.7) * 1.2))
	for i in range(steps, -1, -1):
		var x := w * i / steps
		pts.append(Vector2(x, h * 0.88 + sin(i * 2.3 + 1.0) * 1.2))
	if w > 2.0:
		draw_colored_polygon(pts, col)
		draw_line(Vector2(w, h * 0.1), Vector2(w, h * 0.9), Color(col.darkened(0.3), 0.8), 2.0)
	for t in range(1, 10):
		draw_line(Vector2(size.x * t / 10.0, h * 0.75), Vector2(size.x * t / 10.0, h * 0.95), Color(Palette.INK, 0.2), 1.0)
