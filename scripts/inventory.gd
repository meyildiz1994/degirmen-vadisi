class_name Inventory
extends RefCounted
## Heybe. Malzemeler ve tohumlar sınırsız yığılır; yalnızca aletler slot kaplar.
## Alet seçimi otomatiktir: hedef kaynağa en hızlı vuran alet kullanılır.

signal changed
signal item_added(id: String, amount: int)
signal tool_added(tool: ToolItem)

const TOOL_SLOTS := 6

var items := {}                    ## id -> adet (malzeme + tohum)
var tools: Array[ToolItem] = []


func count(id: String) -> int:
	return int(items.get(id, 0))


func has(id: String, amount := 1) -> bool:
	return count(id) >= amount


func has_all(cost: Dictionary) -> bool:
	for id in cost:
		if not has(id, int(cost[id])):
			return false
	return true


func add(id: String, amount := 1) -> void:
	if amount <= 0:
		return
	items[id] = count(id) + amount
	item_added.emit(id, amount)
	changed.emit()


func remove(id: String, amount := 1) -> bool:
	if not has(id, amount):
		return false
	items[id] = count(id) - amount
	if items[id] <= 0:
		items.erase(id)
	changed.emit()
	return true


func spend(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	for id in cost:
		remove(id, int(cost[id]))
	return true


func seed_total() -> int:
	var n := 0
	for id in Materials.seed_ids():
		n += count(id)
	return n


func first_seed() -> String:
	for id in Materials.seed_ids():
		if has(id):
			return id
	return ""


# --- Aletler ---------------------------------------------------------------------
func tool_slots_free() -> int:
	return TOOL_SLOTS - tools.size()


func add_tool(t: ToolItem) -> bool:
	if tools.size() >= TOOL_SLOTS:
		return false
	tools.append(t)
	tool_added.emit(t)
	changed.emit()
	return true


func has_tool(kind: String) -> bool:
	for t in tools:
		if t.kind == kind:
			return true
	return false


## Kaynak için en az vuruşla, eşitlikte daha hızlı sallanan alet.
func best_tool(kind: String, resource_id: String) -> ToolItem:
	var best: ToolItem = null
	var best_score := INF
	for t in tools:
		if t.kind != kind:
			continue
		var score := t.hits_for(resource_id) * t.swing_time()
		if score < best_score:
			best_score = score
			best = t
	return best


func notify_tool_changed() -> void:
	changed.emit()


# --- Kayıt ---------------------------------------------------------------------
func to_dict() -> Dictionary:
	var tl := []
	for t in tools:
		tl.append(t.to_dict())
	return {"items": items.duplicate(), "tools": tl}


func from_dict(d: Dictionary) -> void:
	items.clear()
	var src: Dictionary = d.get("items", {})
	for id in src:
		if Materials.is_material(id) or Materials.is_seed(id):
			items[id] = int(src[id])
	tools.clear()
	for td in d.get("tools", []):
		if typeof(td) == TYPE_DICTIONARY:
			tools.append(ToolItem.from_dict(td))
	changed.emit()
