class_name Tutorial
extends Node
## Metinsiz tanıtım + eğitim: ikonlu ipucu kartları adım adım yol gösterir.
## İkonlar aktif cihaza göre değişir (WASD/fare, gamepad çubukları, dokunmatik).
##   0: yürü  →  1: etrafına bak  →  2: dal ve küçük taş topla
##   3: atölyede ilk taş balta + taş kazma  →  4: bir ağaç kes, bir kaya kır
##   5: köprüyü onar (2 kiriş + 1 bağlantı)  →  6: karşı kıyıda demir kaz  →  7: keşif
## Görev kartında kısa metin de var; ipucu kartı tamamen ikon ve sayı.

enum Step { MOVE, LOOK, GATHER, CRAFT, USE, BRIDGE, IRON, DONE }

const QUESTS := ["QUEST_WELCOME", "QUEST_WELCOME", "QUEST_FIRST_GATHER", "QUEST_FIRST_TOOLS", "QUEST_USE_TOOLS", "QUEST_REPAIR_BRIDGE", "QUEST_REACH_IRON", "QUEST_EXPLORE"]
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


func setup(h: CanvasLayer, gather_world: GatherWorld, workshop: Interactable, p: Player, b: RepairSite = null) -> void:
	hud = h
	player = p
	bridge = b
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


## Atölyede nabız gibi atacak kalıp (eğitim).
func _mold_to_highlight() -> String:
	if GameState.tutorial_step != Step.CRAFT:
		return ""
	var inv := GameState.inventory
	var handles := 0
	for key: String in inv.parts:
		if Crafting.part_mold(key) == "handle":
			handles += inv.part_count(key)
	var heads_left := int(not inv.has_tool("axe")) + int(not inv.has_tool("pickaxe"))
	if handles < heads_left and handles == 0:
		return "handle"
	if not inv.has_tool("axe"):
		return "axe_head"
	if not inv.has_tool("pickaxe"):
		return "pickaxe_head"
	return ""


func _set_step(s: int) -> void:
	if s == GameState.tutorial_step:
		return
	GameState.tutorial_step = s
	GameState.set_quest(QUESTS[s])
	if s == Step.USE and hud != null:
		hud.show_toast("MSG_FIRST_TOOLS")
		# Aletler heybede: heybe tuşunu da göster.
		hud.hint_card.flash(["axe", "pickaxe", "arrow", "inventory"], 3.5)


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
	if step == Step.IRON and _iron:
		step = Step.DONE
	_set_step(step)


func _refresh() -> void:
	_advance_if_ready()
	if hud.workshop_panel:
		hud.workshop_panel.set_highlight(_mold_to_highlight())
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
