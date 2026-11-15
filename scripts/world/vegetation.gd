extends Node3D
## Ağaçlar (meşe, çam), çimen, saz ve çiçekler: hepsi MultiMeshInstance3D.
## Tüm çimen tek draw call, tüm yaprak blob'ları tek draw call.
## Aşama 2'de ağaçlar toplanabilir kaynaklara dönüşecek; konumlar deterministik.

const SEED := 7
const GRASS_COUNTS := [2600, 5200, 9000]  ## Düşük / Orta / Yüksek

## Yapıların çevresinde boş bırakılacak alanlar (x, z, yarıçap). world.gd doldurur.
var keep_clear: Array[Vector3] = []

var oak_positions: Array[Vector3] = []
var pine_positions: Array[Vector3] = []
var _grass: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = SEED
	_place_trees()
	_build_trees()
	_build_grass()
	_build_reeds()
	_build_flowers()
	GameState.quality_changed.connect(_on_quality_changed)
	_on_quality_changed(GameState.quality)


func _is_clear(x: float, z: float, margin: float) -> bool:
	for c in keep_clear:
		if Vector2(x - c.x, z - c.y).length() < c.z + margin:
			return false
	return true


func _ground_ok(x: float, z: float, river_margin: float, path_margin: float) -> bool:
	if absf(x) > 27.5 or absf(z) > 27.5:
		return false
	if ValleyShape.distance_to_river(x, z) < ValleyShape.river_half_width(z) + river_margin:
		return false
	if ValleyShape.distance_to_path(x, z) < path_margin:
		return false
	return ValleyShape.normal(x, z).y > 0.86


func _place_trees() -> void:
	var tries := 0
	while (oak_positions.size() < 22 or pine_positions.size() < 26) and tries < 4000:
		tries += 1
		var x := _rng.randf_range(-27.0, 27.0)
		var z := _rng.randf_range(-27.0, 27.0)
		if not _ground_ok(x, z, 2.2, 1.6) or not _is_clear(x, z, 1.5):
			continue
		var p := Vector3(x, ValleyShape.height(x, z), z)
		var too_close := false
		for q in oak_positions + pine_positions:
			if Vector2(q.x - x, q.z - z).length() < 3.2:
				too_close = true
				break
		if too_close:
			continue
		# Çamlar kenarlarda ve platoda, meşeler vadinin içinde.
		var edge := maxf(absf(x) / 27.0, (-z) / 27.0)
		if _rng.randf() < 0.25 + edge * 0.7:
			if pine_positions.size() < 26:
				pine_positions.append(p)
		elif oak_positions.size() < 22:
			oak_positions.append(p)


func _mm(mesh: Mesh, count: int, material: Material, use_colors := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_colors
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
	return mmi


func _build_trees() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.24
	trunk.height = 1.0
	trunk.radial_segments = 7
	trunk.rings = 1
	var blob := SphereMesh.new()
	blob.radius = 1.0
	blob.height = 2.0
	blob.radial_segments = 14
	blob.rings = 8
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 10
	cone.rings = 2

	var trunk_xf: Array[Transform3D] = []
	var trunk_col: Array[Color] = []
	var blob_xf: Array[Transform3D] = []
	var blob_col: Array[Color] = []
	var cone_xf: Array[Transform3D] = []
	var cone_col: Array[Color] = []
	var body := StaticBody3D.new()
	body.name = "TreeColliders"
	add_child(body)

	for p in oak_positions:
		var s := _rng.randf_range(0.85, 1.25)
		var th := 2.0 * s
		trunk_xf.append(Transform3D(Basis.from_scale(Vector3(s, th, s)), p + Vector3(0, th * 0.5 - 0.1, 0)))
		trunk_col.append(Palette.WOOD_DARK.lerp(Palette.WOOD, _rng.randf()))
		var crown := p + Vector3(0, th + 0.6 * s, 0)
		var base_green := Palette.MOSS.lerp(Palette.MOSS_LIGHT, _rng.randf_range(0.0, 0.6))
		for i in 7:
			var off := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.9), _rng.randf_range(-1.0, 1.0)) * s
			if i == 0:
				off = Vector3(0, 0.25 * s, 0)
			var r := _rng.randf_range(0.7, 1.05) * s
			var sq := Vector3(r, r * _rng.randf_range(0.78, 0.95), r)
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(sq)
			blob_xf.append(Transform3D(b, crown + off))
			var shade := clampf(0.55 + off.y * 0.4, 0.0, 1.0)
			blob_col.append(Palette.MOSS_DARK.lerp(base_green, shade))
		_add_trunk_collider(body, p, 0.3 * s)

	for p in pine_positions:
		var s := _rng.randf_range(0.8, 1.3)
		var th := 1.2 * s
		trunk_xf.append(Transform3D(Basis.from_scale(Vector3(s * 0.8, th, s * 0.8)), p + Vector3(0, th * 0.5 - 0.1, 0)))
		trunk_col.append(Palette.WOOD_DARK)
		var green := Palette.PINE.lerp(Palette.MOSS_DARK, _rng.randf())
		for i in 3:
			var r := (1.35 - i * 0.33) * s
			var h := (1.6 - i * 0.2) * s
			var y := th + i * 0.95 * s + h * 0.5 - 0.2
			cone_xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(r, h, r)), p + Vector3(0, y, 0)))
			cone_col.append(green.lerp(Palette.MOSS_LIGHT, i * 0.12))
		_add_trunk_collider(body, p, 0.25 * s)

	var mm_trunk := _mm(trunk, trunk_xf.size(), WatercolorMaterials.vertex_colored(true))
	mm_trunk.name = "Trunks"
	_fill(mm_trunk.multimesh, trunk_xf, trunk_col)
	var mm_blob := _mm(blob, blob_xf.size(), WatercolorMaterials.foliage(true))
	mm_blob.name = "OakLeaves"
	_fill(mm_blob.multimesh, blob_xf, blob_col)
	var mm_cone := _mm(cone, cone_xf.size(), WatercolorMaterials.foliage(true))
	mm_cone.name = "PineNeedles"
	_fill(mm_cone.multimesh, cone_xf, cone_col)


func _add_trunk_collider(body: StaticBody3D, p: Vector3, r: float) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = 3.0
	cs.shape = cyl
	cs.position = p + Vector3(0, 1.5, 0)
	body.add_child(cs)


func _fill(mm: MultiMesh, xf: Array[Transform3D], col: Array[Color]) -> void:
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, col[i])


## Üç yapraklı çimen tutamı; tabanı koyu, ucu açık (vertex rengi).
func _grass_tuft_mesh(height: float, width: float, blades: int, base_col: Color, tip_col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in blades:
		var a := TAU * i / blades + 0.4
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * width
		var lean := dir * height * 0.25
		var bh := height * (0.8 + 0.2 * float(i % 2))
		st.set_normal(Vector3.UP)
		st.set_color(base_col); st.set_uv(Vector2(0, 0)); st.add_vertex(-side)
		st.set_color(base_col); st.set_uv(Vector2(1, 0)); st.add_vertex(side)
		st.set_color(tip_col); st.set_uv(Vector2(0.5, 1)); st.add_vertex(Vector3(0, bh, 0) + lean)
	return st.commit()


func _build_grass() -> void:
	var mesh := _grass_tuft_mesh(0.34, 0.06, 4, Palette.MOSS, Palette.MOSS_LIGHT.lerp(Palette.SUNSET_LIGHT, 0.2))
	var max_count: int = GRASS_COUNTS[2]
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var tries := 0
	while xf.size() < max_count and tries < max_count * 6:
		tries += 1
		var x := _rng.randf_range(-28.0, 28.0)
		var z := _rng.randf_range(-28.0, 28.0)
		if not _ground_ok(x, z, 0.9, 0.9) or not _is_clear(x, z, -0.5):
			continue
		# Kümelenme: noise yüksek olan yerlerde daha yoğun
		if ValleyShape.detail_noise(x * 1.7, z * 1.7) < _rng.randf_range(-0.6, 0.3):
			continue
		var s := _rng.randf_range(0.6, 1.2)
		var p := Vector3(x, ValleyShape.height(x, z) - 0.03, z)
		xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.3), s)), p))
		col.append(Color.WHITE.lerp(Palette.SUNSET_LIGHT, _rng.randf() * 0.35))
	# Rastgele sıradan dolayı visible_instance_count ile yoğunluk düşürülebilir.
	_grass = _mm(mesh, xf.size(), WatercolorMaterials.foliage(false, true))
	_grass.name = "Grass"
	_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill(_grass.multimesh, xf, col)


func _build_reeds() -> void:
	var mesh := _grass_tuft_mesh(1.1, 0.04, 5, Palette.MOSS_DARK, Palette.REED)
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var z := -19.0
	while z < 27.5:
		for side: float in [-1.0, 1.0]:
			if _rng.randf() < 0.55:
				var hw := ValleyShape.river_half_width(z)
				var x := ValleyShape.river_x(z) + side * (hw + _rng.randf_range(-0.2, 0.7))
				if not _is_clear(x, z, 0.0):
					continue
				var y := maxf(ValleyShape.height(x, z), ValleyShape.water_y(z) - 0.1)
				var s := _rng.randf_range(0.7, 1.2)
				xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y, z)))
				col.append(Color.WHITE)
		z += 0.55
	var mmi := _mm(mesh, xf.size(), WatercolorMaterials.foliage(false, true))
	mmi.name = "Reeds"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill(mmi.multimesh, xf, col)


func _build_flowers() -> void:
	var m := SphereMesh.new()
	m.radius = 0.07
	m.height = 0.12
	m.radial_segments = 6
	m.rings = 3
	var colors := [Palette.SUNSET, Palette.PAPER, Palette.LAVENDER, Palette.SUNSET_LIGHT]
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var tries := 0
	while xf.size() < 260 and tries < 3000:
		tries += 1
		var x := _rng.randf_range(-26.0, 26.0)
		var z := _rng.randf_range(-26.0, 26.0)
		if not _ground_ok(x, z, 1.0, 1.0) or not _is_clear(x, z, 0.0):
			continue
		if ValleyShape.detail_noise(x * 0.6 + 40.0, z * 0.6) < 0.25:
			continue
		xf.append(Transform3D(Basis.IDENTITY, Vector3(x, ValleyShape.height(x, z) + 0.28, z)))
		col.append(colors[_rng.randi() % colors.size()])
	var mmi := _mm(m, xf.size(), WatercolorMaterials.vertex_colored(false))
	mmi.name = "Flowers"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill(mmi.multimesh, xf, col)


func _on_quality_changed(level: int) -> void:
	if _grass:
		_grass.multimesh.visible_instance_count = mini(GRASS_COUNTS[level], _grass.multimesh.instance_count)
