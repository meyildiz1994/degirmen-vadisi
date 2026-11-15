class_name WatercolorMaterials
extends RefCounted
## Tüm suluboya materyallerinin tek kaynağı. Eklenen her yeni model malzemesini
## buradan almalı; böylece görüntü baştan sona tutarlı kalır ve kalite ayarı
## (kenar çizgisi, noise çözünürlüğü) tek yerden uygulanır.

const OBJECT_SHADER := preload("res://shaders/watercolor_object.gdshader")
const OUTLINE_SHADER := preload("res://shaders/watercolor_outline.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")

const NOISE_SIZES := [256, 384, 512]  ## Düşük / Orta / Yüksek

static var _paint_noise: NoiseTexture2D
static var _outline: ShaderMaterial
static var _cache := {}
static var _outlined: Array[ShaderMaterial] = []
static var _noise_users: Array[ShaderMaterial] = []
static var _quality := 2


## Boya dalgalanması, granülasyon ve kenar çizgisi kalınlığı için ortak noise.
static func paint_noise() -> NoiseTexture2D:
	if _paint_noise == null:
		var n := FastNoiseLite.new()
		n.seed = 42
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.012 * 512.0 / NOISE_SIZES[_quality]
		n.fractal_octaves = 4
		n.fractal_gain = 0.55
		_paint_noise = NoiseTexture2D.new()
		_paint_noise.width = NOISE_SIZES[_quality]
		_paint_noise.height = NOISE_SIZES[_quality]
		_paint_noise.seamless = true
		_paint_noise.generate_mipmaps = true
		_paint_noise.normalize = true
		_paint_noise.noise = n
	return _paint_noise


static func outline_material() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = OUTLINE_SHADER
		_outline.set_shader_parameter("ink_color", Palette.INK)
		_outline.set_shader_parameter("paint_noise", paint_noise())
		_outline.render_priority = -1
	return _outline


## Ortak nesne materyali. use_vertex_color=true ise renk mesh'ten gelir (MeshKit).
static func object(color: Color, use_vertex_color := false, outline := true) -> ShaderMaterial:
	var key := "obj_%s_%s_%s" % [color.to_html(), use_vertex_color, outline]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = OBJECT_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("use_vertex_color", use_vertex_color)
	m.set_shader_parameter("paint_noise", paint_noise())
	_noise_users.append(m)
	if outline:
		_outlined.append(m)
		m.next_pass = outline_material() if _outlines_on() else null
	_cache[key] = m
	return m


static func vertex_colored(outline := true) -> ShaderMaterial:
	return object(Color.WHITE, true, outline)


## Kenarı yumuşak, rüzgârda sallanan yaprak/çimen materyali.
static func foliage(ragged := true, grass := false) -> ShaderMaterial:
	var key := "fol_%s_%s" % [ragged, grass]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("paint_noise", paint_noise())
	m.set_shader_parameter("ragged_edges", ragged)
	m.set_shader_parameter("band_softness", 0.11)
	m.set_shader_parameter("band_high", 0.42)
	m.set_shader_parameter("raggedness", 1.1)
	m.set_shader_parameter("edge_cut", 1.5)
	if grass:
		m.set_shader_parameter("sway_height", 2.2)
		m.set_shader_parameter("wind_strength", 0.12)
		m.set_shader_parameter("up_normals", true)
		m.set_shader_parameter("color_variation", 0.12)
	_noise_users.append(m)
	_cache[key] = m
	return m


static func water() -> ShaderMaterial:
	if _cache.has("water"):
		return _cache["water"]
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("paint_noise", paint_noise())
	m.set_shader_parameter("paper_color", Palette.PAPER)
	m.render_priority = 1
	_cache["water"] = m
	return m


static func _outlines_on() -> bool:
	return _quality >= 1


## GameState.quality_changed sinyalinden çağrılır.
static func apply_quality(level: int) -> void:
	_quality = clampi(level, 0, 2)
	var tex := paint_noise()
	if tex.width != NOISE_SIZES[_quality]:
		(tex.noise as FastNoiseLite).frequency = 0.012 * 512.0 / NOISE_SIZES[_quality]
		tex.width = NOISE_SIZES[_quality]
		tex.height = NOISE_SIZES[_quality]
	var on := _outlines_on()
	for m in _outlined:
		m.next_pass = outline_material() if on else null
