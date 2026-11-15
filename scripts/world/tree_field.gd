class_name TreeField
extends Node3D
## Vadideki tüm ağaçlar: gövde, meşe yaprak blob'ları, çam konileri ve kütükler
## dört MultiMesh'te (dört draw call). Her ağacın parçaları kendi yerel dönüşümünü
## bilir; kesilme, sallanma ve büyüme yalnızca o ağacın örneklerini günceller.

signal tree_fell(position: Vector3, kind: String)
signal tree_grown(position: Vector3, kind: String)

const PLANT_CAPACITY := 12     ## tür başına dikilebilecek ek ağaç
const FALL_TIME := 1.25
const SHRINK_TIME := 0.45
const SHAKE_TIME := 0.38
const SAPLING_SCALE := 0.16

class TreeData:
	var kind := "oak"
	var base := Vector3.ZERO
	var parts: Array = []        ## [MultiMesh, index, yerel Transform3D]
	var stump_index := -1
	var collider: CollisionShape3D
	var gatherable: TreeGatherable
	var active := true
	var planted := false
	var shake_t := 0.0
	var shake_dir := Vector3.RIGHT
	var fall_t := -1.0           ## <0: düşmüyor
	var fall_dir := Vector3.FORWARD
	var growing := false

var trees: Array[TreeData] = []
var _mm_trunk: MultiMesh
var _mm_blob: MultiMesh
var _mm_cone: MultiMesh
var _mm_stump: MultiMesh
var _animating := {}            ## TreeData -> true
var _rng: RandomNumberGenerator
var _body: StaticBody3D
var _hidden := Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -50, 0))


func build(oaks: Array[Vector3], pines: Array[Vector3], rng: RandomNumberGenerator) -> void:
	_rng = rng
	_body = StaticBody3D.new()
	_body.name = "TreeColliders"
	_body.set_meta("surface", "wood")
	add_child(_body)
	var oak_total := oaks.size() + PLANT_CAPACITY
	var pine_total := pines.size() + PLANT_CAPACITY
	_mm_trunk = _make_mm("Trunks", _trunk_mesh(), oak_total + pine_total, WatercolorMaterials.vertex_colored(true))
	_mm_blob = _make_mm("OakLeaves", _blob_mesh(), oak_total * 7, WatercolorMaterials.foliage(true))
	_mm_cone = _make_mm("PineNeedles", _cone_mesh(), pine_total * 3, WatercolorMaterials.foliage(true))
	_mm_stump = _make_mm("Stumps", _stump_mesh(), oak_total + pine_total, WatercolorMaterials.vertex_colored(true))
	var counters := {"trunk": 0, "blob": 0, "cone": 0}
	for i in oak_total:
		var p: Vector3 = oaks[i] if i < oaks.size() else Vector3.ZERO
		_add_tree("oak", p, i >= oaks.size(), counters)
	for i in pine_total:
		var p: Vector3 = pines[i] if i < pines.size() else Vector3.ZERO
		_add_tree("pine", p, i >= pines.size(), counters)
	for t in trees:
		_refresh(t)


func _make_mm(n: String, mesh: Mesh, count: int, material: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
	return mm


func _add_tree(kind: String, p: Vector3, spare: bool, counters: Dictionary) -> void:
	var t := TreeData.new()
	t.kind = kind
	t.base = p
	t.active = not spare
	t.planted = spare
	t.stump_index = trees.size()
	if kind == "oak":
		_oak_parts(t, counters)
	else:
		_pine_parts(t, counters)
	_mm_stump.set_instance_color(t.stump_index, Palette.WOOD_DARK.lerp(Palette.WOOD, 0.55))
	t.collider = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3 if kind == "oak" else 0.25
	cyl.height = 3.0
	t.collider.shape = cyl
	_body.add_child(t.collider)
	t.gatherable = TreeGatherable.new()
	t.gatherable.resource_id = "oak_tree" if kind == "oak" else "pine_tree"
	t.gatherable.save_id = "tree_%d" % trees.size()
	t.gatherable.name = "Tree%d" % trees.size()
	t.gatherable.field = self
	t.gatherable.data = t
	add_child(t.gatherable)
	t.gatherable.position = p + Vector3(0, 0.2, 0)
	t.gatherable.visible = t.active
	trees.append(t)


func _oak_parts(t: TreeData, c: Dictionary) -> void:
	var s := _rng.randf_range(0.85, 1.25)
	var th := 2.0 * s
	_part(t, _mm_trunk, c, "trunk", Transform3D(Basis.from_scale(Vector3(s, th, s)), Vector3(0, th * 0.5 - 0.1, 0)), Palette.WOOD_DARK.lerp(Palette.WOOD, _rng.randf()))
	var crown := Vector3(0, th + 0.6 * s, 0)
	var base_green := Palette.MOSS.lerp(Palette.MOSS_LIGHT, _rng.randf_range(0.0, 0.6))
	for i in 7:
		var off := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.9), _rng.randf_range(-1.0, 1.0)) * s
		if i == 0:
			off = Vector3(0, 0.25 * s, 0)
		var r := _rng.randf_range(0.7, 1.05) * s
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(r, r * _rng.randf_range(0.78, 0.95), r))
		var shade := clampf(0.55 + off.y * 0.4, 0.0, 1.0)
		_part(t, _mm_blob, c, "blob", Transform3D(b, crown + off), Palette.MOSS_DARK.lerp(base_green, shade))


func _pine_parts(t: TreeData, c: Dictionary) -> void:
	var s := _rng.randf_range(0.8, 1.3)
	var th := 1.2 * s
	_part(t, _mm_trunk, c, "trunk", Transform3D(Basis.from_scale(Vector3(s * 0.8, th, s * 0.8)), Vector3(0, th * 0.5 - 0.1, 0)), Palette.WOOD_DARK)
	var green := Palette.PINE.lerp(Palette.MOSS_DARK, _rng.randf())
	for i in 3:
		var r := (1.35 - i * 0.33) * s
		var h := (1.6 - i * 0.2) * s
		var y := th + i * 0.95 * s + h * 0.5 - 0.2
		_part(t, _mm_cone, c, "cone", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(r, h, r)), Vector3(0, y, 0)), green.lerp(Palette.MOSS_LIGHT, i * 0.12))


func _part(t: TreeData, mm: MultiMesh, c: Dictionary, key: String, local: Transform3D, col: Color) -> void:
	var idx: int = c[key]
	c[key] = idx + 1
	mm.set_instance_color(idx, col)
	t.parts.append([mm, idx, local])


# --- Durum ve animasyon ---------------------------------------------------------------
## Ağacın o anki kök dönüşümü: konum * düşme * sallanma * büyüme ölçeği.
func _root_xform(t: TreeData) -> Transform3D:
	var g := t.gatherable
	var scale := 1.0
	if g.state == Gatherable.State.GROWING:
		scale = lerpf(SAPLING_SCALE, 1.0, ease(g.growth, 0.7))
	var b := Basis.from_scale(Vector3.ONE * scale)
	if t.shake_t > 0.0:
		var k := t.shake_t / SHAKE_TIME
		var ang := sin((1.0 - k) * 26.0) * 0.06 * k
		b = Basis(t.shake_dir.cross(Vector3.UP).normalized(), ang) * b
	if t.fall_t >= 0.0:
		var f := clampf(t.fall_t / FALL_TIME, 0.0, 1.0)
		b = Basis(t.fall_dir.cross(Vector3.UP).normalized(), -1.42 * f * f) * b
		var shrink := clampf((t.fall_t - FALL_TIME) / SHRINK_TIME, 0.0, 1.0)
		if shrink > 0.0:
			b = b.scaled(Vector3.ONE * maxf(1.0 - shrink, 0.001))
	return Transform3D(b, t.base)


func _refresh(t: TreeData) -> void:
	var g := t.gatherable
	var show_tree := t.active and (g.state != Gatherable.State.DEPLETED or t.fall_t >= 0.0)
	var root := _root_xform(t)
	for part in t.parts:
		var mm: MultiMesh = part[0]
		mm.set_instance_transform(part[1], root * (part[2] as Transform3D) if show_tree else _hidden)
	var show_stump := t.active and g.state == Gatherable.State.DEPLETED
	var stump_scale := 0.9 if t.kind == "oak" else 0.75
	_mm_stump.set_instance_transform(t.stump_index, Transform3D(Basis.from_scale(Vector3.ONE * stump_scale), t.base) if show_stump else _hidden)
	t.collider.position = t.base + Vector3(0, 1.5, 0)
	t.collider.disabled = not t.active or g.state == Gatherable.State.DEPLETED \
		or (g.state == Gatherable.State.GROWING and g.growth < 0.5)
	g.visible = t.active


func on_state_changed(t: TreeData) -> void:
	var st := t.gatherable.state
	if st == Gatherable.State.READY and t.growing:
		tree_grown.emit(t.base, t.kind)
	t.growing = st == Gatherable.State.GROWING
	_refresh(t)


func shake(t: TreeData, from: Vector3) -> void:
	var d := t.base - from
	d.y = 0.0
	t.shake_dir = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	t.shake_t = SHAKE_TIME
	_animating[t] = true


func start_fall(t: TreeData, from: Vector3) -> void:
	var d := t.base - from
	d.y = 0.0
	t.fall_dir = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	t.fall_t = 0.0
	t.shake_t = 0.0
	_animating[t] = true


func _process(delta: float) -> void:
	if _animating.is_empty():
		return
	for t: TreeData in _animating.keys():
		var done := true
		if t.shake_t > 0.0:
			t.shake_t = maxf(t.shake_t - delta, 0.0)
			done = done and t.shake_t <= 0.0
		if t.fall_t >= 0.0:
			var before := t.fall_t
			t.fall_t += delta
			if before < FALL_TIME and t.fall_t >= FALL_TIME:
				tree_fell.emit(t.base + t.fall_dir * 2.2 + Vector3(0, 0.6, 0), t.kind)
			if t.fall_t >= FALL_TIME + SHRINK_TIME:
				t.fall_t = -1.0
			else:
				done = false
		_refresh(t)
		if done:
			_animating.erase(t)


func update_growth(t: TreeData) -> void:
	_refresh(t)


# --- Dikim ------------------------------------------------------------------------------
func active_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for t in trees:
		if t.active:
			out.append(t.base)
	return out


func free_slot(kind: String) -> TreeData:
	for t in trees:
		if t.planted and not t.active and t.kind == kind:
			return t
	return null


func plant(kind: String, pos: Vector3, start_growth := 0.0) -> TreeData:
	var t := free_slot(kind)
	if t == null:
		return null
	plant_in(t, pos, start_growth)
	return t


## Belirli bir boş yuvaya dik (kayıttan yüklerken de kullanılır).
func plant_in(t: TreeData, pos: Vector3, start_growth := 0.0) -> void:
	t.base = pos
	t.active = true
	t.gatherable.position = pos + Vector3(0, 0.2, 0)
	t.gatherable.visible = true
	t.gatherable.start_growing(start_growth)


func planted_list() -> Array:
	var out := []
	for t in trees:
		if t.planted and t.active:
			out.append({"kind": t.kind, "x": snappedf(t.base.x, 0.01), "z": snappedf(t.base.z, 0.01), "slot": t.gatherable.save_id})
	return out


# --- Mesh'ler ---------------------------------------------------------------------------
func _trunk_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.14
	m.bottom_radius = 0.24
	m.height = 1.0
	m.radial_segments = 7
	m.rings = 1
	return m


func _blob_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 14
	m.rings = 8
	return m


func _cone_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 10
	m.rings = 2
	return m


## Kütük: kısa gövde + açık renkli kesik yüzey + birkaç yonga.
func _stump_mesh() -> Mesh:
	var kit := MeshKit.new()
	kit.cylinder(Vector3(0, 0.16, 0), 0.26, 0.32, 0.36, Color.WHITE.darkened(0.25), Vector3.ZERO, 9)
	kit.cylinder(Vector3(0, 0.345, 0), 0.24, 0.24, 0.02, Palette.SAND.lerp(Color.WHITE, 0.2), Vector3.ZERO, 9)
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		kit.box(Vector3(cos(a) * 0.5, 0.03, sin(a) * 0.5), Vector3(0.12, 0.04, 0.06), Palette.SAND, Vector3(0, a, 0))
	return kit.commit()
