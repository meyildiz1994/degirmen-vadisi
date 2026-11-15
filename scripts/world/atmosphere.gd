extends Node3D
## Sabit, sıcak gün batımı: tek DirectionalLight3D, kodla üretilmiş gökyüzü,
## kâğıt tonunda sis ve sisin içinde açık renk lekelere dönüşen uzak tepeler.

const SKY_SHADER := preload("res://shaders/sky.gdshader")

var sun: DirectionalLight3D
var world_env: WorldEnvironment
var environment: Environment


func _ready() -> void:
	_build_sun()
	_build_environment()
	_build_distant_hills()
	GameState.quality_changed.connect(_on_quality_changed)
	_on_quality_changed(GameState.quality)


func _build_sun() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.89, 0.74)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 38.0
	sun.directional_shadow_fade_start = 0.8
	sun.light_angular_distance = 1.5
	# Batıdan, alçak açıyla gelen ışık
	sun.rotation_degrees = Vector3(-24.0, -118.0, 0.0)
	add_child(sun)


func _cloud_noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = 314
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.008
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	return t


func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("cloud_noise", _cloud_noise())
	sky_mat.set_shader_parameter("paper_color", Palette.PAPER)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Gölgeler siyah değil lavanta: ortam ışığı sabit lavanta rengi
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.66, 0.62, 0.82)
	environment.ambient_light_energy = 0.74
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	# Kâğıt tonunda derinlik sisi: uzaklar kâğıda solar
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Palette.PAPER.lerp(Palette.SUNSET_LIGHT, 0.15)
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.15
	environment.fog_density = 1.0
	environment.fog_depth_begin = 18.0
	environment.fog_depth_end = 95.0
	environment.fog_depth_curve = 1.6
	environment.fog_sky_affect = 0.0
	environment.adjustment_enabled = false
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)


## Oynanabilir alanın dışında halka şeklinde yumuşak tepeler; sis onları lekeye çevirir.
func _build_distant_hills() -> void:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var colors := [Palette.MOSS_LIGHT, Palette.LAVENDER, Palette.MOSS, Palette.SKY.lerp(Palette.LAVENDER, 0.5)]
	for ring in 2:
		var count := 14 + ring * 6
		var dist := 48.0 + ring * 28.0
		for i in count:
			var a := TAU * i / count + rng.randf_range(-0.12, 0.12)
			var r := rng.randf_range(14.0, 22.0) * (1.0 + ring * 0.6)
			var pos := Vector3(cos(a) * dist, -r * 0.55 + ring * 2.0, sin(a) * dist)
			var sq := Vector3(1.0, rng.randf_range(0.55, 0.85), 1.0)
			var c: Color = colors[(i + ring) % colors.size()]
			if ring == 1:
				c = c.lerp(Palette.LAVENDER, 0.5).lerp(Palette.PAPER, 0.3)
			kit.sphere(pos, r, c, sq, 14)
	var mi := MeshInstance3D.new()
	mi.name = "DistantHills"
	mi.mesh = kit.commit()
	mi.material_override = WatercolorMaterials.vertex_colored(false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _on_quality_changed(level: int) -> void:
	# Düşük: tek bölmeli ortografik gölge; Yüksek: 2 bölmeli PSSM
	# Düşük: 1024 atlas + kısa mesafe; Yüksek: 2048 atlas. İkisi de 2 bölmeli PSSM (az draw call).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 26.0 if level == 0 else 40.0
	sun.shadow_normal_bias = 2.4 if level == 0 else 1.6
	RenderingServer.directional_shadow_atlas_set_size(1024 if level == 0 else 2048, true)
