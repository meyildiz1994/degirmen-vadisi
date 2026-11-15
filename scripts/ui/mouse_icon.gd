extends Control
## Küçük fare ikonu (sol tuş vurgulu), "etrafa bakmak için tıkla" kartında.


func _draw() -> void:
	var r := Rect2(Vector2(3, 2), size - Vector2(6, 4))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PAPER
	sb.border_color = Palette.INK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(r.size.x * 0.5))
	draw_style_box(sb, r)
	var mid := r.position.x + r.size.x * 0.5
	var split := r.position.y + r.size.y * 0.42
	draw_line(Vector2(mid, r.position.y + 2), Vector2(mid, split), Palette.INK, 1.5)
	draw_line(Vector2(r.position.x + 2, split), Vector2(r.end.x - 2, split), Palette.INK, 1.5)
	# Sol tuş dolu (tıkla)
	var left := PackedVector2Array([
		Vector2(r.position.x + 4, split - 1), Vector2(mid - 1, split - 1),
		Vector2(mid - 1, r.position.y + 4), Vector2(r.position.x + 6, r.position.y + 7),
	])
	draw_colored_polygon(left, Palette.SUNSET)
