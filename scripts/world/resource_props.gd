extends Node3D
## Aşama 1: kaynakların yalnızca görsel hali (taşlar, bakır/demir damarı, kil, şelale kayaları).
## Aşama 2'de bunlar toplanabilir kaynak sahnelerine dönüşecek; konumlar burada.

const STONE_SPOTS := [
	Vector2(-4.0, 3.0), Vector2(-14.0, -2.0), Vector2(-9.0, 15.0), Vector2(-17.0, 12.0),
	Vector2(-2.5, -12.0), Vector2(-20.0, -14.0), Vector2(9.5, 3.0), Vector2(12.0, -10.0),
	Vector2(18.0, 4.0), Vector2(-6.5, -20.0), Vector2(6.0, 20.0), Vector2(-12.5, 22.0),
]
const COPPER_SPOT := Vector2(-19.0, -6.0)
const IRON_SPOT := Vector2(16.0, 13.5)

var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = 77
	_build_stones()
	_build_vein(COPPER_SPOT, Palette.COPPER, "copper")
	_build_vein(IRON_SPOT, Palette.IRON, "iron")
	_build_clay()
	_build_waterfall_rocks()


func _place(mesh: Mesh, pos: Vector3, yaw: float, s: float, outline := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = WatercolorMaterials.vertex_colored(outline)
	mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)
	add_child(mi)
	return mi


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, ValleyShape.height(p.x, p.y), p.y)


func _build_stones() -> void:
	var variants: Array[ArrayMesh] = []
	for i in 3:
		variants.append(MeshKit.rock_mesh(0.55, 100 + i, Palette.STONE))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = variants[0]
	mm.instance_count = STONE_SPOTS.size()
	for i in STONE_SPOTS.size():
		var s := _rng.randf_range(0.7, 1.3)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), _ground(STONE_SPOTS[i])))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Stones"
	mmi.multimesh = mm
	mmi.material_override = WatercolorMaterials.vertex_colored(true)
	add_child(mmi)
	# Farklı şekiller için iki ek kaya
	_place(variants[1], _ground(Vector2(-7.5, 4.5)), 0.4, 0.8)
	_place(variants[2], _ground(Vector2(14.0, 7.0)), 1.2, 1.1)


func _build_vein(spot: Vector2, spot_color: Color, id: String) -> void:
	var body := StaticBody3D.new()
	body.name = id.capitalize() + "Vein"
	add_child(body)
	for i in 3:
		var off := Vector2(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-1.2, 1.2)) if i > 0 else Vector2.ZERO
		var s := 1.4 if i == 0 else _rng.randf_range(0.6, 0.9)
		var mesh := MeshKit.rock_mesh(0.8, 300 + i + spot_color.to_rgba32() % 50, Palette.STONE_DARK.lerp(Palette.STONE, 0.4), spot_color, 0.45)
		_place(mesh, _ground(spot + off) + Vector3(0, -0.1, 0), _rng.randf() * TAU, s)
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.75 * s
		cs.shape = sph
		cs.position = _ground(spot + off)
		body.add_child(cs)
	if id == "copper":
		# Bakırın yeşil patinası
		var patina := MeshKit.rock_mesh(0.5, 777, Palette.STONE, Palette.COPPER_PATINA, 0.5)
		_place(patina, _ground(spot + Vector2(1.5, 0.8)), 0.0, 0.8)


func _build_clay() -> void:
	var z := 18.0
	var x := ValleyShape.river_x(z) - ValleyShape.river_half_width(z) - 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := FastNoiseLite.new()
	n.seed = 4
	var segs := 18
	var center := Vector3(x, 0, z)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var r0 := 1.6 + n.get_noise_1d(a0 * 30.0) * 0.6
		var r1 := 1.6 + n.get_noise_1d(a1 * 30.0) * 0.6
		var p0 := center + Vector3(cos(a0) * r0, 0, sin(a0) * r0 * 0.7)
		var p1 := center + Vector3(cos(a1) * r1, 0, sin(a1) * r1 * 0.7)
		for p in [center, p0, p1]:
			var q: Vector3 = p
			q.y = ValleyShape.height(q.x, q.z) + 0.03
			st.set_color(Palette.CLAY.lerp(Palette.EARTH, 0.2 if p == center else 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(q)
	var mi := MeshInstance3D.new()
	mi.name = "ClayPatch"
	mi.mesh = st.commit()
	mi.material_override = WatercolorMaterials.vertex_colored(false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for i in 3:
		var lump := MeshKit.rock_mesh(0.25, 900 + i, Palette.CLAY)
		_place(lump, Vector3(x + _rng.randf_range(-0.8, 0.8), ValleyShape.height(x, z), z + _rng.randf_range(-0.5, 0.5)), 0.0, 1.0, false)


func _build_waterfall_rocks() -> void:
	for i in 9:
		var z := _rng.randf_range(-23.5, -19.5)
		var side := -1.0 if i % 2 == 0 else 1.0
		var hw := ValleyShape.river_half_width(z)
		var x := ValleyShape.river_x(z) + side * (hw + _rng.randf_range(-0.2, 0.9))
		var y := ValleyShape.height(x, z)
		var mesh := MeshKit.rock_mesh(0.9, 500 + i, Palette.STONE.lerp(Palette.STONE_DARK, 0.2))
		_place(mesh, Vector3(x, y, z), _rng.randf() * TAU, _rng.randf_range(0.8, 1.6))
