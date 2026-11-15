class_name ModalPanel
extends Control
## Atölye ve onarım panellerinin ortak tabanı: karartılmış arka plan, ortada suluboya kart,
## başlık + kapat düğmesi, açılış/kapanış animasyonu. Kart dışına dokunmak, Esc/B/Start kapatır.

signal closed

var is_open := false
## Eğitimde açık: işaretçi sıradaki adımı (kalıp → yuva → malzeme → düğme) gösterir.
var guide_enabled := false
var guide: GuidePointer
var _card: WatercolorPanel
var _title: Label
var _panel_tween: Tween


## Kartı kurar ve içerik için dikey kutuyu döndürür.
func _build_card(title_key: String, blob_seed: float) -> VBoxContainer:
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
	_card.blob_seed = blob_seed
	center.add_child(_card)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_card.add_child(root)
	root.add_child(_header(title_key))
	root.add_child(_rule())
	guide = GuidePointer.new()
	guide.name = "Guide"
	add_child(guide)
	return root


## Alt sınıf: yol göstericinin şu an işaret etmesi gereken kontrol (yoksa null).
func _guide_target() -> Control:
	return null


func _process(_delta: float) -> void:
	if guide != null:
		guide.target = _guide_target() if is_open and guide_enabled else null


func _header(title_key: String) -> Control:
	var head := HBoxContainer.new()
	_title = Label.new()
	_title.text = title_key
	_title.add_theme_font_size_override("font_size", 36)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
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


func _wrap_label(text: String, font_size: int, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(width, 0)
	return l


func _show_panel() -> void:
	is_open = true
	visible = true
	_animate(true)


func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	_animate(false)
	_on_closing()
	closed.emit()


## Alt sınıflar kapanırken ek iş yapabilir (müzik vb.).
func _on_closing() -> void:
	pass


func _animate(show_it: bool) -> void:
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	_panel_tween = create_tween().set_parallel(true)
	_card.pivot_offset = _card.size * 0.5
	if show_it:
		modulate.a = 0.0
		_card.scale = Vector2(0.94, 0.94)
		_panel_tween.tween_property(self, "modulate:a", 1.0, 0.2)
		_panel_tween.tween_property(_card, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_panel_tween.tween_property(self, "modulate:a", 0.0, 0.16)
		_panel_tween.chain().tween_callback(hide)


func _pop(c: Control) -> void:
	if c == null:
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(1.1, 1.1)
	create_tween().tween_property(c, "scale", Vector2.ONE, 0.18)


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		if not _card.get_global_rect().has_point(event.position):
			close_panel()
			accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		close_panel()
		get_viewport().set_input_as_handled()


## Değer çubuğu satırı: ad, sayı ve suluboya çubuk. threshold ≥ 0 ise istenen çizgisi çizilir.
func _stat_row(name_text: String, value: float, neutral := false, threshold := -1.0, width := 280.0) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	var n := Label.new()
	n.text = name_text
	n.add_theme_font_size_override("font_size", 21)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	var v := Label.new()
	v.text = ("%.1f" % value) if threshold < 0.0 else ("%.1f / %s" % [value, _num(threshold)])
	v.add_theme_font_size_override("font_size", 21)
	top.add_child(v)
	vb.add_child(top)
	var bar := StatBar.new()
	bar.value = value
	bar.neutral = neutral
	bar.threshold = threshold
	bar.custom_minimum_size = Vector2(width, 16)
	vb.add_child(bar)
	return vb


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
