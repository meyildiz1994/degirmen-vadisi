class_name RepairSite
extends Node3D
## Onarılabilir yapıların ortak tabanı (köprü; Aşama 5'te değirmen duvarı ve çark).
## Durumu tutar, kaydeder, parça takar, zayıf parçaları çatlatır. Görünümü alt sınıf çizer
## (_apply_visuals). Etkileşim noktaları open_requested ile arayüze bağlanır.

signal open_requested(site: RepairSite)
signal slot_installed(slot_id: String, weak: bool)
signal completed
signal cracked(slot_ids: Array)
signal state_changed

@export var site_id := "bridge"

var state := {}


func _ready() -> void:
	add_to_group(SaveSystem.PERSIST_GROUP)
	state = Repair.new_state(site_id)


## Zamanla çatlayan yapılarda: tamamlanmış ve zayıf parçalıysa çalışma süresini say.
func _process(delta: float) -> void:
	var limit := Repair.crack_after_seconds(site_id)
	if limit <= 0.0 or not is_complete() or not Repair.has_weak(state) or get_tree().paused:
		return
	state["crossings"] = float(state.get("crossings", 0.0)) + delta
	if state["crossings"] >= limit:
		crack_weak_parts()


func display_name_key() -> String:
	return str(Repair.site(site_id).get("name", site_id))


func is_complete() -> bool:
	return bool(state.get("done", false)) and Repair.is_complete(state)


func install(slot_id: String, key: String) -> bool:
	if not Repair.install(state, site_id, slot_id, key, GameState.inventory):
		return false
	var weak := bool(Repair.slot_state(state, slot_id).get("weak", false))
	slot_installed.emit(slot_id, weak)
	_on_installed(slot_id, weak)
	if Repair.is_complete(state) and not state["done"]:
		state["done"] = true
		state["crossings"] = 0
		_on_completed()
		var ach := str(Repair.site(site_id).get("achievement", ""))
		if ach != "":
			PlatformServices.unlock_achievement(ach)
		completed.emit()
	state_changed.emit()
	return true


func crack_weak_parts() -> Array:
	var ids := Repair.crack_weak(state)
	if ids.is_empty():
		return ids
	state["done"] = false
	_on_cracked(ids)
	cracked.emit(ids)
	state_changed.emit()
	return ids


# --- Kayıt ---------------------------------------------------------------------------
func save_state(data: Dictionary) -> void:
	var world: Dictionary = data.get_or_add("world", {})
	var repairs: Dictionary = world.get_or_add("repairs", {})
	repairs[site_id] = state.duplicate(true)
	var done: Array = data.get_or_add("repaired", [])
	if is_complete() and not done.has(site_id):
		done.append(site_id)
	elif not is_complete():
		done.erase(site_id)


func load_state(data: Dictionary) -> void:
	var raw = data.get("world", {}).get("repairs", {}).get(site_id, {})
	state = Repair.sanitize(site_id, raw if typeof(raw) == TYPE_DICTIONARY else {})
	_apply_visuals(false)
	state_changed.emit()


# --- Alt sınıfın dolduracakları --------------------------------------------------------
func _apply_visuals(_animate: bool) -> void:
	pass


func _on_installed(_slot_id: String, _weak: bool) -> void:
	_apply_visuals(true)


func _on_completed() -> void:
	pass


func _on_cracked(_slot_ids: Array) -> void:
	_apply_visuals(true)
