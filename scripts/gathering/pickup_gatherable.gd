class_name PickupGatherable
extends Gatherable
## Elle tek dokunuşla alınan küçük şeyler: dal, küçük taş, kil topağı, saz demeti.
## Alınınca kaybolur, süre dolunca yerinde yumuşakça belirir.

var _visual: Node3D


func setup(mesh: Mesh, xform: Transform3D, outline := false) -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xform
	mi.material_override = WatercolorMaterials.vertex_colored(outline)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(mi)


func growing_time() -> float:
	return 1.2


func _apply_state() -> void:
	if _visual == null:
		return
	_visual.visible = state != State.DEPLETED
	_update_growth()


func _update_growth() -> void:
	_visual.scale = Vector3.ONE * (ease(growth, 0.5) if state == State.GROWING else 1.0)


func fx_point() -> Vector3:
	return global_position + Vector3(0, 0.2, 0)


func highlight_parts() -> Array:
	var out := []
	if _visual:
		for c in _visual.get_children():
			out.append([(c as MeshInstance3D).mesh, (c as MeshInstance3D).global_transform])
	return out
