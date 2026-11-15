class_name Tutorial
extends Node
## Metinsiz tanıtım + eğitim: ikonlu ipucu kartları adım adım yol gösterir.
## İkonlar aktif cihaza göre değişir (WASD/fare, gamepad çubukları, dokunmatik).
##   0: yürü  →  1: etrafına bak  →  2: dal ve küçük taş topla
##   3: atölyede ilk taş balta + taş kazma  →  4: bir ağaç kes, bir kaya kır
##   5: köprüyü onar (2 kiriş + 1 bağlantı)  →  6: karşı kıyıda demir kaz
##   7: demirden balta/kazma yap  →  8: eski değirmeni incele  →  9: duvarı ör (3 Duvar Taşı)
##   10: çarkı onar (aks + dişli + 6 kanat)  →  11: final, serbest oyun
## Görev kartında kısa metin de var; ipucu kartı tamamen ikon ve sayı.

enum Step { MOVE, LOOK, GATHER, CRAFT, USE, BRIDGE, IRON, IRON_TOOL, MILL, MILL_WALL, MILL_WHEEL, DONE }

const QUESTS := ["QUEST_WELCOME", "QUEST_WELCOME", "QUEST_FIRST_GATHER", "QUEST_FIRST_TOOLS", "QUEST_USE_TOOLS",
	"QUEST_REPAIR_BRIDGE", "QUEST_REACH_IRON", "QUEST_IRON_TOOLS", "QUEST_VISIT_MILL", "QUEST_REPAIR_WALL",
	"QUEST_REPAIR_WHEEL", "QUEST_VALLEY_DONE"]
## Onarım adımları: hangi yer, hangi kalıplar (atölyede sırayla vurgulanır).
const WALL_MOLDS := ["block"]
const WHEEL_MOLDS := ["axle", "gear", "paddle"]
## Görev işaretçisi bu mesafeden yakında gizlenir (metre).
const MARKER_HIDE := 4.0
const MOVE_GOAL := 4.0      ## metre
const LOOK_GOAL := 1.4      ## radyan (toplam kamera dönüşü)

var hud: CanvasLayer
var player: Player
var _walked := 0.0
var _looked := 0.0
var _last_pos := Vector3.INF
var _last_yaw := 0.0
var _last_pitch := 0.0
var _chopped := false
var _mined := false
var _iron := false
var bridge: RepairSite
var workshop_node: Interactable
var mill: Interactable
var iron_spot := Vector3.INF
var _mill_seen := false
var mill_node: Mill


func setup(h: CanvasLayer, gather_world: GatherWorld, workshop: Interactable, p: Player, b: RepairSite = null,
		mill_point: Interactable = null, iron_pos := Vector3.INF, m: Mill = null) -> void:
	hud = h
	player = p
	bridge = b
	workshop_node = workshop
	mill = mill_point
	iron_spot = iron_pos
	if mill != null:
		mill.interacted.connect(func(_by): _mill_seen = true; _refresh())
	mill_node = m
	if m != null:
		for site: RepairSite in [m.wall, m.wheel]:
			site.state_changed.connect(_refresh)
			site.cracked.connect(func(_ids): hud.show_toast("MSG_MILL_CRACKED", 4.5))
		m.wall.completed.connect(func(): hud.show_toast("MSG_WALL_DONE", 3.5))
	if b != null:
		b.state_changed.connect(_refresh)
		b.cracked.connect(func(_ids): hud.show_toast("MSG_BRIDGE_CRACKED", 4.5))
		b.completed.connect(func(): hud.show_toast("MSG_BRIDGE_REPAIRED", 4.0))
	InputManager.device_changed.connect(func(_d): _refresh())
	GameState.inventory.changed.connect(_refresh)
	gather_world.resource_gathered.connect(_on_gathered)
	workshop.interacted.connect(_on_workshop)
	h.workshop_panel.crafted.connect(func(_m, _r): _refresh())
	workshop.message_key = ""
	workshop.action_key = "ACTION_USE"
	_advance_if_ready()
	GameState.set_quest(QUESTS[GameState.tutorial_step])
	_refresh()


## İlk taş balta ve kazma için gereken toplam (heybedeki saplar düşülür).
## Sap kalıbı 1 dal, baş kalıbı 2 taş + 1 sap ister (data/molds.json).
func _needed() -> Dictionary:
	var inv := GameState.inventory
	var heads := 0
	for kind: String in ["axe", "pickaxe"]:
		if not inv.has_tool(kind):
			heads += 1
	var handles_have := 0
	for key: String in inv.parts:
		if Crafting.part_mold(key) == "handle":
			handles_have += inv.part_count(key)
	var total := {}
	if heads > 0:
		total["stone"] = heads * Crafting.slot_amount("axe_head", 0)
		var branches := maxi(heads - handles_have, 0)
		if branches > 0:
			total["branch"] = branches
	return total


## Atölyede nabız gibi atacak kalıp (eğitim). Köprü adımında eksik kiriş/bağlantı kalıbı.
func _mold_to_highlight() -> String:
	var inv := GameState.inventory
	if GameState.tutorial_step == Step.BRIDGE and bridge != null:
		for mold_id: String in ["beam", "connector"]:
			var missing := Repair.slot_total(bridge.site_id, mold_id) - Repair.filled_count(bridge.state, bridge.site_id, mold_id)
			if missing > _parts_of(mold_id):
				return mold_id
		return ""
	if GameState.tutorial_step in [Step.MILL_WALL, Step.MILL_WHEEL]:
		var site := _step_site()
		return _missing_mold(site, _step_molds()) if site != null else ""
	if GameState.tutorial_step == Step.IRON_TOOL:
		return "axe_head" if inv.count("iron") >= Crafting.slot_amount("axe_head", 0) else ""
	if GameState.tutorial_step != Step.CRAFT:
		return ""
	var handles := _parts_of("handle")
	var heads_left := int(not inv.has_tool("axe")) + int(not inv.has_tool("pickaxe"))
	if handles < heads_left and handles == 0:
		return "handle"
	if not inv.has_tool("axe"):
		return "axe_head"
	if not inv.has_tool("pickaxe"):
		return "pickaxe_head"
	return ""


func _parts_of(mold_id: String) -> int:
	var n := 0
	for key: String in GameState.inventory.parts:
		if Crafting.part_mold(key) == mold_id:
			n += GameState.inventory.part_count(key)
	return n


func _set_step(s: int) -> void:
	if s == GameState.tutorial_step:
		return
	GameState.tutorial_step = s
	GameState.set_quest(QUESTS[s])
	if s == Step.USE and hud != null:
		hud.show_toast("MSG_FIRST_TOOLS")
		# Aletler heybede: heybe tuşunu da göster.
		hud.hint_card.flash(["axe", "pickaxe", "arrow", "inventory"], 3.5)
	elif s == Step.MILL and hud != null:
		hud.show_toast("MSG_IRON_TOOL_MADE", 4.0)
	elif s == Step.MILL_WALL and hud != null:
		hud.show_toast("MSG_MILL_SEEN", 5.0)


func _advance_if_ready() -> void:
	var inv := GameState.inventory
	var step := GameState.tutorial_step
	if step == Step.MOVE and _walked >= MOVE_GOAL:
		step = Step.LOOK
	if step == Step.LOOK and _looked >= LOOK_GOAL:
		step = Step.GATHER
	if step == Step.GATHER and (inv.has_all(_needed()) or _needed().is_empty()):
		step = Step.CRAFT
	if step == Step.CRAFT and inv.has_tool("axe") and inv.has_tool("pickaxe"):
		step = Step.USE
	if step == Step.USE and _chopped and _mined:
		step = Step.BRIDGE
	if step == Step.BRIDGE and bridge != null and bridge.is_complete():
		step = Step.IRON
	if step == Step.IRON and (_iron or inv.count("iron") > 0 or _has_iron_tool()):
		step = Step.IRON_TOOL
	if step == Step.IRON_TOOL and _has_iron_tool():
		step = Step.MILL
	if step == Step.MILL and (_mill_seen or (mill_node != null and mill_node.wall.is_complete())):
		step = Step.MILL_WALL
	if step == Step.MILL_WALL and mill_node != null and mill_node.wall.is_complete():
		step = Step.MILL_WHEEL
	if step == Step.MILL_WHEEL and mill_node != null and mill_node.wheel.is_complete() and mill_node.wall.is_complete():
		step = Step.DONE
	_set_step(step)


func _has_iron_tool() -> bool:
	for t: ToolItem in GameState.inventory.tools:
		if t.head == "iron":
			return true
	return false


func _refresh() -> void:
	_advance_if_ready()
	if hud.workshop_panel:
		hud.workshop_panel.set_highlight(_mold_to_highlight())
	if hud.repair_panel:
		hud.repair_panel.guide_enabled = GameState.tutorial_step in [Step.BRIDGE, Step.MILL_WALL, Step.MILL_WHEEL]
	var card: IconHintCard = hud.hint_card
	match GameState.tutorial_step:
		Step.MOVE:
			card.set_persistent(["move", "arrow", ["check", "", true]])
		Step.LOOK:
			card.set_persistent(["look", "arrow", ["check", "", true]])
		Step.GATHER:
			var items: Array = ["interact", "hand"]
			var need := _needed()
			for id: String in need:
				items.append([id, "%d/%d" % [mini(GameState.inventory.count(id), need[id]), need[id]]])
			card.set_persistent(items)
		Step.CRAFT:
			card.set_persistent(["workshop", "arrow", "mold_handle", "plus", "stone", "arrow", "axe", "pickaxe"])
		Step.USE:
			card.set_persistent([["axe", "", _chopped], "arrow", ["tree", "", _chopped], ["pickaxe", "", _mined], "arrow", ["rock", "", _mined]])
		Step.BRIDGE:
			card.set_persistent(_bridge_card())
		Step.IRON:
			card.set_persistent(["bridge", "arrow", "pickaxe", "arrow", "iron"])
		Step.IRON_TOOL:
			var need := Crafting.slot_amount("axe_head", 0)
			card.set_persistent([["iron", "%d/%d" % [mini(GameState.inventory.count("iron"), need), need]], "arrow", "workshop", "arrow", "axe"])
		Step.MILL:
			card.set_persistent(["axe", "arrow", "mill"])
		Step.MILL_WALL, Step.MILL_WHEEL:
			card.set_persistent(_site_card(_step_site(), _step_molds(), "mill"))
		_:
			card.set_persistent([])


func _on_gathered(resource_id: String) -> void:
	if resource_id.ends_with("_tree"):
		_chopped = true
	elif resource_id in ["boulder", "copper_vein", "iron_vein"]:
		_mined = true
	if resource_id == "iron_vein":
		_iron = true
	_refresh()


## Köprü kartı: kiriş ve bağlantı (takılı / gereken) → köprü. Elde parça yoksa önce atölye.
func _bridge_card() -> Array:
	if bridge == null:
		return []
	var items: Array = []
	var any_part := false
	for mold_id: String in ["beam", "connector"]:
		var total := Repair.slot_total(bridge.site_id, mold_id)
		var done := Repair.filled_count(bridge.state, bridge.site_id, mold_id)
		items.append(["mold_" + mold_id, "%d/%d" % [done, total], done >= total])
		for key: String in GameState.inventory.parts:
			if Crafting.part_mold(key) == mold_id and GameState.inventory.part_count(key) > 0:
				any_part = true
	items.append("arrow")
	items.append("bridge")
	if not any_part:
		items.push_front("arrow")
		items.push_front("workshop")
	return items


# --- Onarım adımları (köprü sonrası değirmen) -----------------------------------------
func _step_site() -> RepairSite:
	if mill_node == null:
		return null
	match GameState.tutorial_step:
		Step.MILL_WALL: return mill_node.wall
		Step.MILL_WHEEL: return mill_node.wheel
	return null


func _step_molds() -> Array:
	return WALL_MOLDS if GameState.tutorial_step == Step.MILL_WALL else WHEEL_MOLDS


## Takılı + heybedeki parçalar yetmiyorsa atölyede yapılacak ilk kalıp; yoksa "".
func _missing_mold(site: RepairSite, molds: Array) -> String:
	for mold_id: String in molds:
		var missing := Repair.slot_total(site.site_id, mold_id) - Repair.filled_count(site.state, site.site_id, mold_id)
		if missing > _parts_of(mold_id):
			return mold_id
	return ""


## Kart: her kalıp için takılı/gereken → hedef. Parça yoksa önce atölye.
func _site_card(site: RepairSite, molds: Array, goal_icon_id: String) -> Array:
	if site == null:
		return []
	var items: Array = []
	for mold_id: String in molds:
		var total := Repair.slot_total(site.site_id, mold_id)
		var done := Repair.filled_count(site.state, site.site_id, mold_id)
		items.append(["mold_" + mold_id, "%d/%d" % [done, total], done >= total])
	items.append("arrow")
	items.append(goal_icon_id)
	if _missing_mold(site, molds) != "":
		items.push_front("arrow")
		items.push_front("workshop")
	return items


## Görev işaretçisinin gösterdiği yer (yoksa INF). Köprü adımında parça yoksa atölye.
func goal_position() -> Vector3:
	match GameState.tutorial_step:
		Step.CRAFT:
			return _pos(workshop_node)
		Step.BRIDGE:
			if bridge == null:
				return Vector3.INF
			return _pos(workshop_node) if _bridge_needs_parts() else bridge.global_position + Vector3(0, 1.2, 0)
		Step.IRON:
			return iron_spot
		Step.IRON_TOOL:
			if GameState.inventory.count("iron") < Crafting.slot_amount("axe_head", 0):
				return iron_spot
			return _pos(workshop_node)
		Step.MILL:
			return _pos(mill)
		Step.MILL_WALL, Step.MILL_WHEEL:
			var site := _step_site()
			if site == null:
				return Vector3.INF
			if _missing_mold(site, _step_molds()) != "":
				return _pos(workshop_node)
			var it: Interactable = site.get("interactable")
			return _pos(it)
	return Vector3.INF


## İşaretçideki küçük ikon: hedefin ne olduğu.
func goal_icon() -> String:
	var p := goal_position()
	if p == Vector3.INF:
		return ""
	if workshop_node != null and p == _pos(workshop_node):
		return "workshop"
	if p == iron_spot:
		return "iron"
	if mill != null and p == _pos(mill):
		return "mill"
	if GameState.tutorial_step in [Step.MILL_WALL, Step.MILL_WHEEL]:
		return "mill"
	return "bridge"


func _pos(n: Node3D) -> Vector3:
	return n.global_position + Vector3(0, 1.2, 0) if n != null and n.is_inside_tree() else Vector3.INF


func _bridge_needs_parts() -> bool:
	for mold_id: String in ["beam", "connector"]:
		var missing := Repair.slot_total(bridge.site_id, mold_id) - Repair.filled_count(bridge.state, bridge.site_id, mold_id)
		if missing > _parts_of(mold_id):
			return true
	return false


## Atölye her zaman kalıp panelini açar; eğitimdeyken doğru kalıp nabız gibi atar.
func _on_workshop(_by: Node) -> void:
	hud.workshop_panel.set_highlight(_mold_to_highlight())
	hud.open_workshop()


## Yürüme ve bakma adımları: oyuncunun gerçekten yürüdüğü ve kamerayı çevirdiği ölçülür.
func _process(_delta: float) -> void:
	var step := GameState.tutorial_step
	if player == null or step > Step.LOOK:
		set_process(false)
		return
	var pos := player.global_position
	if _last_pos != Vector3.INF:
		_walked += Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
		_looked += absf(angle_difference(_last_yaw, player.yaw)) + absf(player.pitch - _last_pitch)
	_last_pos = pos
	_last_yaw = player.yaw
	_last_pitch = player.pitch
	if (step == Step.MOVE and _walked >= MOVE_GOAL) or (step == Step.LOOK and _looked >= LOOK_GOAL):
		AudioManager.play_ui("ui_click")
		hud.hint_card.flash(["check"], 0.8)
		_refresh()
