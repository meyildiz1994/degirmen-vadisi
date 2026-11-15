extends Node3D
## Ağaçlar (meşe, çam), çimen, saz ve çiçekler: hepsi MultiMeshInstance3D.
## Tüm çimen tek draw call, tüm yaprak blob'ları tek draw call.
## Ağaçlar kesilebilir ve dikilebilir: TreeField (konumlar deterministik).

const SEED := 7
const GRASS_COUNTS := [2600, 5200, 9000]  ## Düşük / Orta / Yüksek

## Yapıların çevresinde boş bırakılacak alanlar (x, z, yarıçap). world.gd doldurur.
var keep_clear: Array[Vector3] = []

var oak_positions: Array[Vector3] = []
var pine_positions: Array[Vector3] = []
var tree_field: TreeField
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
	tree_field = TreeField.new()
	tree_field.name = "Trees"
	add_child(tree_field)
	tree_field.build(oak_positions, pine_positions, _rng)


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


## Tohum dikmeye uygun mu: düz zemin, dere/patika/yapı dışında, diğer ağaçlardan uzak.
func can_plant(x: float, z: float) -> bool:
	if not _ground_ok(x, z, 1.4, 1.1) or not _is_clear(x, z, 0.5):
		return false
	for p in tree_field.active_positions():
		if Vector2(p.x - x, p.z - z).length() < 2.6:
			return false
	return true


func _on_quality_changed(level: int) -> void:
	if _grass:
		_grass.multimesh.visible_instance_count = mini(GRASS_COUNTS[level], _grass.multimesh.instance_count)
