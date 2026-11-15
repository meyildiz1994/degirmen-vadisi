extends MeshInstance3D
## Dere + şelale + gölet: ValleyShape hattını izleyen tek bir şerit mesh.
## Vertex rengi (kırmızı kanal) akış hızını taşır; şelalede su hızlanır.

const Z_START := -33.0
const Z_END := 33.0
const STEP := 0.4
const SEGMENTS_ACROSS := 4


func _ready() -> void:
	mesh = _build()
	material_override = WatercolorMaterials.water()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 0
	var along := 0.0
	var prev := Vector3.ZERO
	var z := Z_START
	while z <= Z_END:
		var cx := ValleyShape.river_x(z)
		var hw := ValleyShape.river_half_width(z) + 0.35
		var y := ValleyShape.water_y(z)
		var center := Vector3(cx, y, z)
		if rows > 0:
			along += center.distance_to(prev)
		prev = center
		var slope := absf(ValleyShape.water_y(z + 0.2) - ValleyShape.water_y(z - 0.2)) / 0.4
		var speed := 1.0 + clampf(slope, 0.0, 6.0) * 2.2
		for i in SEGMENTS_ACROSS + 1:
			var t := float(i) / SEGMENTS_ACROSS
			st.set_color(Color(speed, 0, 0))
			st.set_uv(Vector2(t, along))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(cx - hw + t * hw * 2.0, y, z))
		rows += 1
		z += STEP
	var w := SEGMENTS_ACROSS + 1
	for r in rows - 1:
		for i in SEGMENTS_ACROSS:
			var a := r * w + i
			st.add_index(a); st.add_index(a + 1); st.add_index(a + w)
			st.add_index(a + 1); st.add_index(a + w + 1); st.add_index(a + w)
	st.generate_normals()
	return st.commit()
