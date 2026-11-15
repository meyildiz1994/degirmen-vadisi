extends StaticBody3D
## Vadinin zemini: ValleyShape'ten prosedürel ızgara mesh, vertex renkleriyle boyanır.
## Ayrıca dere kıyısına görünmez bariyerler koyar (köprü onarılana kadar karşıya geçilemez).

const EXTENT := 34.0        ## Görünen zemin yarı boyutu (oynanabilir alan 30)
const RESOLUTION := 110     ## Izgara hücre sayısı (kenar başına)
const PLAY_LIMIT := 28.5

var mesh_instance: MeshInstance3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = _build_mesh()
	mesh_instance.material_override = WatercolorMaterials.vertex_colored(false)
	add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	shape.shape = mesh_instance.mesh.create_trimesh_shape()
	add_child(shape)
	_build_bounds()
	_build_river_barriers()


func _ground_color(x: float, z: float, h: float, n: Vector3) -> Color:
	var dn := ValleyShape.detail_noise(x, z)
	var c := Palette.MOSS.lerp(Palette.MOSS_LIGHT, clampf(dn * 0.8 + 0.35, 0.0, 1.0))
	c = c.lerp(Palette.MOSS_DARK, clampf(-dn - 0.35, 0.0, 1.0) * 0.8)
	# Yükseklerde ışık alan sarımsı çayır
	c = c.lerp(Palette.MOSS_LIGHT.lerp(Palette.SUNSET_LIGHT, 0.2), smoothstep(2.5, 6.0, h) * 0.25)
	# Dik yamaçlar: toprak ve taş
	var steep := 1.0 - n.y
	c = c.lerp(Palette.EARTH, smoothstep(0.18, 0.35, steep))
	c = c.lerp(Palette.STONE_DARK.lerp(Palette.EARTH, 0.25), smoothstep(0.38, 0.6, steep))
	# Dere kıyısı: kum ve ıslak toprak
	var dr := ValleyShape.distance_to_river(x, z) - ValleyShape.river_half_width(z)
	c = c.lerp(Palette.SAND, 1.0 - smoothstep(0.2, 1.6, dr))
	c = c.lerp(Palette.EARTH.darkened(0.15), 1.0 - smoothstep(-0.6, 0.3, dr))
	# Patikalar
	var dp := ValleyShape.distance_to_path(x, z)
	c = c.lerp(Palette.EARTH_LIGHT, (1.0 - smoothstep(0.55, 1.25, dp + dn * 0.3)) * 0.85)
	return c


func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := EXTENT * 2.0 / RESOLUTION
	var row := RESOLUTION + 1
	for iz in row:
		for ix in row:
			var x := -EXTENT + ix * step
			var z := -EXTENT + iz * step
			var h := ValleyShape.height(x, z)
			var n := ValleyShape.normal(x, z)
			st.set_color(_ground_color(x, z, h, n))
			st.set_uv(Vector2(x, z) * 0.1)
			st.set_normal(n)
			st.add_vertex(Vector3(x, h, z))
	for iz in RESOLUTION:
		for ix in RESOLUTION:
			var a := iz * row + ix
			var b := a + 1
			var c := a + row
			var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	return st.commit()


func _add_box(pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	add_child(cs)


func _build_bounds() -> void:
	var L := PLAY_LIMIT
	_add_box(Vector3(0, 5, -L - 0.5), Vector3(L * 2 + 2, 20, 1))
	_add_box(Vector3(0, 5, L + 0.5), Vector3(L * 2 + 2, 20, 1))
	_add_box(Vector3(-L - 0.5, 5, 0), Vector3(1, 20, L * 2 + 2))
	_add_box(Vector3(L + 0.5, 5, 0), Vector3(1, 20, L * 2 + 2))


## Dere boyunca iki kıyıya ince duvarlar: oyuncu suya girmez, köprü tek geçiş olur.
## Köprünün önünde boşluk bırakılır; geçişi köprünün kendi yan duvarları ve kapıları yönetir.
func _build_river_barriers() -> void:
	var gap := ValleyShape.BRIDGE_GAP_HALF
	_river_barrier_range(-PLAY_LIMIT, ValleyShape.BRIDGE_Z - gap)
	_river_barrier_range(ValleyShape.BRIDGE_Z + gap, PLAY_LIMIT)


func _river_barrier_range(z_from: float, z_to: float) -> void:
	var count := maxi(int(ceil((z_to - z_from) / 1.5)), 1)
	var seg := (z_to - z_from) / count
	for i in count:
		var z := z_from + i * seg
		var z2 := z + seg
		for side: float in [-1.0, 1.0]:
			var p1 := Vector2(ValleyShape.river_x(z) + side * (ValleyShape.river_half_width(z) + 0.25), z)
			var p2 := Vector2(ValleyShape.river_x(z2) + side * (ValleyShape.river_half_width(z2) + 0.25), z2)
			var mid := (p1 + p2) * 0.5
			var dir := p2 - p1
			var y := ValleyShape.water_y(mid.y) + 1.0
			# Uçlarda 0.15 taşma: segmentler arasında aralık kalmasın, ama köprü boşluğuna girmesin.
			_add_box(Vector3(mid.x, y, mid.y), Vector3(0.3, 4.0, dir.length() + 0.15), atan2(dir.x, dir.y))
