class_name SafeArea
extends MarginContainer
## Telefon çentiği / güvenli alan: kenar boşluklarını DisplayServer'dan hesaplar.
## Masaüstünde sabit küçük bir kenar boşluğu kullanılır.

const BASE_MARGIN := 16


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var m := compute_margins(get_viewport())
	add_theme_constant_override("margin_left", int(m.x))
	add_theme_constant_override("margin_top", int(m.y))
	add_theme_constant_override("margin_right", int(m.z))
	add_theme_constant_override("margin_bottom", int(m.w))


## (sol, üst, sağ, alt) kenar boşlukları, kanvas (UI) biriminde.
static func compute_margins(vp: Viewport) -> Vector4:
	var base := Vector4(BASE_MARGIN, BASE_MARGIN, BASE_MARGIN, BASE_MARGIN)
	if not OS.has_feature("mobile"):
		return base
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0:
		return base
	var canvas := vp.get_visible_rect().size
	var k := canvas.x / win.x
	var left := safe.position.x * k
	var top := safe.position.y * k
	var right := (win.x - safe.end.x) * k
	var bottom := (win.y - safe.end.y) * k
	return Vector4(maxf(left, BASE_MARGIN), maxf(top, BASE_MARGIN), maxf(right, BASE_MARGIN), maxf(bottom, BASE_MARGIN))
