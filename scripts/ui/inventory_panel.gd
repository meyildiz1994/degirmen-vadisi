class_name InventoryPanel
extends Control
## Heybe: malzemeler ve tohumlar sınırsız yığılır (sayılarla), aletler slotlarda
## dayanıklılık çubuğuyla. Kod ile kurulur; dokunmatikte boşluğa dokunmak kapatır.

signal closed

var _grid: GridContainer
var _tools_box: VBoxContainer
var _empty_label: Label
var _mat_card: MaterialCard
var _selected := ""
var _card: WatercolorPanel
var _tween: Tween
var is_open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.25, 0.18, 0.12, 0.28)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = WatercolorPanel.new()
	_card.card = true
	_card.padding = Vector2(34, 22)
	_card.blob_seed = 3.3
	center.add_child(_card)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	_card.add_child(cols)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(560, 0)
	cols.add_child(vb)
	_mat_card = MaterialCard.new()
	_mat_card.width = 300.0
	_mat_card.stacked = true
	_mat_card.custom_minimum_size = Vector2(300, 0)
	cols.add_child(_mat_card)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "INVENTORY_TITLE"
	title.add_theme_font_size_override("font_size", 38)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(56, 56)
	close.pressed.connect(close_panel)
	close.add_to_group(&"touch_ui")
	head.add_child(close)
	vb.add_child(_rule())
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(_grid)
	_empty_label = Label.new()
	_empty_label.text = "MSG_INVENTORY_EMPTY"
	_empty_label.add_theme_font_size_override("font_size", 24)
	_empty_label.modulate.a = 0.7
	vb.add_child(_empty_label)
	var tools_title := Label.new()
	tools_title.text = "INVENTORY_TOOLS"
	tools_title.add_theme_font_size_override("font_size", 28)
	vb.add_child(tools_title)
	vb.add_child(_rule())
	_tools_box = VBoxContainer.new()
	_tools_box.add_theme_constant_override("separation", 6)
	vb.add_child(_tools_box)
	GameState.inventory.changed.connect(_on_changed)


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(Palette.EARTH, 0.35)
	r.custom_minimum_size = Vector2(0, 3)
	return r


func open_panel() -> void:
	is_open = true
	_rebuild()
	visible = true
	_animate(true)


func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	_animate(false)
	closed.emit()


func toggle() -> void:
	if is_open:
		close_panel()
	else:
		open_panel()


func _animate(show_it: bool) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_card.pivot_offset = _card.size * 0.5
	if show_it:
		modulate.a = 0.0
		_card.scale = Vector2(0.92, 0.92)
		_tween.tween_property(self, "modulate:a", 1.0, 0.2)
		_tween.tween_property(_card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, "modulate:a", 0.0, 0.16)
		_tween.chain().tween_callback(hide)


func _gui_input(event: InputEvent) -> void:
	# Kartın dışına dokunma/tıklama kapatır.
	if event is InputEventMouseButton and event.pressed or event is InputEventScreenTouch and event.pressed:
		if not _card.get_global_rect().has_point(event.position):
			close_panel()
			accept_event()


func _on_changed() -> void:
	if is_open:
		_rebuild()


func _rebuild() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for c in _tools_box.get_children():
		c.queue_free()
	var inv := GameState.inventory
	var ids := Materials.material_ids() + Materials.seed_ids()
	var shown := 0
	for id: String in ids:
		if inv.count(id) > 0:
			_grid.add_child(_item_cell(id, inv.count(id)))
			shown += 1
	var keys := inv.parts.keys()
	keys.sort()
	for key: String in keys:
		_grid.add_child(_item_cell(key, inv.part_count(key)))
		shown += 1
	_empty_label.visible = shown == 0
	if _selected == "" or (GameState.inventory.count(_selected) == 0 and GameState.inventory.part_count(_selected) == 0):
		_selected = ""
		for id: String in Materials.material_ids():
			if inv.count(id) > 0:
				_selected = id
				break
	_mat_card.show_item(_selected)
	for t in inv.tools:
		_tools_box.add_child(_tool_row(t))
	var slots := HBoxContainer.new()
	for i in inv.tool_slots_free():
		slots.add_child(_empty_slot())
	_tools_box.add_child(slots)


## Eşyaya dokununca/üstüne gelince sağda malzeme kartı açılır (neye yarar).
func _item_cell(id: String, n: int) -> Control:
	var b := Button.new()
	b.flat = true
	b.toggle_mode = true
	b.button_pressed = id == _selected
	b.custom_minimum_size = Vector2(128, 62)
	b.pressed.connect(_select.bind(id))
	b.mouse_entered.connect(_mat_card.show_item.bind(id))
	b.focus_entered.connect(_select.bind(id))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var ic := ItemIcon.new()
	ic.icon = id
	ic.custom_minimum_size = Vector2(56, 56)
	row.add_child(ic)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -8)
	var cnt := Label.new()
	cnt.text = "×%d" % n
	cnt.add_theme_font_size_override("font_size", 26)
	vb.add_child(cnt)
	var name_l := Label.new()
	name_l.text = Crafting.part_name(id) if ":" in id else tr(Materials.display_name(id))
	name_l.add_theme_font_size_override("font_size", 18)
	name_l.modulate.a = 0.8
	vb.add_child(name_l)
	row.add_child(vb)
	return b


func _select(id: String) -> void:
	_selected = id
	_mat_card.show_item(id)


func _tool_row(t: ToolItem) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var ic := ItemIcon.new()
	ic.icon = t.kind
	ic.custom_minimum_size = Vector2(56, 56)
	row.add_child(ic)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l := Label.new()
	name_l.text = t.display_name()
	name_l.add_theme_font_size_override("font_size", 24)
	vb.add_child(name_l)
	var bar := _bar(t.durability_ratio())
	vb.add_child(bar)
	row.add_child(vb)
	var stats := Label.new()
	stats.text = "%s %.1f · %s %.1f" % [tr("STAT_POWER"), t.power, tr("STAT_WEIGHT"), t.weight]
	if t.is_blunt():
		stats.text = tr("TOOL_BLUNT")
	stats.add_theme_font_size_override("font_size", 19)
	stats.modulate.a = 0.8
	row.add_child(stats)
	return row


func _bar(ratio: float) -> Control:
	var back := ColorRect.new()
	back.color = Color(Palette.EARTH, 0.22)
	back.custom_minimum_size = Vector2(220, 10)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fill := ColorRect.new()
	fill.color = Palette.MOSS if ratio > 0.3 else Palette.SUNSET
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	back.add_child(fill)
	return back


func _empty_slot() -> Control:
	var ic := ItemIcon.new()
	ic.icon = "plus"
	ic.dimmed = true
	ic.custom_minimum_size = Vector2(44, 40)
	return ic
