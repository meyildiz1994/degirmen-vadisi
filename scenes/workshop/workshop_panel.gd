class_name WorkshopPanel
extends Control
## Atölye paneli: solda kalıplar, ortada yuvalar ve yuvaya konabilecek malzemeler,
## sağda tahmini istatistik çubukları ve "Üret". Sabit tarif yok; oyuncu dener, görür.
## Kod ile kurulur; dokunmatik hedefler ≥ 56 px, gamepad/klavye odak gezintisi çalışır.

signal closed
signal crafted(mold_id: String, result: Dictionary)

const BAR_W := 190.0

var is_open := false
var mold_id := "handle"
var choices: Array = []
var active_slot := 0
var highlight_mold := ""       ## eğitim: nabız gibi atan kalıp

var _card: WatercolorPanel
var _mold_list: VBoxContainer
var _mold_buttons := {}
var _mold_title: Label
var _slot_row: HBoxContainer
var _option_title: Label
var _option_grid: GridContainer
var _stats_box: VBoxContainer
var _hits_label: Label
var _craft_button: Button
var _result_label: Label
var _tween: Tween
var _pulse := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.25, 0.18, 0.12, 0.32)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = WatercolorPanel.new()
	_card.card = true
	_card.padding = Vector2(28, 18)
	_card.blob_seed = 6.1
	center.add_child(_card)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_card.add_child(root)
	root.add_child(_header())
	root.add_child(_rule())
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	root.add_child(cols)
	cols.add_child(_left_column())
	cols.add_child(_vrule())
	cols.add_child(_center_column())
	cols.add_child(_vrule())
	cols.add_child(_right_column())
	GameState.inventory.changed.connect(func(): if is_open: _refresh())


# --- Yapı ---------------------------------------------------------------------------
func _header() -> Control:
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "NAME_WORKSHOP"
	title.add_theme_font_size_override("font_size", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(56, 56)
	close.pressed.connect(close_panel)
	close.focus_mode = Control.FOCUS_NONE
	head.add_child(close)
	return head


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(Palette.EARTH, 0.35)
	r.custom_minimum_size = Vector2(0, 3)
	return r


func _vrule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(Palette.EARTH, 0.25)
	r.custom_minimum_size = Vector2(3, 0)
	return r


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.modulate = Color(1, 1, 1, 0.85)
	return l


func _left_column() -> Control:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(250, 0)
	vb.add_child(_section("WORKSHOP_MOLDS"))
	_mold_list = VBoxContainer.new()
	_mold_list.add_theme_constant_override("separation", 4)
	vb.add_child(_mold_list)
	for id: String in Crafting.mold_ids():
		var b := Button.new()
		b.custom_minimum_size = Vector2(240, 58)
		b.toggle_mode = true
		b.pressed.connect(select_mold.bind(id))
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8.0
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		var ic := ItemIcon.new()
		ic.icon = str(Crafting.mold(id).get("icon", "lump"))
		ic.custom_minimum_size = Vector2(50, 50)
		row.add_child(ic)
		var l := Label.new()
		l.text = str(Crafting.mold(id).get("name", id))
		l.add_theme_font_size_override("font_size", 25)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		b.add_child(row)
		_mold_list.add_child(b)
		_mold_buttons[id] = b
	return vb


func _center_column() -> Control:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(430, 0)
	vb.add_theme_constant_override("separation", 10)
	_mold_title = Label.new()
	_mold_title.add_theme_font_size_override("font_size", 30)
	vb.add_child(_mold_title)
	_slot_row = HBoxContainer.new()
	_slot_row.add_theme_constant_override("separation", 14)
	vb.add_child(_slot_row)
	_option_title = _section("")
	vb.add_child(_option_title)
	_option_grid = GridContainer.new()
	_option_grid.columns = 3
	_option_grid.add_theme_constant_override("h_separation", 8)
	_option_grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(_option_grid)
	return vb


func _right_column() -> Control:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(300, 0)
	vb.add_theme_constant_override("separation", 6)
	vb.add_child(_section("WORKSHOP_PREDICTION"))
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 4)
	_stats_box.custom_minimum_size = Vector2(0, 200)
	vb.add_child(_stats_box)
	_hits_label = Label.new()
	_hits_label.add_theme_font_size_override("font_size", 20)
	_hits_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hits_label.custom_minimum_size = Vector2(290, 0)
	vb.add_child(_hits_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 22)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_result_label.custom_minimum_size = Vector2(290, 0)
	_result_label.modulate.a = 0.0
	vb.add_child(_result_label)
	_craft_button = Button.new()
	_craft_button.text = "WORKSHOP_CRAFT"
	_craft_button.custom_minimum_size = Vector2(290, 68)
	_craft_button.add_theme_font_size_override("font_size", 30)
	_craft_button.pressed.connect(_on_craft)
	vb.add_child(_craft_button)
	return vb


# --- Açma / kapama --------------------------------------------------------------------
func open_panel() -> void:
	is_open = true
	visible = true
	select_mold(mold_id if highlight_mold == "" else highlight_mold)
	_animate(true)
	AudioManager.play_music("music_workshop")
	(_mold_buttons[mold_id] as Button).grab_focus.call_deferred()


func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	_animate(false)
	AudioManager.play_music("music_explore")
	closed.emit()


func _animate(show_it: bool) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_card.pivot_offset = _card.size * 0.5
	if show_it:
		modulate.a = 0.0
		_card.scale = Vector2(0.94, 0.94)
		_tween.tween_property(self, "modulate:a", 1.0, 0.2)
		_tween.tween_property(_card, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, "modulate:a", 0.0, 0.16)
		_tween.chain().tween_callback(hide)


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		if not _card.get_global_rect().has_point(event.position):
			close_panel()
			accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		close_panel()
		get_viewport().set_input_as_handled()


# --- Seçimler -------------------------------------------------------------------------
func select_mold(id: String) -> void:
	if id != mold_id or choices.size() != Crafting.slots(id).size():
		choices = Crafting.empty_choices(id)
	mold_id = id
	_autofill()
	active_slot = _first_empty_slot()
	for k in _mold_buttons:
		(_mold_buttons[k] as Button).button_pressed = k == id
	AudioManager.play_ui("ui_click")
	_refresh()


## Tek seçenekli yuvaları ve son kullanılanları kendiliğinden doldur (mobilde az dokunuş).
func _autofill() -> void:
	var inv := GameState.inventory
	for i in choices.size():
		if str(choices[i]) != "" and Crafting.option_available(mold_id, i, choices[i], inv):
			continue
		choices[i] = ""
		var avail := []
		for o in Crafting.slot_options(mold_id, i, inv):
			if Crafting.option_available(mold_id, i, o, inv):
				avail.append(o)
		if avail.size() == 1:
			choices[i] = avail[0]


func _first_empty_slot() -> int:
	for i in choices.size():
		if str(choices[i]) == "":
			return i
	return 0


func select_slot(i: int) -> void:
	active_slot = i
	AudioManager.play_ui("ui_click")
	_refresh()


func choose(option: String) -> void:
	choices[active_slot] = option
	AudioManager.play_sfx("slot_place")
	var nxt := _first_empty_slot()
	if str(choices[nxt]) == "":
		active_slot = nxt
	_refresh()
	_pop(_slot_row.get_child(active_slot) if active_slot < _slot_row.get_child_count() else null)


func _pop(c: Control) -> void:
	if c == null:
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(1.1, 1.1)
	create_tween().tween_property(c, "scale", Vector2.ONE, 0.18)


# --- Görünüm --------------------------------------------------------------------------
func _refresh() -> void:
	_mold_title.text = str(Crafting.mold(mold_id).get("name", mold_id))
	_build_slots()
	_build_options()
	_build_stats()
	_craft_button.disabled = not Crafting.can_craft(GameState.inventory, mold_id, choices)


func _build_slots() -> void:
	for c in _slot_row.get_children():
		c.queue_free()
	var defs := Crafting.slots(mold_id)
	for i in defs.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 150)
		b.toggle_mode = true
		b.button_pressed = i == active_slot
		b.pressed.connect(select_slot.bind(i))
		var vb := VBoxContainer.new()
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := ItemIcon.new()
		var chosen := str(choices[i])
		ic.icon = chosen if chosen != "" else "plus"
		ic.dimmed = chosen == ""
		ic.custom_minimum_size = Vector2(72, 72)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(ic)
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 20)
		l.text = "%s ×%d" % [tr(str(defs[i].get("name", ""))), Crafting.slot_amount(mold_id, i)]
		vb.add_child(l)
		b.add_child(vb)
		_slot_row.add_child(b)


func _build_options() -> void:
	for c in _option_grid.get_children():
		c.queue_free()
	var inv := GameState.inventory
	var opts := Crafting.slot_options(mold_id, active_slot, inv)
	var defs := Crafting.slots(mold_id)
	_option_title.text = "%s: %s" % [tr("WORKSHOP_CHOOSE"), tr(str(defs[active_slot].get("name", "")))]
	if opts.is_empty():
		var l := Label.new()
		l.text = "WORKSHOP_NEED_HANDLE"
		l.add_theme_font_size_override("font_size", 20)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size = Vector2(420, 0)
		_option_grid.add_child(l)
		return
	var need := Crafting.slot_amount(mold_id, active_slot)
	for o: String in opts:
		var have := inv.part_count(o) if ":" in o else inv.count(o)
		var b := Button.new()
		b.custom_minimum_size = Vector2(138, 62)
		b.toggle_mode = true
		b.button_pressed = str(choices[active_slot]) == o
		b.disabled = have < need
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "        %s\n        %d/%d" % [Crafting.part_name(o) if ":" in o else tr(Materials.display_name(o)), mini(have, 99), need]
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(choose.bind(o))
		var ic := ItemIcon.new()
		ic.icon = o
		ic.dimmed = have < need
		ic.position = Vector2(4, 6)
		ic.size = Vector2(48, 48)
		b.add_child(ic)
		_option_grid.add_child(b)


func _build_stats() -> void:
	for c in _stats_box.get_children():
		c.queue_free()
	var stats := Crafting.predict(mold_id, choices)
	_hits_label.text = ""
	if stats.is_empty():
		var l := Label.new()
		l.text = "WORKSHOP_FILL_SLOTS"
		l.add_theme_font_size_override("font_size", 20)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size = Vector2(290, 0)
		l.modulate.a = 0.75
		_stats_box.add_child(l)
		return
	for s: Dictionary in stats:
		_stats_box.add_child(_stat_row(tr(str(s["name"])), float(s["value"]), str(s["key"]) == "weight"))
	var hits := Crafting.preview_hits(mold_id, choices)
	var parts := []
	for r: String in hits:
		parts.append("%s: %d %s" % [tr(str(Materials.resource(r).get("name", r))), hits[r], tr("HITS")])
	_hits_label.text = "\n".join(parts)


## neutral: iyi/kötü yönü olmayan özellik (ağırlık) mavi çizilir, düşük değer uyarısı yok.
func _stat_row(name_text: String, value: float, neutral := false) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	var n := Label.new()
	n.text = name_text
	n.add_theme_font_size_override("font_size", 21)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	var v := Label.new()
	v.text = "%.1f" % value
	v.add_theme_font_size_override("font_size", 21)
	top.add_child(v)
	vb.add_child(top)
	var bar := StatBar.new()
	bar.value = value
	bar.neutral = neutral
	bar.custom_minimum_size = Vector2(BAR_W + 90.0, 16)
	vb.add_child(bar)
	return vb


func _on_craft() -> void:
	var result := Crafting.craft(GameState.inventory, mold_id, choices)
	if result.is_empty():
		AudioManager.play_sfx("craft_fail")
		return
	AudioManager.play_sfx("craft_success")
	PlatformServices.vibrate(40)
	var name_text: String = (result["tool"] as ToolItem).display_name() if result["kind"] == "tool" else Crafting.part_name(result["key"])
	_result_label.text = "%s: %s" % [tr("WORKSHOP_MADE"), name_text]
	var t := create_tween()
	_result_label.modulate.a = 1.0
	t.tween_interval(2.2)
	t.tween_property(_result_label, "modulate:a", 0.0, 0.6)
	_pop(_craft_button)
	crafted.emit(mold_id, result)
	_autofill()
	_refresh()


func _process(delta: float) -> void:
	if not is_open or highlight_mold == "" or not _mold_buttons.has(highlight_mold):
		return
	_pulse += delta * 4.0
	var b: Button = _mold_buttons[highlight_mold]
	b.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.25, 1.1, 0.75), 0.5 + 0.5 * sin(_pulse))
	for k in _mold_buttons:
		if k != highlight_mold:
			(_mold_buttons[k] as Button).modulate = Color.WHITE


func set_highlight(id: String) -> void:
	highlight_mold = id
	if id == "":
		for k in _mold_buttons:
			(_mold_buttons[k] as Button).modulate = Color.WHITE
