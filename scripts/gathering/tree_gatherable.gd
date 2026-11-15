class_name TreeGatherable
extends Gatherable
## Ağaç: baltayla kesilir, devrilir, kütük kalır; kütükten fidan çıkar ve büyür.
## Görsel TreeField'daki MultiMesh örnekleridir; bu düğüm yalnızca durum ve hedef.

var field: TreeField
var data: TreeField.TreeData
var _last_hitter := Vector3.ZERO


func depleted_time() -> float:
	return float(_def.get("stump_time", 60.0))


func growing_time() -> float:
	return float(_def.get("sapling_time", 120.0))


func can_focus() -> bool:
	return data != null and data.active and super.can_focus()


func start_growing(start_growth := 0.0) -> void:
	_enter_growing(start_growth)


func set_hitter(pos: Vector3) -> void:
	_last_hitter = pos


func complete() -> void:
	field.start_fall(data, _last_hitter)
	super.complete()


func _apply_state() -> void:
	if field:
		field.on_state_changed(data)


func _update_growth() -> void:
	field.update_growth(data)


func _on_hit(_sweet: bool) -> void:
	field.shake(data, _last_hitter)


func fx_point() -> Vector3:
	return data.base + Vector3(0, 1.0, 0)


func highlight_parts() -> Array:
	var out := []
	for part in data.parts:
		var mm: MultiMesh = part[0]
		out.append([mm.mesh, field.global_transform * mm.get_instance_transform(part[1])])
	return out
