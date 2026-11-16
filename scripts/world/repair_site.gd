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
## Mürekkep lekesi bir parçayı eritip çatlattı.
signal eroded(slot_id: String)

@export var site_id := "bridge"

var state := {}
## Son çatlamanın sebebi: "weak" (zayıf parça dayanamadı) ya da "ink" (lekeler eritti).
var crack_cause := "weak"


func _ready() -> void:
	add_to_group(SaveSystem.PERSIST_GROUP)
	state = Repair.new_state(site_id)


## Zamanla çatlayan yapılarda: tamamlanmış ve zayıf parçalıysa çalışma süresini say.
func _process(delta: float) -> void:
	var limit := Repair.crack_after_seconds(site_id)
	if Net.is_guest():
		return  # çevrimiçi katılan: çatlamaları ev sahibi bildirir
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
	crack_cause = "weak"
	state["done"] = false
	_on_cracked(ids)
	cracked.emit(ids)
	state_changed.emit()
	return ids


# --- Mürekkep lekeleri -----------------------------------------------------------------
## Lekelerin saldırabileceği (takılı parçası olan) yuvalar.
func damageable_slots() -> Array:
	var out := []
	for slot_id: String in state["slots"]:
		if Repair.is_filled(state, slot_id):
			out.append(slot_id)
	return out


func slot_health(slot_id: String) -> float:
	return Repair.slot_health(site_id, state, slot_id)


## Yapının genel sağlığı (0..1): tüm yuvaların kalan dayanıklılığı.
func health_ratio() -> float:
	var ids: Array = state["slots"].keys()
	if ids.is_empty():
		return 0.0
	var sum := 0.0
	for slot_id: String in ids:
		sum += slot_health(slot_id)
	return sum / float(ids.size())


## Aşınmış (ama çatlamamış) parça var mı?
func is_worn() -> bool:
	for slot_id: String in damageable_slots():
		if slot_health(slot_id) < 0.999:
			return true
	return false


## Leke bir yuvayı eritir. Döner: true = parça çatladı.
func damage_slot(slot_id: String, amount: float) -> bool:
	if not Repair.erode(state, site_id, slot_id, amount):
		return false
	crack_cause = "ink"
	state["done"] = false
	_on_cracked([slot_id])
	cracked.emit([slot_id])
	eroded.emit(slot_id)
	state_changed.emit()
	return true


func mend(amount: float) -> void:
	if Repair.mend(state, amount):
		state_changed.emit()


## Lekelerin toplandığı noktalar (alt sınıf daha uygun yerler verebilir).
## Varsayılan: yapının etkileşim noktaları (yapıya yürüyerek ulaşılan yerler).
func attack_points() -> Array:
	var out := []
	for c in get_children():
		if c is Interactable:
			out.append((c as Interactable).global_position)
	if out.is_empty():
		out.append(global_position)
	return out


# --- Çevrimiçi ----------------------------------------------------------------------
## Karşı taraftan gelen durumu uygula. Parça takılıp çatladıysa görünüm güncellenir;
## yalnızca aşınma değiştiyse (dalga sırasında sık) görünüme dokunulmaz.
func net_apply(st: Dictionary) -> void:
	var was_complete := is_complete()
	var before := _slot_shape()
	var old_cracked := []
	for id: String in state.get("slots", {}):
		if Repair.is_cracked(state, id):
			old_cracked.append(id)
	state = st.duplicate(true)
	var now_shape := _slot_shape()
	if now_shape != before:
		var new_cracks := []
		for id: String in state.get("slots", {}):
			if Repair.is_cracked(state, id) and not old_cracked.has(id):
				new_cracks.append(id)
		if not new_cracks.is_empty():
			crack_cause = "ink"
			_on_cracked(new_cracks)
		else:
			_apply_visuals(true)
	state_changed.emit()
	if not was_complete and is_complete():
		_on_completed()
		completed.emit()


func _slot_shape() -> String:
	var out := ""
	for id: String in state.get("slots", {}):
		var ss := Repair.slot_state(state, id)
		out += "%s=%s/%s;" % [id, str(ss.get("part", "")), str(Repair.is_cracked(state, id))]
	return out


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
