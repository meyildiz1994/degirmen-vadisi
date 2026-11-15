class_name RepairPanel
extends ModalPanel
## Onarım paneli: solda onarım yerleri, ortada heybedeki uygun parçalar,
## sağda istenen özellikler (eşik çizgisi) ve seçilen parçanın değerleri.
## Eşiği tutmayan parça da takılabilir; panel bunu turuncu çubukla ve kısa bir notla söyler.

signal installed(site: RepairSite, slot_id: String)

const BAR_W := 280.0

var site: RepairSite
var slot_id := ""
var choice := ""

var _slot_list: VBoxContainer
var _slot_buttons := {}
var _parts_title: Label
var _parts_box: VBoxContainer
var _needs_box: VBoxContainer
var _note: Label
var _install_button: Button


func _ready() -> void:
	var root := _build_card("NAME_BRIDGE", 3.7)
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
func _left_column() -> Control:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(260, 0)
	vb.add_child(_section("REPAIR_POINTS"))
	_slot_list = VBoxContainer.new()
	_slot_list.add_theme_constant_override("separation", 6)
	vb.add_child(_slot_list)
	return vb


func _center_column() -> Control:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(430, 330)
	vb.add_theme_constant_override("separation", 10)
	_parts_title = _section("REPAIR_PARTS")
	vb.add_child(_parts_title)
	_parts_box = VBoxContainer.new()
	_parts_box.add_theme_constant_override("separation", 8)
	vb.add_child(_parts_box)
	return vb


func _right_column() -> Control:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(300, 0)
	vb.add_theme_constant_override("separation", 8)
	vb.add_child(_section("REPAIR_NEEDS"))
	_needs_box = VBoxContainer.new()
	_needs_box.add_theme_constant_override("separation", 6)
	vb.add_child(_needs_box)
	_note = _wrap_label("", 20, 290)
	vb.add_child(_note)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)
	_install_button = Button.new()
	_install_button.text = "REPAIR_INSTALL"
	_install_button.custom_minimum_size = Vector2(290, 68)
	_install_button.add_theme_font_size_override("font_size", 30)
	_install_button.pressed.connect(_on_install)
	vb.add_child(_install_button)
	return vb


# --- Açma ------------------------------------------------------------------------------
func open_for(s: RepairSite) -> void:
	site = s
	_title.text = s.display_name_key()
	_build_slot_buttons()
	select_slot(_first_open_slot())
	_show_panel()
	if _slot_buttons.has(slot_id):
		(_slot_buttons[slot_id] as Button).grab_focus.call_deferred()


func _first_open_slot() -> String:
	for d: Dictionary in Repair.slots(site.site_id):
		if not Repair.is_filled(site.state, d["id"]):
			return d["id"]
	return str(Repair.slots(site.site_id)[0]["id"])


func select_slot(id: String) -> void:
	slot_id = id
	var cands := Repair.candidates(site.site_id, id, GameState.inventory)
	choice = "" if cands.is_empty() or Repair.is_filled(site.state, id) else str(cands[0])
	AudioManager.play_ui("ui_click")
	_refresh()


func choose(key: String) -> void:
	choice = key
	AudioManager.play_ui("ui_click")
	_refresh()


# --- Görünüm --------------------------------------------------------------------------
func _refresh() -> void:
	if site == null:
		return
	_refresh_slot_buttons()
	_build_parts()
	_build_needs()


func _build_slot_buttons() -> void:
	for c in _slot_list.get_children():
		c.queue_free()
	_slot_buttons.clear()
	for d: Dictionary in Repair.slots(site.site_id):
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 70)
		b.toggle_mode = true
		b.pressed.connect(select_slot.bind(str(d["id"])))
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8.0
		row.offset_right = -8.0
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var ic := ItemIcon.new()
		ic.name = "Icon"
		ic.custom_minimum_size = Vector2(54, 54)
		row.add_child(ic)
		var l := Label.new()
		l.text = str(d["name"])
		l.add_theme_font_size_override("font_size", 23)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var mark := ItemIcon.new()
		mark.name = "Mark"
		mark.custom_minimum_size = Vector2(36, 54)
		row.add_child(mark)
		b.add_child(row)
		_slot_list.add_child(b)
		_slot_buttons[d["id"]] = b


func _refresh_slot_buttons() -> void:
	for d: Dictionary in Repair.slots(site.site_id):
		var id: String = d["id"]
		var b: Button = _slot_buttons.get(id)
		if b == null:
			continue
		b.button_pressed = id == slot_id
		var st := Repair.slot_state(site.state, id)
		var ic: ItemIcon = b.find_child("Icon", true, false)
		var mark: ItemIcon = b.find_child("Mark", true, false)
		ic.icon = str(st["part"]) if st.has("part") else str(Crafting.mold(d["mold"]).get("icon", "lump"))
		ic.dimmed = not st.has("part")
		mark.icon = "check" if st.has("part") else ("crack" if st.has("cracked") else "plus")
		mark.dimmed = not st.has("part") and not st.has("cracked")


func _build_parts() -> void:
	for c in _parts_box.get_children():
		c.queue_free()
	var st := Repair.slot_state(site.state, slot_id)
	if st.has("part"):
		_parts_title.text = "REPAIR_INSTALLED"
		_parts_box.add_child(_part_card(str(st["part"])))
		return
	_parts_title.text = "REPAIR_PARTS"
	var cands := Repair.candidates(site.site_id, slot_id, GameState.inventory)
	if cands.is_empty():
		_parts_box.add_child(_wrap_label("REPAIR_NO_PARTS", 21, 420))
		var mold_id := str(Repair.slot_def(site.site_id, slot_id)["mold"])
		var hint := HBoxContainer.new()
		for icon_id: String in ["workshop", "arrow", str(Crafting.mold(mold_id).get("icon", "lump"))]:
			var ic := ItemIcon.new()
			ic.icon = icon_id
			ic.custom_minimum_size = Vector2(34, 64) if icon_id == "arrow" else Vector2(64, 64)
			hint.add_child(ic)
		_parts_box.add_child(hint)
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_parts_box.add_child(grid)
	var n := Repair.needs(site.site_id, slot_id)
	for key: String in cands:
		var b := Button.new()
		b.custom_minimum_size = Vector2(138, 62)
		b.toggle_mode = true
		b.button_pressed = key == choice
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "        %s\n        ×%d" % [tr(Materials.display_name(Crafting.part_material(key))), mini(GameState.inventory.part_count(key), 99)]
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(choose.bind(key))
		var ic := ItemIcon.new()
		ic.icon = key
		ic.position = Vector2(4, 6)
		ic.size = Vector2(48, 48)
		b.add_child(ic)
		if not Repair.meets(key, n):
			b.modulate = Color(1.0, 0.86, 0.74)
		grid.add_child(b)


func _part_card(key: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var ic := ItemIcon.new()
	ic.icon = key
	ic.custom_minimum_size = Vector2(96, 96)
	hb.add_child(ic)
	var l := Label.new()
	l.text = Crafting.part_name(key)
	l.add_theme_font_size_override("font_size", 26)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	return hb


## İstenen özellikler: çubuk seçilen (ya da takılı) parçanın değerini, kesikli çizgi eşiği gösterir.
func _build_needs() -> void:
	for c in _needs_box.get_children():
		c.queue_free()
	var def := Repair.slot_def(site.site_id, slot_id)
	var n: Dictionary = def.get("needs", {})
	var st := Repair.slot_state(site.state, slot_id)
	var key := str(st["part"]) if st.has("part") else choice
	var stats := Crafting.stats_for_part(key) if key != "" else []
	var stat_defs: Dictionary = Crafting.mold(def["mold"]).get("stats", {})
	for k: String in n:
		var name_key := str(stat_defs.get(k, {}).get("name", k))
		_needs_box.add_child(_stat_row(tr(name_key), Crafting.stat_value(stats, k), false, float(n[k]), BAR_W))
	_note.modulate = Color.WHITE
	if st.has("part"):
		_note.text = ""
	elif key == "":
		_note.text = "REPAIR_CRACKED" if st.has("cracked") else "REPAIR_PICK_PART"
		if st.has("cracked"):
			_note.modulate = Palette.SUNSET.darkened(0.25)
	elif Repair.meets(key, n):
		_note.text = "REPAIR_GOOD"
		_note.modulate = Palette.MOSS_DARK
	else:
		_note.text = "REPAIR_WEAK_WARNING"
		_note.modulate = Palette.SUNSET.darkened(0.25)
	_install_button.disabled = st.has("part") or key == ""
	_install_button.text = "REPAIR_INSTALLED" if st.has("part") else "REPAIR_INSTALL"


func _on_install() -> void:
	if choice == "" or not site.install(slot_id, choice):
		AudioManager.play_sfx("craft_fail")
		return
	PlatformServices.vibrate(35)
	installed.emit(site, slot_id)
	_pop(_slot_buttons.get(slot_id))
	if site.is_complete():
		_refresh()
		get_tree().create_timer(0.6).timeout.connect(close_panel)
		return
	select_slot(_first_open_slot())
