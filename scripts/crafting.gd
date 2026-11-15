class_name Crafting
extends RefCounted
## Atölye: kalıp + yuvalara konan malzemeler → parça ya da alet.
## Sabit tarif yok. Her kalıp (data/molds.json) hangi malzemeleri kabul ettiğini ve
## istatistiklerin hangi özelliklerden nasıl hesaplanacağını söyler.
## choices: her yuva için seçilen kimlik (malzeme "oak" ya da parça "handle:oak"), boşsa "".

const MOLDS_PATH := "res://data/molds.json"
const TOOL_STATS := ["power", "durability", "weight", "speed"]

static var _molds := {}
static var _order: Array = []


static func _ensure() -> void:
	if not _molds.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MOLDS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Crafting: molds.json okunamadı")
		return
	_molds = parsed.get("molds", {})
	_order = parsed.get("order", _molds.keys())


static func mold_ids() -> Array:
	_ensure()
	return _order


static func mold(id: String) -> Dictionary:
	_ensure()
	return _molds.get(id, {})


static func slots(mold_id: String) -> Array:
	return mold(mold_id).get("slots", [])


static func is_tool_mold(mold_id: String) -> bool:
	return str(mold(mold_id).get("output", {}).get("kind", "")) == "tool"


static func empty_choices(mold_id: String) -> Array:
	var c := []
	c.resize(slots(mold_id).size())
	c.fill("")
	return c


# --- Parça kimlikleri: "kalıp:malzeme" -------------------------------------------------
static func part_key(mold_id: String, material: String) -> String:
	return "%s:%s" % [mold_id, material]


static func part_mold(key: String) -> String:
	return key.get_slice(":", 0)


static func part_material(key: String) -> String:
	return key.get_slice(":", 1)


static func part_name(key: String) -> String:
	return "%s %s" % [TranslationServer.translate(Materials.display_name(part_material(key)) + "_ADJ"),
		TranslationServer.translate(str(mold(part_mold(key)).get("name", "")))]


## Bir yuvaya konabilecek seçenekler. Parça yuvasında yalnız heybedeki uygun parçalar.
static func slot_options(mold_id: String, slot_index: int, inv: Inventory) -> Array:
	var s: Dictionary = slots(mold_id)[slot_index]
	if s.has("part"):
		var out := []
		for key: String in inv.parts:
			if part_mold(key) == str(s["part"]):
				out.append(key)
		out.sort()
		return out
	return s.get("accepts", [])


static func slot_amount(mold_id: String, slot_index: int) -> int:
	return int(slots(mold_id)[slot_index].get("amount", 1))


## Seçenek heybede yeterli mi?
static func option_available(mold_id: String, slot_index: int, option: String, inv: Inventory) -> bool:
	var n := slot_amount(mold_id, slot_index)
	if ":" in option:
		return inv.part_count(option) >= n
	return inv.count(option) >= n


static func is_complete(mold_id: String, choices: Array) -> bool:
	for c in choices:
		if str(c) == "":
			return false
	return choices.size() == slots(mold_id).size()


# --- Tahmin -----------------------------------------------------------------------------
## Seçimlere göre istatistikler (0-10). Eksik yuva varsa boş sözlük.
## Dönüş: [{key, name, value}] (arayüz sırası korunur).
static func predict(mold_id: String, choices: Array) -> Array:
	if not is_complete(mold_id, choices):
		return []
	if is_tool_mold(mold_id):
		return _tool_stats(_preview_tool(mold_id, choices))
	return stats_for_part(part_key(mold_id, str(choices[0])))


static func stats_for_part(key: String) -> Array:
	var m := mold(part_mold(key))
	var material := part_material(key)
	var out := []
	var defs: Dictionary = m.get("stats", {})
	for stat_key: String in defs:
		var d: Dictionary = defs[stat_key]
		var v := float(d.get("const", 0.0))
		for t: Array in d.get("terms", []):
			v += Materials.prop(material, str(t[1])) * float(t[2])
		out.append({"key": stat_key, "name": str(d.get("name", stat_key)), "value": clampf(v, 0.0, 10.0)})
	return out


static func stat_value(stats: Array, key: String) -> float:
	for s: Dictionary in stats:
		if s["key"] == key:
			return float(s["value"])
	return 0.0


static func _preview_tool(mold_id: String, choices: Array) -> ToolItem:
	var head := str(choices[0])
	var handle := part_material(str(choices[1]))
	return ToolItem.create(str(mold(mold_id)["output"]["tool"]), head, handle)


static func _tool_stats(t: ToolItem) -> Array:
	return [
		{"key": "power", "name": "STAT_POWER", "value": clampf(t.power, 0.0, 10.0)},
		{"key": "durability", "name": "STAT_DURABILITY", "value": clampf(t.max_durability / 15.0, 0.0, 10.0)},
		{"key": "weight", "name": "STAT_WEIGHT", "value": clampf(t.weight, 0.0, 10.0)},
		{"key": "speed", "name": "STAT_SPEED", "value": clampf(10.0 - t.weight, 0.0, 10.0)},
	]


## Alet kalıplarında örnek kaynaklarda kaç vuruş süreceği (oyuncu deneyerek öğrensin).
static func preview_hits(mold_id: String, choices: Array) -> Dictionary:
	if not is_tool_mold(mold_id) or not is_complete(mold_id, choices):
		return {}
	var t := _preview_tool(mold_id, choices)
	var res := ["oak_tree", "pine_tree"] if t.kind == "axe" else ["boulder", "copper_vein", "iron_vein"]
	var out := {}
	for r: String in res:
		out[r] = t.hits_for(r)
	return out


# --- Üretim -----------------------------------------------------------------------------
static func can_craft(inv: Inventory, mold_id: String, choices: Array) -> bool:
	if not is_complete(mold_id, choices):
		return false
	# Aynı malzeme iki yuvada seçilirse toplam miktar gerekir.
	var need := _cost(mold_id, choices)
	for id: String in need:
		var have := inv.part_count(id) if ":" in id else inv.count(id)
		if have < need[id]:
			return false
	if is_tool_mold(mold_id) and inv.tool_slots_free() <= 0:
		return false
	return true


static func _cost(mold_id: String, choices: Array) -> Dictionary:
	var need := {}
	for i in choices.size():
		var id := str(choices[i])
		need[id] = int(need.get(id, 0)) + slot_amount(mold_id, i)
	return need


## Üretir; sonuç: {"kind": "tool", "tool": ToolItem} ya da {"kind": "part", "key": String}. Olmazsa {}.
static func craft(inv: Inventory, mold_id: String, choices: Array) -> Dictionary:
	if not can_craft(inv, mold_id, choices):
		return {}
	var need := _cost(mold_id, choices)
	for id: String in need:
		if ":" in id:
			inv.remove_part(id, need[id])
		else:
			inv.remove(id, need[id])
	if is_tool_mold(mold_id):
		var t := _preview_tool(mold_id, choices)
		inv.add_tool(t)
		return {"kind": "tool", "tool": t}
	var key := part_key(mold_id, str(choices[0]))
	inv.add_part(key, 1)
	return {"kind": "part", "key": key}
