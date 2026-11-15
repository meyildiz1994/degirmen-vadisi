class_name IconHintCard
extends WatercolorPanel
## Metinsiz ipucu kartı: bir dizi ikon (isteğe bağlı sayaçla), örn.
## [dal 1/2] [taş 3/4] → [atölye] = [balta]. Eğitim ve "alet gerekli" uyarıları için.

var _row: HBoxContainer
var _tween: Tween
var _sequence: Array = []
var _flash_left := 0.0
var _persistent: Array = []


func _init() -> void:
	card = true
	padding = Vector2(20, 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	super._ready()
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	modulate.a = 0.0
	visible = false


## Kalıcı ipucu (eğitim adımı). Boş liste = gizle.
## Öğe biçimi: "icon" | ["icon", "1/2"] | ["icon", "", true(soluk)]
func set_persistent(items: Array) -> void:
	_persistent = items
	if _flash_left <= 0.0:
		_show(items)


## Kısa süreli uyarı; bitince kalıcı ipucuna döner.
func flash(items: Array, duration := 3.0) -> void:
	_flash_left = duration
	_show(items)


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_show(_persistent)


func _show(items: Array) -> void:
	if items == _sequence and visible:
		return
	_sequence = items.duplicate(true)
	for c in _row.get_children():
		c.queue_free()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if items.is_empty():
		_tween.tween_property(self, "modulate:a", 0.0, 0.3)
		_tween.tween_callback(hide)
		return
	for it in items:
		_row.add_child(_make_item(it))
	visible = true
	_tween.tween_property(self, "modulate:a", 1.0, 0.25)


func _make_item(it) -> Control:
	var icon_id: String = it if typeof(it) == TYPE_STRING else str(it[0])
	var label: String = "" if typeof(it) == TYPE_STRING or it.size() < 2 else str(it[1])
	var dim: bool = typeof(it) != TYPE_STRING and it.size() > 2 and bool(it[2])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := ItemIcon.new()
	ic.icon = icon_id
	ic.dimmed = dim
	var small := icon_id in ["arrow", "plus"]
	ic.custom_minimum_size = Vector2(34, 56) if small else Vector2(56, 56)
	box.add_child(ic)
	if label != "":
		var l := Label.new()
		l.text = label
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 20)
		box.add_child(l)
	return box
