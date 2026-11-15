class_name PickupFeed
extends VBoxContainer
## Sol kenarda kısa "+3 Meşe" kartları. Aynı malzeme art arda gelirse sayı birikir.

const LIFETIME := 2.6

var _entries := {}   ## id -> {panel, label, amount, t}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	alignment = BoxContainer.ALIGNMENT_END


func add_item(id: String, amount: int) -> void:
	if _entries.has(id):
		var e: Dictionary = _entries[id]
		e.amount += amount
		e.t = LIFETIME
		(e.label as Label).text = _text(id, e.amount)
		var p: Control = e.panel
		p.scale = Vector2(1.08, 1.08)
		create_tween().tween_property(p, "scale", Vector2.ONE, 0.2)
		return
	var panel := WatercolorPanel.new()
	panel.card = true
	panel.padding = Vector2(14, 4)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := ItemIcon.new()
	ic.icon = id
	ic.custom_minimum_size = Vector2(44, 44)
	row.add_child(ic)
	var l := Label.new()
	l.text = _text(id, amount)
	l.add_theme_font_size_override("font_size", 24)
	row.add_child(l)
	panel.add_child(row)
	add_child(panel)
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.2)
	_entries[id] = {"panel": panel, "label": l, "amount": amount, "t": LIFETIME}


func _text(id: String, amount: int) -> String:
	return "+%d %s" % [amount, tr(Materials.display_name(id))]


func _process(delta: float) -> void:
	for id in _entries.keys():
		var e: Dictionary = _entries[id]
		e.t -= delta
		var p: Control = e.panel
		if e.t < 0.5:
			p.modulate.a = clampf(e.t / 0.5, 0.0, 1.0)
		if e.t <= 0.0:
			p.queue_free()
			_entries.erase(id)
