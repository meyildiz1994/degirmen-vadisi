class_name MaterialCard
extends VBoxContainer
## Bir malzemenin kimlik kartı: ikon, ad, beş özellik çubuğu ve "neye yarar" notu.
## Atölyede seçilen/üzerine gelinen malzeme ve heybede seçilen eşya için gösterilir.
## Parça ("beam:oak") verilirse malzemesini anlatır.

const PROPS := ["hardness", "flexibility", "durability", "weight", "workability"]

var _icon: ItemIcon
var _name: Label
var _bars: BoxContainer
var _hint: Label
var width := 420.0
## Dar yerlerde (heybe) özellikler alt alta: ad solda, çubuk sağda.
var stacked := false


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_icon = ItemIcon.new()
	_icon.custom_minimum_size = Vector2(46, 46)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -4)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 21)
	text.add_child(_name)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.custom_minimum_size = Vector2(width - 56.0, 0)
	text.add_child(_hint)
	head.add_child(text)
	add_child(head)
	_bars = VBoxContainer.new() if stacked else HBoxContainer.new()
	_bars.add_theme_constant_override("separation", 4 if stacked else 6)
	add_child(_bars)
	visible = false


## id: malzeme, tohum ya da parça anahtarı. Boş ya da bilinmeyen → gizle.
func show_item(id: String) -> void:
	var mat := Crafting.part_material(id) if ":" in id else id
	if id == "" or not Materials.is_material(mat):
		visible = false
		return
	visible = true
	_icon.icon = id
	_name.text = Crafting.part_name(id) if ":" in id else tr(Materials.display_name(mat))
	for c in _bars.get_children():
		c.queue_free()
	for p: String in PROPS:
		_bars.add_child(_row(p, Materials.prop(mat, p)))
	_hint.text = tr("MAT_%s_HINT" % mat.to_upper())


func _row(prop: String, value: float) -> Control:
	if stacked:
		return _row_wide(prop, value)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	var l := Label.new()
	l.text = "%s %d" % [tr("PROP_" + prop.to_upper()), int(value)]
	l.add_theme_font_size_override("font_size", 14)
	l.clip_text = true
	l.custom_minimum_size = Vector2(width / 5.0 - 6.0, 0)
	vb.add_child(l)
	var bar := StatBar.new()
	bar.value = value
	bar.neutral = prop == "weight"
	bar.custom_minimum_size = Vector2(width / 5.0 - 6.0, 12)
	vb.add_child(bar)
	return vb


func _row_wide(prop: String, value: float) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = tr("PROP_" + prop.to_upper())
	l.add_theme_font_size_override("font_size", 17)
	l.custom_minimum_size = Vector2(110, 0)
	hb.add_child(l)
	var bar := StatBar.new()
	bar.value = value
	bar.neutral = prop == "weight"
	bar.custom_minimum_size = Vector2(width - 160.0, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(bar)
	var n := Label.new()
	n.text = str(int(value))
	n.add_theme_font_size_override("font_size", 17)
	hb.add_child(n)
	return hb
