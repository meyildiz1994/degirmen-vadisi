class_name GatherFx
extends Node3D
## Vuruş geri bildirimi için suluboya parçacıklar: yonga, yaprak, toz, kıvılcım.
## Hepsi CPUParticles3D (mobilde ucuz), havuzdan yeniden kullanılır.
## Doku kodla üretilir: kenarı koyulaşan, düzensiz bir boya lekesi.

const POOL := 3

## tür -> [renkler, adet, hız, yerçekimi, boyut, ömür, yaprak mı]
var KINDS := {
	"wood":    [[Palette.SAND, Palette.WOOD, Palette.EARTH_LIGHT], 10, 3.2, 7.0, 0.11, 0.7, false],
	"leaf":    [[Palette.MOSS_LIGHT, Palette.MOSS, Palette.SUNSET_LIGHT], 9, 2.0, 1.6, 0.15, 1.3, true],
	"stone":   [[Palette.STONE, Palette.STONE_DARK, Palette.PAPER], 11, 3.6, 9.0, 0.09, 0.6, false],
	"dust":    [[Palette.EARTH_LIGHT, Palette.SAND, Palette.PAPER], 7, 1.2, -0.4, 0.26, 0.9, false],
	"copper":  [[Palette.COPPER, Palette.SUNSET, Palette.COPPER_PATINA], 11, 3.6, 9.0, 0.09, 0.6, false],
	"iron":    [[Palette.IRON, Palette.STONE_DARK, Palette.SUNSET], 11, 3.6, 9.0, 0.09, 0.6, false],
	"clay":    [[Palette.CLAY, Palette.EARTH, Palette.SUNSET_LIGHT], 8, 2.0, 6.0, 0.12, 0.7, false],
	"ink":     [[Color(0.10, 0.14, 0.18), Color(0.22, 0.34, 0.40), Color(0.16, 0.24, 0.30)], 14, 3.4, 7.5, 0.14, 0.75, false],
	"sparkle": [[Palette.SUNSET_LIGHT, Color(1.0, 0.95, 0.7), Palette.PAPER], 14, 2.6, -0.8, 0.12, 0.9, false],
}

var _pools := {}
var _next := {}
var _blob_tex: ImageTexture
var _leaf_tex: ImageTexture


func _ready() -> void:
	top_level = true
	_blob_tex = _make_texture(false)
	_leaf_tex = _make_texture(true)
	for kind in KINDS:
		var list: Array[CPUParticles3D] = []
		for i in POOL:
			list.append(_make_emitter(kind))
		_pools[kind] = list
		_next[kind] = 0


## Bir patlama. dir: parçacıkların ana yönü (vurulan yüzeyden dışarı).
func burst(kind: String, pos: Vector3, dir := Vector3.UP, strength := 1.0) -> void:
	if not _pools.has(kind):
		kind = "dust"
	var list: Array = _pools[kind]
	var e: CPUParticles3D = list[_next[kind]]
	_next[kind] = (_next[kind] + 1) % list.size()
	e.global_position = pos
	e.direction = (dir + Vector3.UP * 0.6).normalized()
	var base_amount: int = KINDS[kind][1]
	e.amount = maxi(2, int(base_amount * strength))
	e.initial_velocity_max = KINDS[kind][2] * (1.0 + 0.25 * (strength - 1.0))
	e.restart()


## Kaynağın türüne göre vuruş/bitiş patlaması.
func hit(fx_kind: String, pos: Vector3, dir: Vector3, sweet: bool) -> void:
	var s := 1.8 if sweet else 1.0
	burst(fx_kind, pos, dir, s)
	if fx_kind == "wood":
		burst("leaf", pos + Vector3(0, 1.6, 0), Vector3.UP, 0.6 * s)
	elif fx_kind in ["stone", "copper", "iron"]:
		burst("dust", pos, dir, 0.7 * s)
	if sweet:
		burst("sparkle", pos, dir, 1.0)


func _make_emitter(kind: String) -> CPUParticles3D:
	var cfg: Array = KINDS[kind]
	var e := CPUParticles3D.new()
	e.name = "Fx_" + kind
	e.emitting = false
	e.one_shot = true
	e.explosiveness = 0.92
	e.amount = cfg[1]
	e.lifetime = cfg[5]
	e.local_coords = false
	e.spread = 55.0
	e.initial_velocity_min = cfg[2] * 0.45
	e.initial_velocity_max = cfg[2]
	e.gravity = Vector3(0, -cfg[3], 0)
	e.damping_min = 0.5
	e.damping_max = 2.0
	e.angle_min = 0.0
	e.angle_max = 360.0
	e.angular_velocity_min = -180.0 if cfg[6] else -40.0
	e.angular_velocity_max = 180.0 if cfg[6] else 40.0
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	e.scale_amount_curve = curve
	var grad := Gradient.new()
	var cols: Array = cfg[0]
	grad.set_color(0, cols[0])
	grad.set_color(1, Color(cols[1], 0.0))
	grad.add_point(0.5, cols[2])
	e.color_initial_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * cfg[4]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _leaf_tex if cfg[6] else _blob_tex
	mat.disable_receive_shadows = true
	quad.material = mat
	e.mesh = quad
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(e)
	return e


## Düzensiz kenarlı, kenarı koyulaşan boya lekesi (veya yaprak) dokusu.
func _make_texture(leaf: bool) -> ImageTexture:
	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 21 if leaf else 9
	n.frequency = 0.09
	for y in size:
		for x in size:
			var u := (x + 0.5) / size * 2.0 - 1.0
			var v := (y + 0.5) / size * 2.0 - 1.0
			var d: float
			if leaf:
				d = sqrt(u * u * 3.2 + v * v * 0.9)   # uzun yaprak
			else:
				d = sqrt(u * u + v * v)
			d += n.get_noise_2d(x, y) * 0.22
			var a := 1.0 - smoothstep(0.72, 0.92, d)
			var rim := smoothstep(0.5, 0.85, d) * a
			var shade := 1.0 - rim * 0.28
			img.set_pixel(x, y, Color(shade, shade, shade, a * (0.78 + rim * 0.22)))
	return ImageTexture.create_from_image(img)
