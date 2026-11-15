class_name ToolItem
extends RefCounted
## Envanterde slot kaplayan tek tek aletler. Her alet kendi geçmişini taşır
## (kullanım sayısı, aşınma, ne yaptığı). İsim, geçmiş metni ve tamir: item_memory.gd.

var uid := ""
var kind := "axe"         ## axe | pickaxe
var head := "stone"       ## baş malzemesi
var handle := "branch"    ## sap malzemesi
var power := 1.0
var weight := 1.0
var max_durability := 100
var durability := 100
var uses := 0
var custom_name := ""
var epithet := ""          ## isim kazanınca sıfat anahtarı (ITEM_EPITHET_*); dil değişince isim de çevrilir
var history := {}         ## "trees" / "rocks" / "copper" / "iron" -> adet
var deeds: Array = []     ## katıldığı onarımlar: "bridge", "mill_wall", "mill_wheel"
var repairs := 0


static func create(tool_kind: String, head_mat: String, handle_mat: String) -> ToolItem:
	var t := ToolItem.new()
	t.uid = "%s_%d_%d" % [tool_kind, Time.get_unix_time_from_system(), randi() % 100000]
	t.kind = tool_kind
	t.head = head_mat
	t.handle = handle_mat
	t.recalculate()
	t.durability = t.max_durability
	return t


func recalculate() -> void:
	power = Materials.edge_power(head)
	weight = Materials.tool_weight(head, handle)
	max_durability = Materials.tool_max_durability(head, handle)


func is_blunt() -> bool:
	return durability <= 0


## Körelmiş alet de çalışır, sadece yarı güçle (heybeden tamir edilebilir).
func effective_power() -> float:
	return power * (Materials.tune("blunt_power_factor", 0.5) if is_blunt() else 1.0)


func swing_time() -> float:
	return Materials.swing_time(weight)


func hits_for(resource_id: String) -> int:
	return Materials.hits_needed(effective_power(), float(Materials.resource(resource_id).get("hardness", 1.0)))


func wear(amount := 1) -> void:
	durability = maxi(durability - amount, 0)
	uses += 1


func durability_ratio() -> float:
	return float(durability) / float(maxi(max_durability, 1))


func display_name() -> String:
	if custom_name != "":
		return custom_name
	if epithet != "":
		return "%s %s" % [TranslationServer.translate(epithet), base_name()]
	return base_name()


func base_name() -> String:
	return "%s %s" % [TranslationServer.translate(Materials.display_name(head) + "_ADJ"), TranslationServer.translate(Materials.tool_name_key(kind))]


func to_dict() -> Dictionary:
	return {"uid": uid, "kind": kind, "head": head, "handle": handle, "durability": durability, "uses": uses,
		"name": custom_name, "epithet": epithet, "history": history.duplicate(), "deeds": deeds.duplicate(), "repairs": repairs}


static func from_dict(d: Dictionary) -> ToolItem:
	var t := ToolItem.new()
	t.uid = str(d.get("uid", ""))
	t.kind = str(d.get("kind", "axe"))
	t.head = str(d.get("head", "stone"))
	t.handle = str(d.get("handle", "branch"))
	t.recalculate()
	t.durability = clampi(int(d.get("durability", t.max_durability)), 0, t.max_durability)
	t.uses = int(d.get("uses", 0))
	t.custom_name = str(d.get("name", ""))
	t.epithet = str(d.get("epithet", ""))
	if t.epithet != "" and not ItemMemory.EPITHETS.has(t.epithet):
		t.epithet = ""
	var h = d.get("history", {})
	if typeof(h) == TYPE_DICTIONARY:
		for k in h:
			t.history[str(k)] = int(h[k])
	var dd = d.get("deeds", [])
	if typeof(dd) == TYPE_ARRAY:
		for x in dd:
			t.deeds.append(str(x))
	t.repairs = int(d.get("repairs", 0))
	return t
