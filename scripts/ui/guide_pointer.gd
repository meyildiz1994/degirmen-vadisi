class_name GuidePointer
extends Control
## Metinsiz yol gösterici: hedef kontrolün etrafında nabız gibi atan suluboya halka
## ve ona dokunmayı gösteren sallanan bir el. Panellerin en üstünde, girişi engellemez.
## Gamepad'de hedef bir düğmeyse odak da ona geçer.

var target: Control:
	set(v):
		if v == target:
			return
		target = v
		_t = 0.0
		if v is Button and InputManager.device == InputManager.Device.GAMEPAD:
			(v as Button).grab_focus.call_deferred()
		queue_redraw()

var _t := 0.0
var _hand: ItemIcon


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand = ItemIcon.new()
	_hand.icon = "hand"
	_hand.custom_minimum_size = Vector2(68, 68)
	_hand.size = Vector2(68, 68)
	_hand.visible = false
	add_child(_hand)


func _valid() -> bool:
	return target != null and is_instance_valid(target) and target.is_visible_in_tree() \
		and not target.is_queued_for_deletion()


func _process(delta: float) -> void:
	_t += delta
	var ok := _valid()
	_hand.visible = ok
	if ok:
		var r := _rect()
		var bob := sin(_t * 5.0) * 6.0
		_hand.position = r.position + Vector2(r.size.x - 30.0, r.size.y - 20.0) + Vector2(bob, bob)
		_hand.modulate.a = clampf(_t * 4.0, 0.0, 1.0)
	queue_redraw()


func _rect() -> Rect2:
	var gr := target.get_global_rect()
	return Rect2(gr.position - global_position, gr.size)


func _draw() -> void:
	if not _valid():
		return
	var grow := 5.0 + 3.0 * (0.5 + 0.5 * sin(_t * 5.0))
	var r := _rect().grow(grow)
	var a := clampf(_t * 4.0, 0.0, 1.0)
	var col := Color(Palette.SUNSET, 0.85 * a)
	# Elle çizilmiş gibi: iki kat, hafif kaymış çerçeve.
	draw_rect(r, col, false, 4.0)
	draw_rect(r.grow(-2.0).grow_individual(1.5, -1.0, -1.0, 1.5), Color(Palette.SUNSET_LIGHT, 0.6 * a), false, 2.0)
