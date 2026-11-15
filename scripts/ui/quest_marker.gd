class_name QuestMarker
extends Control
## Görev işaretçisi: mevcut hedefin (atölye, köprü, demir damarı, değirmen) ekrandaki
## yerinde suluboya bir damla ve içinde hedefin ikonu, altında mesafe. Hedef ekran
## dışındaysa kenara yapışır ve yönü gösteren bir ok çizer. Yakına gelince söner.

const PIN_R := 30.0
const EDGE := 56.0

var tutorial: Tutorial
var player: Player
var _icon: ItemIcon
var _dist: Label
var _on_screen := true
var _dir := Vector2.DOWN
var _t := 0.0
var _alpha := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon = ItemIcon.new()
	_icon.size = Vector2(44, 44)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_dist = Label.new()
	_dist.add_theme_font_size_override("font_size", 18)
	_dist.add_theme_color_override("font_outline_color", Palette.PAPER)
	_dist.add_theme_constant_override("outline_size", 6)
	_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dist.size = Vector2(80, 24)
	add_child(_dist)


func _process(delta: float) -> void:
	_t += delta
	var goal := tutorial.goal_position() if tutorial != null else Vector3.INF
	var show := goal != Vector3.INF and player != null and player.input_enabled and not get_tree().paused
	var d := INF
	if show:
		d = player.global_position.distance_to(goal)
		show = d > Tutorial.MARKER_HIDE
	_alpha = move_toward(_alpha, 1.0 if show else 0.0, delta * 4.0)
	visible = _alpha > 0.01
	if not visible or goal == Vector3.INF or player == null:
		return
	var p := _screen_point(goal)
	var bob := sin(_t * 3.0) * 4.0 if _on_screen else 0.0
	position = Vector2.ZERO
	var c := p + Vector2(0, bob)
	_icon.icon = tutorial.goal_icon()
	_icon.position = c - _icon.size * 0.5
	_dist.text = "%d m" % int(round(d)) if d != INF else ""
	_dist.position = c + Vector2(-40, PIN_R + 2.0)
	modulate.a = _alpha
	set_meta("pin", c)
	queue_redraw()


## Hedefin ekrandaki yeri; kamera arkasında ya da dışarıdaysa kenara kenetlenir.
func _screen_point(goal: Vector3) -> Vector2:
	var cam := player.camera
	var vp := get_viewport_rect().size
	var center := vp * 0.5
	var behind := cam.is_position_behind(goal)
	var p := cam.unproject_position(goal)
	if behind:
		# Arkadaysa: sağ ya da sol kenara (alttaki ipucu kartının üstüne binmesin).
		var side := signf(center.x - p.x) if absf(center.x - p.x) > 1.0 else 1.0
		p = Vector2(center.x + side * vp.x * 4.0, center.y)
	var inner := Rect2(Vector2(EDGE, 130.0), Vector2(vp.x - EDGE * 2.0, vp.y - 130.0 - 150.0))
	_on_screen = not behind and inner.has_point(p)
	if _on_screen:
		return p
	var v := p - center
	if v.length() < 0.01:
		v = Vector2.DOWN
	_dir = v.normalized()
	var half := inner.size * 0.5
	var s := minf(half.x / maxf(absf(v.x), 0.001), half.y / maxf(absf(v.y), 0.001))
	return inner.get_center() + v * s


func _draw() -> void:
	if not has_meta("pin"):
		return
	var c: Vector2 = get_meta("pin")
	var pulse := 1.0 + 0.06 * sin(_t * 5.0)
	# Gölge, mürekkep kenar, kâğıt iç: ikon okunaklı kalsın.
	draw_circle(c + Vector2(2, 3), PIN_R * pulse, Color(0.25, 0.18, 0.12, 0.25))
	draw_circle(c, PIN_R * pulse, Palette.SUNSET)
	draw_circle(c, (PIN_R - 4.0) * pulse, Palette.PAPER)
	if _on_screen:
		# Damla ucu: hedefi gösteren küçük üçgen.
		var tip := PackedVector2Array([c + Vector2(-9, PIN_R - 3), c + Vector2(9, PIN_R - 3), c + Vector2(0, PIN_R + 12)])
		draw_colored_polygon(tip, Palette.SUNSET)
	else:
		var a := c + _dir * (PIN_R + 16.0)
		var side := _dir.orthogonal() * 10.0
		draw_colored_polygon(PackedVector2Array([a, c + _dir * (PIN_R + 2.0) + side, c + _dir * (PIN_R + 2.0) - side]), Palette.SUNSET)
