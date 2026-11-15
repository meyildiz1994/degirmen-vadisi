class_name Repair
extends RefCounted
## Onarım: her yapı (köprü, değirmen...) yuvalardan oluşur. Her yuva bir kalıbın
## parçasını ister ve istediği özellikleri eşik olarak gösterir (data/repairs.json).
## Eşiği tutmayan parça da takılır ama "zayıf" olur: bir süre dayanır, sonra çatlar.
##
## Durum sözlüğü (kayda doğrudan yazılır):
##   {"slots": {slot_id: {"part": "beam:oak", "weak": false} | {"cracked": "beam:pine"} | {}},
##    "crossings": 0, "done": false}

const PATH := "res://data/repairs.json"

static var _data := {}


static func _ensure() -> void:
	if not _data.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Repair: repairs.json okunamadı")
		return
	_data = parsed


static func site(site_id: String) -> Dictionary:
	_ensure()
	return _data.get("sites", {}).get(site_id, {})


static func slots(site_id: String) -> Array:
	return site(site_id).get("slots", [])


static func slot_def(site_id: String, slot_id: String) -> Dictionary:
	for s: Dictionary in slots(site_id):
		if s["id"] == slot_id:
			return s
	return {}


static func needs(site_id: String, slot_id: String) -> Dictionary:
	return slot_def(site_id, slot_id).get("needs", {})


static func crack_after() -> int:
	_ensure()
	return int(_data.get("crack_after_crossings", 2))


# --- Parçalar ------------------------------------------------------------------------
## Heybedeki, yuvanın kalıbına uyan parçalar; eşiği en iyi tutan önce.
static func candidates(site_id: String, slot_id: String, inv: Inventory) -> Array:
	var mold_id := str(slot_def(site_id, slot_id).get("mold", ""))
	var out := []
	for key: String in inv.parts:
		if Crafting.part_mold(key) == mold_id and inv.part_count(key) > 0:
			out.append(key)
	var n := needs(site_id, slot_id)
	out.sort_custom(func(a, b): return _score(a, n) > _score(b, n))
	return out


static func _score(key: String, n: Dictionary) -> float:
	var stats := Crafting.stats_for_part(key)
	var s := 0.0
	for k: String in n:
		s += minf(Crafting.stat_value(stats, k) - float(n[k]), 0.0) * 10.0 + Crafting.stat_value(stats, k)
	return s


## Eşiğin altında kalan özellikler (boşsa parça istenenleri karşılıyor).
static func failing(key: String, n: Dictionary) -> Array:
	var stats := Crafting.stats_for_part(key)
	var out := []
	for k: String in n:
		if Crafting.stat_value(stats, k) < float(n[k]) - 0.001:
			out.append(k)
	return out


static func meets(key: String, n: Dictionary) -> bool:
	return failing(key, n).is_empty()


# --- Durum ---------------------------------------------------------------------------
static func new_state(site_id: String) -> Dictionary:
	var st := {"slots": {}, "crossings": 0, "done": false}
	for s: Dictionary in slots(site_id):
		st["slots"][s["id"]] = {}
	return st


## Kayıttan gelen durumu bugünkü yuva listesine uydur (eksik yuva eklenir, bilinmeyen atılır).
static func sanitize(site_id: String, raw: Dictionary) -> Dictionary:
	var st := new_state(site_id)
	st["crossings"] = int(raw.get("crossings", 0))
	st["done"] = bool(raw.get("done", false))
	var raw_slots: Dictionary = raw.get("slots", {})
	for slot_id: String in st["slots"]:
		var v = raw_slots.get(slot_id, {})
		if typeof(v) == TYPE_DICTIONARY:
			st["slots"][slot_id] = v
	return st


static func slot_state(st: Dictionary, slot_id: String) -> Dictionary:
	return st["slots"].get(slot_id, {})


static func is_filled(st: Dictionary, slot_id: String) -> bool:
	return slot_state(st, slot_id).has("part")


static func is_cracked(st: Dictionary, slot_id: String) -> bool:
	return slot_state(st, slot_id).has("cracked")


static func is_complete(st: Dictionary) -> bool:
	for slot_id: String in st["slots"]:
		if not is_filled(st, slot_id):
			return false
	return true


static func has_weak(st: Dictionary) -> bool:
	for slot_id: String in st["slots"]:
		if bool(slot_state(st, slot_id).get("weak", false)):
			return true
	return false


## Yuvaya takılı sağlam parça sayısı, kalıba göre (eğitim kartı için).
static func filled_count(st: Dictionary, site_id: String, mold_id: String) -> int:
	var n := 0
	for s: Dictionary in slots(site_id):
		if s["mold"] == mold_id and is_filled(st, s["id"]):
			n += 1
	return n


static func slot_total(site_id: String, mold_id: String) -> int:
	var n := 0
	for s: Dictionary in slots(site_id):
		if s["mold"] == mold_id:
			n += 1
	return n


## Parçayı heybeden alıp yuvaya tak. Dolu yuvaya takılmaz.
static func install(st: Dictionary, site_id: String, slot_id: String, key: String, inv: Inventory) -> bool:
	var def := slot_def(site_id, slot_id)
	if def.is_empty() or is_filled(st, slot_id) or Crafting.part_mold(key) != def["mold"]:
		return false
	if not inv.remove_part(key, 1):
		return false
	st["slots"][slot_id] = {"part": key, "weak": not meets(key, def.get("needs", {}))}
	return true


## Zayıf parçaları çatlat; çatlayan yuvalar yeniden boşalır. Çatlayan yuva kimliklerini döndürür.
static func crack_weak(st: Dictionary) -> Array:
	var out := []
	for slot_id: String in st["slots"]:
		var s := slot_state(st, slot_id)
		if bool(s.get("weak", false)):
			st["slots"][slot_id] = {"cracked": s["part"]}
			out.append(slot_id)
	if not out.is_empty():
		st["crossings"] = 0
	return out
