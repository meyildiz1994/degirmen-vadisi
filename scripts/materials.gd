class_name Materials
extends RefCounted
## Malzeme, tohum ve kaynak verileri (data/*.json) + bunlardan türeyen formüller.
## Sabit tarif yok: alet gücü, ağırlığı ve dayanıklılığı malzeme özelliklerinden hesaplanır.

const MATERIALS_PATH := "res://data/materials.json"
const RESOURCES_PATH := "res://data/resources.json"

static var _materials := {}
static var _seeds := {}
static var _resources := {}
static var _tools := {}
static var gathering := {}


static func _ensure() -> void:
	if not _materials.is_empty():
		return
	var m := _load_json(MATERIALS_PATH)
	_materials = m.get("materials", {})
	_seeds = m.get("seeds", {})
	var r := _load_json(RESOURCES_PATH)
	_resources = r.get("resources", {})
	_tools = r.get("tools", {})
	gathering = r.get("gathering", {})


static func _load_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Materials: %s okunamadı" % path)
		return {}
	return parsed


# --- Sorgular -------------------------------------------------------------------
static func is_material(id: String) -> bool:
	_ensure()
	return _materials.has(id)


static func is_seed(id: String) -> bool:
	_ensure()
	return _seeds.has(id)


## Malzeme veya tohum tanımı (ad anahtarı, ikon, renk...).
static func item(id: String) -> Dictionary:
	_ensure()
	return _materials.get(id, _seeds.get(id, {}))


static func prop(id: String, property: String) -> float:
	return float(item(id).get(property, 0.0))


static func display_name(id: String) -> String:
	return str(item(id).get("name", id))


static func color(id: String) -> Color:
	var c: Array = item(id).get("color", [0.5, 0.5, 0.5])
	return Color(c[0], c[1], c[2])


static func icon(id: String) -> String:
	return str(item(id).get("icon", "lump"))


static func material_ids() -> Array:
	_ensure()
	return _materials.keys()


static func seed_ids() -> Array:
	_ensure()
	return _seeds.keys()


static func resource(id: String) -> Dictionary:
	_ensure()
	return _resources.get(id, {})


static func tool_name_key(kind: String) -> String:
	_ensure()
	return str(_tools.get(kind, {}).get("name", kind))


static func tune(key: String, fallback: float) -> float:
	_ensure()
	return float(gathering.get(key, fallback))


# --- Alet formülleri (Aşama 3'teki kalıp sistemi de bunları kullanır) ------------
## Kesme/kırma gücü: baş malzemenin sertliği, esneklik ve işlenebilirlikten gelen
## "ağız tutma" çarpanıyla. Taş sert ama kırılgan; demir hem sert hem işlenebilir.
static func edge_power(head: String) -> float:
	var edge := clampf(0.45 + 0.09 * (prop(head, "flexibility") + prop(head, "workability")), 0.45, 1.0)
	return prop(head, "hardness") * edge


static func tool_weight(head: String, handle: String) -> float:
	return prop(head, "weight") * 0.6 + prop(handle, "weight") * 0.4


static func tool_max_durability(head: String, handle: String) -> int:
	return int(round(prop(head, "durability") * 10.0 + prop(handle, "durability") * 6.0))


## Bir kaynağı tamamlamak için gereken ilerleme (normal vuruş = 1, tatlı vuruş = 2).
## Örn. taş balta (güç ≈5) meşede 5, demir balta (güç ≈8) meşede 2 vuruş.
static func hits_needed(power: float, resource_hardness: float) -> int:
	var base := tune("base_hits", 5.0)
	var ratio := resource_hardness / maxf(power, 0.5)
	var hits := base * pow(ratio, tune("hit_exponent", 2.0))
	if power < resource_hardness:
		hits *= tune("softer_tool_penalty", 1.5)  # yavaş ama asla engellenmez
	return clampi(int(ceil(hits - 0.001)), 1, int(tune("max_hits", 24.0)))


## Vuruş aralığı (saniye): ağır alet yavaş sallanır.
static func swing_time(weight: float) -> float:
	return tune("swing_base", 0.34) + tune("swing_per_weight", 0.06) * weight
