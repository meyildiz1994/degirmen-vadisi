class_name CursorArt
extends RefCounted
## Oyuna özel fare imleci, kodla çizilir (harici görsel yok): mürekkep kenarlı,
## gün batımı turuncusu dolgulu, fırça ucunu andıran yuvarlatılmış ok.
## Masaüstünde InputManager açılışta uygular; mobilde hiç kullanılmaz.

const SIZE := 40
const SUB := 4   ## kenar yumuşatma için piksel başına alt örnek


static func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var arrow := ImageTexture.create_from_image(_arrow_image())
	Input.set_custom_mouse_cursor(arrow, Input.CURSOR_ARROW, Vector2(3, 2))
	Input.set_custom_mouse_cursor(arrow, Input.CURSOR_POINTING_HAND, Vector2(3, 2))


static func _arrow_image() -> Image:
	var outer := PackedVector2Array([
		Vector2(3, 2), Vector2(31, 19), Vector2(19, 21.5), Vector2(26, 34),
		Vector2(20.5, 37), Vector2(13.5, 24.5), Vector2(5, 33),
	])
	var inner := _shrink(outer, 3.0)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var ink := Palette.INK
	var fill := Palette.SUNSET_LIGHT
	var shade := Palette.SUNSET
	for y in SIZE:
		for x in SIZE:
			var cov_out := 0
			var cov_in := 0
			var cov_shadow := 0
			for sy in SUB:
				for sx in SUB:
					var p := Vector2(x + (sx + 0.5) / SUB, y + (sy + 0.5) / SUB)
					if Geometry2D.is_point_in_polygon(p, outer):
						cov_out += 1
					if Geometry2D.is_point_in_polygon(p, inner):
						cov_in += 1
					if Geometry2D.is_point_in_polygon(p - Vector2(1.5, 2.0), outer):
						cov_shadow += 1
			var n := float(SUB * SUB)
			var a_out := cov_out / n
			var a_in := cov_in / n
			# Suluboya: dolgu sağ alta doğru koyulaşır.
			var t := clampf((x + y) / 60.0, 0.0, 1.0)
			var body := fill.lerp(shade, t)
			var c := ink.lerp(body, a_in / maxf(a_out, 0.001)) if a_out > 0.0 else Color(0, 0, 0, 0)
			c.a = a_out
			if a_out < 1.0 and cov_shadow > 0:
				var sh := Color(0.25, 0.18, 0.12, 0.28 * cov_shadow / n)
				c = sh.lerp(c, a_out) if a_out > 0.0 else sh
				c.a = maxf(a_out, sh.a)
			img.set_pixel(x, y, c)
	return img


## Çokgeni merkezine doğru küçült (iç dolgu için yeterli).
static func _shrink(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(poly, -amount, Geometry2D.JOIN_ROUND)
	return res[0] if not res.is_empty() else poly
