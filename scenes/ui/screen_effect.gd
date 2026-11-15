extends CanvasLayer
## Tam ekran suluboya katmanı (CanvasLayer + ColorRect + hint_screen_texture).
## Kalite: Düşük = kâğıt + renk kaydırma + kenar beyazlatma;
## Orta = + renk taşması + ıslak kenarlar; Yüksek = + Kuwahara + daha ince noise.

@onready var rect: ColorRect = $Paint

var _paper: NoiseTexture2D
var _blot: NoiseTexture2D


func _ready() -> void:
	_paper = _make_noise(512, 0.06, 5, 21, FastNoiseLite.TYPE_PERLIN)
	_blot = _make_noise(256, 0.006, 3, 22, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	var mat := rect.material as ShaderMaterial
	mat.set_shader_parameter("paper_noise", _paper)
	mat.set_shader_parameter("blot_noise", _blot)
	mat.set_shader_parameter("paper_color", Palette.PAPER)
	GameState.quality_changed.connect(apply_quality)
	apply_quality(GameState.quality)


func _make_noise(size: int, freq: float, octaves: int, seed_value: int, type: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t


func apply_quality(level: int) -> void:
	var mat := rect.material as ShaderMaterial
	mat.set_shader_parameter("bleed_enabled", level >= 1)
	mat.set_shader_parameter("wet_edges_enabled", level >= 1)
	mat.set_shader_parameter("kuwahara_enabled", level >= 2)
	var size: int = [256, 384, 512][level]
	if _paper.width != size:
		# Aynı görünüm, farklı çözünürlük: frekansı boyuta göre ölçekle
		_paper.noise.frequency = 0.06 * 512.0 / size
		_paper.width = size
		_paper.height = size
