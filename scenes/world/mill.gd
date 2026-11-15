class_name Mill
extends Node3D
## Bozuk su değirmeni: taş gövde, çökmüş çatı. Onarılabilir iki parça kodla eklenir:
## dere tarafındaki yıkık duvar (MillWall) ve çark (MillWheel). Pencerede, değirmen
## çalışınca yanan sıcak bir ışık var (final).

@onready var interactable: Interactable = $Interactable

var wall: MillWall
var wheel: MillWheel
var window_glow: MeshInstance3D

const WALL_T := 0.45
const SIZE := Vector3(4.4, 3.0, 4.0)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 31
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _build_body()
	body.material_override = WatercolorMaterials.vertex_colored(true)
	add_child(body)
	var sb := StaticBody3D.new()
	sb.set_meta("surface", "stone")
	sb.add_child(_shape(body.mesh))
	add_child(sb)
	wall = MillWall.new()
	wall.name = "Wall"
	wall.size = SIZE
	add_child(wall)
	wheel = MillWheel.new()
	wheel.name = "Wheel"
	wheel.position = wheel_local_center()
	add_child(wheel)
	_build_window_glow()


## Pencere ışığı: başta kapalı; set_glow(1) ile yanar.
func _build_window_glow() -> void:
	window_glow = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.6, 0.05)
	window_glow.mesh = bm
	window_glow.position = Vector3(0.6, 1.9, SIZE.z * 0.5 + 0.25)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(Palette.SUNSET_LIGHT.lightened(0.3), 0.0)
	window_glow.material_override = m
	window_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(window_glow)
	var light := OmniLight3D.new()
	light.name = "WindowLight"
	light.light_color = Palette.SUNSET_LIGHT
	light.light_energy = 0.0
	light.omni_range = 2.6
	light.position = window_glow.position + Vector3(0, 0, 1.1)
	add_child(light)


func set_glow(v: float) -> void:
	(window_glow.material_override as StandardMaterial3D).albedo_color.a = v
	($WindowLight as OmniLight3D).light_energy = v * 0.45


func _shape(mesh: Mesh) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	return cs


func _stone() -> Color:
	return Palette.STONE.lerp(Palette.STONE_DARK, _rng.randf() * 0.6).lerp(Palette.SAND, _rng.randf() * 0.2)


## Taş duvar: üst üste dizilmiş, rengi değişen bloklar. top_profile ile yıkık üst kenar.
func _stone_wall(kit: MeshKit, start: Vector3, along: Vector3, length: float, height: float, broken := false) -> void:
	var rows := int(height / 0.5)
	var dir := along.normalized()
	var yaw := atan2(dir.x, dir.z)
	for r in rows:
		var x := 0.0
		var offset := 0.35 if r % 2 == 1 else 0.0
		var first := true
		while x < length - 0.01:
			var w := minf(_rng.randf_range(0.6, 1.1) - (offset if first else 0.0), length - x)
			w = maxf(w, 0.2)
			first = false
			var col_h := height
			if broken:
				# Yıkık kenar: ortaya doğru alçalan, dişli üst profil
				var t := (x + w * 0.5) / length
				col_h = height * (0.35 + 0.65 * absf(t - 0.55) * 1.6) + _rng.randf_range(-0.3, 0.2)
			if (r + 1) * 0.5 <= col_h:
				var center := start + dir * (x + w * 0.5) + Vector3(0, r * 0.5 + 0.25, 0)
				kit.box(center, Vector3(WALL_T + _rng.randf_range(-0.03, 0.05), 0.48, w - 0.04), _stone(), Vector3(0, yaw, 0))
			x += w


func _build_body() -> ArrayMesh:
	var kit := MeshKit.new()
	var hx := SIZE.x * 0.5
	var hz := SIZE.z * 0.5
	# Temel
	kit.box(Vector3(0, -0.15, 0), Vector3(SIZE.x + 0.5, 0.5, SIZE.z + 0.5), Palette.STONE_DARK)
	# Duvarlar: kuzey, güney, batı tam; doğu (dere tarafı) yarım ve yıkık
	_stone_wall(kit, Vector3(-hx, 0.1, -hz), Vector3.RIGHT, SIZE.x, SIZE.y)
	_stone_wall(kit, Vector3(-hx, 0.1, hz), Vector3.RIGHT, SIZE.x, SIZE.y)
	_stone_wall(kit, Vector3(-hx, 0.1, -hz), Vector3.BACK, SIZE.z, SIZE.y)
	# Doğu duvarı: yalnız en alt sıra sabit; üstü MillWall (onarılabilir).
	StoneWall.rows(kit, _rng, Vector3(hx, 0.1, -hz), Vector3.BACK, SIZE.z, 0, 0)
	# Kapı (batı yüzünde koyu boşluk) ve pencere
	kit.box(Vector3(-hx - 0.2, 1.0, 0.4), Vector3(0.08, 1.8, 1.0), Palette.WOOD_DARK)
	kit.box(Vector3(-hx - 0.24, 1.0, 0.4), Vector3(0.05, 1.9, 0.12), Palette.WOOD)
	kit.box(Vector3(0.6, 1.9, hz + 0.2), Vector3(0.8, 0.7, 0.08), Palette.INK.lerp(Palette.LAVENDER, 0.5))
	# Ahşap çatı kirişleri
	var roof_y := SIZE.y + 0.1
	for x: float in [-hx, hx]:
		kit.box(Vector3(x, roof_y, 0), Vector3(0.22, 0.22, SIZE.z + 0.6), Palette.WOOD_DARK)
	var ridge := roof_y + 1.5
	kit.box(Vector3(0, ridge, -0.6), Vector3(0.2, 0.2, SIZE.z - 1.0), Palette.WOOD_DARK, Vector3(0.08, 0, 0))
	# Çatı: kuzey yarısı sağlam, güney yarısı çökmüş (eksik ve düşmüş kalaslar)
	var slope := atan2(1.5, hx)
	var plank_w := 0.42
	var n := int((SIZE.z + 0.8) / plank_w)
	for i in n:
		var z := -hz - 0.4 + plank_w * (i + 0.5)
		for side: float in [-1.0, 1.0]:
			var missing := z > 0.2 and side > 0 and _rng.randf() < 0.75
			if z > 1.1 and _rng.randf() < 0.6:
				missing = true
			if missing:
				continue
			var c := Palette.ROOF.lerp(Palette.WOOD_OLD, _rng.randf() * 0.5)
			var pos := Vector3(side * hx * 0.5, roof_y + 0.75 + 0.05, z)
			kit.box(pos, Vector3(hx * 1.25, 0.08, plank_w - 0.03), c, Vector3(0, 0, -side * slope + _rng.randf_range(-0.03, 0.03)))
	# Yere düşmüş kalaslar ve değirmen taşı
	kit.box(Vector3(hx + 0.6, 0.12, 1.6), Vector3(2.2, 0.08, 0.4), Palette.ROOF.lerp(Palette.WOOD_OLD, 0.5), Vector3(0.1, 0.7, 0.25))
	kit.box(Vector3(-hx - 1.4, 0.06, -1.2), Vector3(1.8, 0.08, 0.36), Palette.WOOD_OLD, Vector3(0, -0.4, 0.05))
	kit.cylinder(Vector3(-hx - 1.2, 0.35, 1.8), 0.7, 0.7, 0.28, Palette.STONE, Vector3(0.0, 0.0, 1.35), 14)
	# Yıkık duvarın döküntü taşları
	for i in 6:
		kit.box(Vector3(hx + _rng.randf_range(0.2, 1.0), 0.15, _rng.randf_range(-1.5, 1.5)), Vector3(0.45, 0.3, 0.4) * _rng.randf_range(0.7, 1.1), _stone(), Vector3(_rng.randf(), _rng.randf() * 3.0, _rng.randf()))
	return kit.commit()


## Dünya değirmeni yerleştirdikten sonra çağırır: çark su seviyesine göre konur.
func on_placed() -> void:
	wheel.position = wheel_local_center()


func wheel_local_center() -> Vector3:
	var ground := global_position.y
	var water := ValleyShape.water_y(global_position.z)
	return Vector3(SIZE.x * 0.5 + 1.55, water - ground + 0.75, 0)
