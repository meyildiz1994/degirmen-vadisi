class_name AimReticle
extends Control
## Fareyle oynarken ekranın ortasındaki suluboya nişangâh (oyun içi imleç).
## Hedef varsa genişleyip turuncuya döner: "sol tık ya da E ile etkileş".

var has_target := false:
	set(v):
		if v != has_target:
			has_target = v
			_t = 0.0
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var ink := Palette.INK
	draw_circle(c + Vector2(1, 1.5), 4.0, Color(0.25, 0.18, 0.12, 0.3))
	draw_circle(c, 3.5, Color(Palette.PAPER, 0.95))
	draw_arc(c, 3.5, 0.0, TAU, 14, Color(ink, 0.8), 1.5, true)
	if not has_target:
		draw_arc(c, 11.0, 0.0, TAU, 28, Color(Palette.PAPER, 0.55), 2.0, true)
		return
	var grow := minf(_t * 8.0, 1.0)
	var r := lerpf(11.0, 17.0, grow) + sin(_t * 5.0) * 1.2
	draw_arc(c, r + 1.0, 0.0, TAU, 32, Color(ink, 0.45), 3.5, true)
	draw_arc(c, r, 0.0, TAU, 32, Color(Palette.SUNSET_LIGHT, 0.95), 3.0, true)
	for i in 4:
		var ang := TAU * i / 4.0 + PI * 0.25
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * (r + 4.0), c + d * (r + 9.0), Color(Palette.SUNSET, 0.9), 3.0, true)
