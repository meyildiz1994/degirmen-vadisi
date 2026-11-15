class_name MeshKit
extends RefCounted
## Primitive mesh'leri vertex rengiyle tek bir ArrayMesh'te birleştirir.
## Bir yapı = tek mesh = tek draw call (+ kalite açıksa kenar çizgisi geçişi).

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()


func add_mesh(mesh: PrimitiveMesh, xform: Transform3D, color: Color) -> MeshKit:
	var arr := mesh.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var base := _verts.size()
	var nb := xform.basis.inverse().transposed()
	for i in v.size():
		_verts.append(xform * v[i])
		_normals.append((nb * n[i]).normalized())
		_colors.append(color)
		_uvs.append(uv[i] if uv != null and i < uv.size() else Vector2.ZERO)
	for j in idx:
		_indices.append(base + j)
	return self


static func make_xform(pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(rot).scaled_local(scale) if rot != Vector3.ZERO else Basis.from_scale(scale)
	return Transform3D(b, pos)


func box(pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshKit:
	var m := BoxMesh.new()
	m.size = size
	return add_mesh(m, make_xform(pos, rot), color)


func cylinder(pos: Vector3, radius_top: float, radius_bottom: float, h: float, color: Color, rot := Vector3.ZERO, segments := 10) -> MeshKit:
	var m := CylinderMesh.new()
	m.top_radius = radius_top
	m.bottom_radius = radius_bottom
	m.height = h
	m.radial_segments = segments
	m.rings = 1
	return add_mesh(m, make_xform(pos, rot), color)


func prism(pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshKit:
	var m := PrismMesh.new()
	m.size = size
	return add_mesh(m, make_xform(pos, rot), color)


func sphere(pos: Vector3, radius: float, color: Color, scale := Vector3.ONE, segments := 12) -> MeshKit:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = maxi(4, segments / 2)
	return add_mesh(m, make_xform(pos, Vector3.ZERO, scale), color)


func is_empty() -> bool:
	return _verts.is_empty()


func commit() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	if _verts.is_empty():
		return mesh  # boş kit (örn. tamamen yıkık duvar sırası): yüzeysiz mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Gürültüyle bozulmuş, organik görünümlü bir kaya mesh'i.
static func rock_mesh(radius: float, seed_value: int, base_color: Color, spot_color := Color(0, 0, 0, 0), spot_amount := 0.0) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.3
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 1.4
	sm.radial_segments = 10
	sm.rings = 6
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(v.size())
	for i in v.size():
		var p := v[i]
		var d := 1.0 + noise.get_noise_3dv(p * 1.7) * 0.35
		p *= d
		if p.y < -radius * 0.25:
			p.y = -radius * 0.25 - (p.y + radius * 0.25) * 0.2
		v[i] = p
		var c := base_color.lerp(Palette.STONE_DARK, clampf(0.5 - p.y / radius, 0.0, 1.0) * 0.35)
		if spot_amount > 0.0:
			var s := noise.get_noise_3dv(p * 4.5 + Vector3(9, 3, 1))
			if s > 1.0 - spot_amount * 1.6:
				c = spot_color
		colors[i] = c
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for j in idx:
		st.set_color(colors[j])
		st.add_vertex(v[j])
	st.index()
	st.generate_normals()
	return st.commit()
