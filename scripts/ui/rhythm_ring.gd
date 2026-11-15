class_name RhythmRing
extends Control
## Vuruş halkası: kaynağın üstünde sabit bir hedef daire ve ona doğru küçülen halka.
## Halka daireye değdiğinde basmak tatlı vuruş. Dairenin çevresindeki yay ilerlemeyi gösterir.
## Ritim kapalıyken yalnızca ilerleme dairesi görünür (basılı tut).

const TARGET_R := 30.0
const START_R := 92.0

var controller: GatherController
var camera: Camera3D
var _pop := 0.0
var _pop_sweet := false
var _pop_pos := Vector2.ZERO
var _alpha := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func bind(c: GatherController, cam: Camera3D) -> void:
	controller = c
	camera = cam
	c.hit_landed.connect(_on_hit)


func _on_hit(_g: Gatherable, sweet: bool) -> void:
	_pop = 1.0
	_pop_sweet = sweet


func _process(delta: float) -> void:
	var on := controller != null and controller.active()
	_alpha = move_toward(_alpha, 1.0 if on else 0.0, delta * 6.0)
	_pop = maxf(_pop - delta * 2.6, 0.0)
	if _alpha > 0.0 or _pop > 0.0:
		queue_redraw()


func _screen_pos() -> Vector2:
	if controller == null or controller.target == null or camera == null:
		return _pop_pos
	var wp := controller.target.fx_point() + Vector3(0, 0.9, 0)
	if camera.is_position_behind(wp):
		return _pop_pos
	# Halka doğrudan HUD katmanında (tam ekran), bu yüzden görüntü koordinatı yeterli.
	return camera.unproject_position(wp)


func _draw() -> void:
	var c := _screen_pos()
	_pop_pos = c
	var a := _alpha
	if controller != null and controller.active():
		var g := controller.target
		_draw_target(c, a, g.progress, controller.in_sweet_window())
		if GameState.rhythm_hits:
			var p := controller.ring_phase()
			var r := lerpf(START_R, TARGET_R, p)
			var col := Palette.SUNSET_LIGHT if controller.in_sweet_window() else Palette.SUNSET
			var w := 5.0 + 3.0 * float(controller.in_sweet_window())
			draw_arc(c, r, 0, TAU, 48, Color(Palette.INK, 0.35 * a), w + 3.0, true)
			_soft_ring(c, r, Color(col, a * lerpf(0.55, 1.0, p)), w)
	if _pop > 0.0:
		_draw_pop(c, _pop, _pop_sweet)


func _draw_target(c: Vector2, a: float, progress: float, sweet_now: bool) -> void:
	draw_circle(c, TARGET_R, Color(Palette.PAPER, 0.55 * a))
	if sweet_now:
		draw_circle(c, TARGET_R - 4.0, Color(Palette.SUNSET_LIGHT, 0.55 * a))
	_soft_ring(c, TARGET_R, Color(Palette.INK, 0.55 * a), 2.5)
	# İlerleme yayı: kâğıt rengi iz üstünde koyu yeşil
	draw_arc(c, TARGET_R + 9.0, 0, TAU, 40, Color(Palette.PAPER, 0.7 * a), 9.0, true)
	if progress > 0.0:
		draw_arc(c, TARGET_R + 9.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, Color(Palette.MOSS_DARK, 0.95 * a), 6.0, true)


## İki kez, hafif kaydırılmış çizim: elle çekilmiş fırça hissi.
func _soft_ring(c: Vector2, r: float, col: Color, w: float) -> void:
	draw_arc(c, r, 0, TAU, 48, col, w, true)
	draw_arc(c + Vector2(0.8, -0.6), r + 1.2, 0.3, TAU + 0.3, 48, Color(col, col.a * 0.35), w * 0.6, true)


func _draw_pop(c: Vector2, t: float, sweet: bool) -> void:
	var k := 1.0 - t
	var col := Palette.SUNSET_LIGHT if sweet else Palette.PAPER
	draw_arc(c, TARGET_R + k * (46.0 if sweet else 22.0), 0, TAU, 40, Color(col, t * 0.9), 5.0 * t + 1.0, true)
	if sweet:
		for i in 8:
			var ang := TAU * i / 8.0 + 0.2
			var d := Vector2(cos(ang), sin(ang))
			draw_line(c + d * (TARGET_R + 6.0 + k * 30.0), c + d * (TARGET_R + 16.0 + k * 44.0), Color(Palette.SUNSET, t), 4.0, true)
