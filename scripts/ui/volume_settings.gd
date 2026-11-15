class_name VolumeSettings
extends VBoxContainer
## Duraklatma menüsündeki ses ayarları: Müzik, Efekt, Ortam, Arayüz.
## Her satır en az 48 px yüksekliğinde (dokunmatik). Değerler SaveSystem'e yazılır.

const BUS_KEYS := {"Music": "VOL_MUSIC", "SFX": "VOL_SFX", "Ambience": "VOL_AMBIENCE", "UI": "VOL_UI"}
const ROW_H := 52.0

var sliders := {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "VOL_TITLE"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	for bus: String in AudioManager.BUSES:
		add_child(_row(bus))
	SaveSystem.loaded.connect(refresh)
	refresh()


func _row(bus: String) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	var l := Label.new()
	l.text = BUS_KEYS.get(bus, bus)
	l.add_theme_font_size_override("font_size", 22)
	vb.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(280, ROW_H)
	s.add_theme_icon_override("grabber", _knob(Palette.SUNSET))
	s.add_theme_icon_override("grabber_highlight", _knob(Palette.SUNSET_LIGHT))
	s.add_theme_stylebox_override("slider", _track(Color(Palette.EARTH, 0.3)))
	s.add_theme_stylebox_override("grabber_area", _track(Palette.MOSS))
	s.add_theme_stylebox_override("grabber_area_highlight", _track(Palette.MOSS_LIGHT))
	s.value_changed.connect(_on_changed.bind(bus))
	s.add_to_group(&"touch_ui")
	vb.add_child(s)
	sliders[bus] = s
	return vb


func refresh() -> void:
	var vol: Dictionary = SaveSystem.data.get("settings", {}).get("volume", {})
	for bus: String in sliders:
		sliders[bus].set_value_no_signal(float(vol.get(bus, 0.8)))


func _on_changed(v: float, bus: String) -> void:
	SaveSystem.set_volume_setting(bus, v)
	# Duyulabilir bir örnek: efekt ve arayüz çubuğunda kısa bir tık.
	if bus == "UI":
		AudioManager.play_ui("ui_click")
	elif bus == "SFX":
		AudioManager.play_sfx("sweet_hit")


## Yuvarlak, suluboya tonlu tutamak (40 px: parmakla rahat tutulur).
static func _knob(c: Color) -> ImageTexture:
	var n := 40
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var r := n * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if d <= r - 1.0:
				var edge := d > r - 4.5
				img.set_pixel(x, y, Palette.INK if edge else c)
			elif d <= r:
				img.set_pixel(x, y, Color(Palette.INK, r - d))
	return ImageTexture.create_from_image(img)


static func _track(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
