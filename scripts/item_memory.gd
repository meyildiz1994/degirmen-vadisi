class_name ItemMemory
extends RefCounted
## Eşya hafızası: aletler kullandıkça aşınır ve koyulaşır, 50 kullanımdan sonra isim
## kazanır ("Yaşlı Meşe Balta") ve kısa bir geçmiş tutar ("12 ağaç kesti, köprüyü onardı").
## Aletler atölyede değil heybede, baş malzemesinden 1 birimle tamir edilir.

const NAME_AFTER_USES := 50
const EPITHETS := ["ITEM_EPITHET_OLD", "ITEM_EPITHET_LOYAL", "ITEM_EPITHET_WISE", "ITEM_EPITHET_PATIENT", "ITEM_EPITHET_BRAVE", "ITEM_EPITHET_TIRELESS"]
## Kaynak → geçmiş sayacı grubu.
const GROUPS := {"oak_tree": "trees", "pine_tree": "trees", "boulder": "rocks", "copper_vein": "copper", "iron_vein": "iron"}
const DEEDS := ["bridge", "mill_wall", "mill_wheel"]


## Bir kaynak tamamen alındığında (ağaç devrildi, kaya kırıldı) aletin geçmişine yaz.
static func record_gather(t: ToolItem, resource_id: String) -> void:
	var g := str(GROUPS.get(resource_id, ""))
	if g == "":
		return
	t.history[g] = int(t.history.get(g, 0)) + 1


## Yapı onarılınca o ana kadar kullanılmış her alet bu işe "katılmış" sayılır.
static func record_deed(tools: Array, site_id: String) -> void:
	for t: ToolItem in tools:
		if t.uses > 0 and not t.deeds.has(site_id):
			t.deeds.append(site_id)


## İsim hakkı: 50 kullanımda bir kez. Dönüş: yeni isim verildiyse true.
static func maybe_name(t: ToolItem) -> bool:
	if is_named(t) or t.uses < NAME_AFTER_USES:
		return false
	t.epithet = epithet_for(t)
	return true


static func is_named(t: ToolItem) -> bool:
	return t.epithet != "" or t.custom_name != ""


## Sıfat aletin kimliğinden (uid) seçilir: aynı alet her dilde aynı sıfatı alır.
static func epithet_for(t: ToolItem) -> String:
	return EPITHETS[absi(t.uid.hash()) % EPITHETS.size()]


## "12 ağaç kesti, 3 kaya kırdı, köprüyü onardı" (boşsa "").
static func history_text(t: ToolItem) -> String:
	var parts := []
	for g: String in ["trees", "rocks", "copper", "iron"]:
		var n := int(t.history.get(g, 0))
		if n > 0:
			parts.append(TranslationServer.translate("ITEM_HIST_" + g.to_upper()) % n)
	for d: String in DEEDS:
		if t.deeds.has(d):
			parts.append(TranslationServer.translate("ITEM_DEED_" + d.to_upper()))
	return ", ".join(parts)


## Aşınma koyuluğu 0..0.35: alet ne kadar çok kullanıldıysa o kadar koyu.
static func darkness(t: ToolItem) -> float:
	return clampf(float(t.uses) / 160.0, 0.0, 0.35)


## Görünüm için kaba seviye (0..3): mesh önbelleğini küçük tutar.
static func wear_level(t: ToolItem) -> int:
	return int(darkness(t) / 0.35 * 3.0 + 0.001)


# --- Tamir ------------------------------------------------------------------------------
static func repair_cost(t: ToolItem) -> Dictionary:
	return {t.head: 1}


static func can_repair(t: ToolItem, inv: Inventory) -> bool:
	return t.durability < t.max_durability and inv.count(t.head) >= 1


## Baş malzemesinden 1 birim harcar, dayanıklılığı doldurur.
static func repair(t: ToolItem, inv: Inventory) -> bool:
	if not can_repair(t, inv):
		return false
	inv.remove(t.head, 1)
	t.durability = t.max_durability
	t.repairs += 1
	inv.notify_tool_changed()
	return true
