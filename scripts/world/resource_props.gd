extends Node3D
## Vadideki toplanabilir kaynakların yerleşimi: kayalar, bakır/demir damarları,
## elle alınan dallar, küçük taşlar, kil topakları ve saz demetleri.
## Şelale kayaları ve kil birikintisi yalnızca dekor.

const STONE_SPOTS := [
	Vector2(-4.0, 3.0), Vector2(-14.0, -2.0), Vector2(-9.0, 15.0), Vector2(-17.0, 12.0),
	Vector2(-2.5, -12.0), Vector2(-20.0, -14.0), Vector2(9.5, 3.0), Vector2(12.0, -10.0),
	Vector2(18.0, 4.0), Vector2(-6.5, -20.0), Vector2(6.0, 20.0), Vector2(-12.5, 22.0),
	Vector2(-7.5, 4.5), Vector2(14.0, 7.0),
]
const COPPER_SPOT := Vector2(-19.0, -6.0)
const IRON_SPOT := Vector2(16.0, 13.5)
const CLAY_Z := 18.0
## Eğitim için başlangıç noktasının yakınında birkaç dal ve küçük taş.
const STARTER_BRANCHES := [Vector2(-8.0, 11.2), Vector2(-11.2, 8.4), Vector2(-6.6, 7.6)]
const STARTER_PEBBLES := [Vector2(-10.6, 11.6), Vector2(-7.4, 9.9), Vector2(-12.0, 9.8), Vector2(-9.0, 6.6), Vector2(-5.6, 11.0)]

var gatherables: Array[Gatherable] = []
var _rng := RandomNumberGenerator.new()
var _pebble_meshes: Array[ArrayMesh] = []
var _counter := 0


func build(oak_positions: Array[Vector3]) -> void:
	_rng.seed = 77
	for i in 3:
		_pebble_meshes.append(MeshKit.rock_mesh(0.16, 60 + i, Palette.STONE.lerp(Palette.SAND, 0.3)))
	_build_boulders()
	_build_vein(COPPER_SPOT, Palette.COPPER, "copper_vein")
	_build_vein(IRON_SPOT, Palette.IRON, "iron_vein")
	_build_clay()
	_build_pebbles()
	_build_branches(oak_positions)
	_build_reeds()
	_build_waterfall_rocks()


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, ValleyShape.height(p.x, p.y), p.y)


func _add(g: Gatherable, res_id: String, pos: Vector3) -> Gatherable:
	g.resource_id = res_id
	g.save_id = "%s_%d" % [res_id, _counter]
	g.name = g.save_id
	_counter += 1
	add_child(g)
	g.position = pos
	gatherables.append(g)
	return g


func _place(mesh: Mesh, pos: Vector3, yaw: float, s: float, outline := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = WatercolorMaterials.vertex_colored(outline)
	mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)
	add_child(mi)
	return mi


# --- Kazmayla kırılanlar ------------------------------------------------------------
func _build_boulders() -> void:
	var variants: Array[ArrayMesh] = []
	for i in 3:
		variants.append(MeshKit.rock_mesh(0.55, 100 + i, Palette.STONE))
	for i in STONE_SPOTS.size():
		var s := _rng.randf_range(0.75, 1.25)
		var g := RockGatherable.new()
		_add(g, "boulder", _ground(STONE_SPOTS[i]))
		g.setup([[variants[i % 3], Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3.ZERO)]], 0.55 * s, Palette.STONE)


func _build_vein(spot: Vector2, spot_color: Color, res_id: String) -> void:
	var center := _ground(spot)
	var meshes := []
	for i in 3:
		var off := Vector2(_rng.randf_range(-1.1, 1.1), _rng.randf_range(-1.1, 1.1)) if i > 0 else Vector2.ZERO
		var s := 1.4 if i == 0 else _rng.randf_range(0.6, 0.9)
		var mesh := MeshKit.rock_mesh(0.8, 300 + i + spot_color.to_rgba32() % 50, Palette.STONE_DARK.lerp(Palette.STONE, 0.4), spot_color, 0.45)
		var p := _ground(spot + off) - center + Vector3(0, -0.1, 0)
		meshes.append([mesh, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), p)])
	var g := RockGatherable.new()
	_add(g, res_id, center)
	g.setup(meshes, 1.0, spot_color.lerp(Palette.STONE, 0.4))
	if res_id == "copper_vein":
		# Bakırın yeşil patinası (dekor)
		var patina := MeshKit.rock_mesh(0.5, 777, Palette.STONE, Palette.COPPER_PATINA, 0.5)
		_place(patina, _ground(spot + Vector2(1.8, 1.0)), 0.0, 0.8)


# --- Elle alınanlar ------------------------------------------------------------------
func _pickup(res_id: String, pos: Vector3, mesh: Mesh, yaw: float, outline := false) -> void:
	var g := PickupGatherable.new()
	_add(g, res_id, pos)
	g.setup(mesh, Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO), outline)


func _build_pebbles() -> void:
	var spots: Array[Vector2] = []
	spots.assign(STARTER_PEBBLES)
	for sp: Vector2 in STONE_SPOTS:
		if _rng.randf() < 0.6:
			var a := _rng.randf() * TAU
			spots.append(sp + Vector2(cos(a), sin(a)) * 1.3)
	for i in spots.size():
		_pickup("pebble", _ground(spots[i]), _pebble_meshes[i % 3], _rng.randf() * TAU)


func _branch_mesh(seed_i: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = 500 + seed_i
	var kit := MeshKit.new()
	for i in 3:
		var yaw := r.randf_range(-0.6, 0.6) + i * 1.1
		var l := r.randf_range(0.55, 0.85)
		var c := Palette.WOOD.lerp(Palette.WOOD_DARK, r.randf())
		kit.cylinder(Vector3(0, 0.05 + i * 0.035, 0), 0.03, 0.04, l, c, Vector3(PI * 0.5, yaw, 0), 6)
	kit.sphere(Vector3(0.18, 0.1, 0.05), 0.09, Palette.MOSS_LIGHT, Vector3(1, 0.6, 1), 6)
	return kit.commit()


func _build_branches(oaks: Array[Vector3]) -> void:
	var spots: Array[Vector2] = []
	spots.assign(STARTER_BRANCHES)
	for i in oaks.size():
		if i % 2 == 0:
			var a := _rng.randf() * TAU
			spots.append(Vector2(oaks[i].x, oaks[i].z) + Vector2(cos(a), sin(a)) * 1.6)
	var meshes := [_branch_mesh(0), _branch_mesh(1)]
	for i in spots.size():
		var p := _ground(spots[i])
		if ValleyShape.distance_to_river(p.x, p.z) < ValleyShape.river_half_width(p.z) + 0.6:
			continue
		_pickup("branch_pile", p, meshes[i % 2], _rng.randf() * TAU, true)


## Saz demeti: tepesi kahverengi püsküllü birkaç kalın saz (dekor sazlardan ayırt edilsin).
func _reed_mesh() -> ArrayMesh:
	var kit := MeshKit.new()
	for i in 5:
		var a := TAU * i / 5.0
		var p := Vector3(cos(a), 0, sin(a)) * 0.1
		var h := 0.8 + 0.12 * float(i % 3)
		kit.cylinder(p + Vector3(0, h * 0.5, 0), 0.018, 0.024, h, Palette.MOSS.lerp(Palette.REED, 0.5), Vector3(cos(a) * 0.1, 0, sin(a) * 0.1), 5)
		kit.cylinder(p + Vector3(cos(a) * 0.05, h + 0.06, sin(a) * 0.05), 0.04, 0.04, 0.16, Palette.WOOD.lerp(Palette.EARTH, 0.4), Vector3.ZERO, 6)
	kit.cylinder(Vector3(0, 0.25, 0), 0.13, 0.13, 0.05, Palette.REED, Vector3.ZERO, 8)
	return kit.commit()


func _build_reeds() -> void:
	var mesh := _reed_mesh()
	for z: float in [-15.0, -10.5, -3.5, 3.0, 13.0, 16.5, 23.0]:
		var x := ValleyShape.river_x(z) - ValleyShape.river_half_width(z) - 0.55
		var y := maxf(ValleyShape.height(x, z), ValleyShape.water_y(z) - 0.05)
		_pickup("reed_clump", Vector3(x, y, z), mesh, _rng.randf() * TAU, true)


func _build_clay() -> void:
	var x := ValleyShape.river_x(CLAY_Z) - ValleyShape.river_half_width(CLAY_Z) - 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := FastNoiseLite.new()
	n.seed = 4
	var segs := 18
	var center := Vector3(x, 0, CLAY_Z)
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
		var px := x + (i - 1) * 0.9
		var pz := CLAY_Z + _rng.randf_range(-0.4, 0.4)
		_pickup("clay_lump", Vector3(px, ValleyShape.height(px, pz), pz), lump, 0.0, true)


func _build_waterfall_rocks() -> void:
	for i in 9:
		var z := _rng.randf_range(-23.5, -19.5)
		var side := -1.0 if i % 2 == 0 else 1.0
		var hw := ValleyShape.river_half_width(z)
		var x := ValleyShape.river_x(z) + side * (hw + _rng.randf_range(-0.2, 0.9))
		var y := ValleyShape.height(x, z)
		var mesh := MeshKit.rock_mesh(0.9, 500 + i, Palette.STONE.lerp(Palette.STONE_DARK, 0.2))
		_place(mesh, Vector3(x, y, z), _rng.randf() * TAU, _rng.randf_range(0.8, 1.6))
