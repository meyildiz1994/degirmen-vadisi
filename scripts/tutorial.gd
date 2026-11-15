class_name Tutorial
extends Node
## Metinsiz tanıtım + eğitim: ikonlu ipucu kartları adım adım yol gösterir.
## İkonlar aktif cihaza göre değişir (WASD/fare, gamepad çubukları, dokunmatik).
##   0: yürü  →  1: etrafına bak  →  2: dal ve küçük taş topla
##   3: atölyede ilk taş balta + taş kazma  →  4: bir ağaç kes, bir kaya kır  →  5: keşif
## Görev kartında kısa metin de var; ipucu kartı tamamen ikon ve sayı.

enum Step { MOVE, LOOK, GATHER, CRAFT, USE, DONE }

const QUESTS := ["QUEST_WELCOME", "QUEST_WELCOME", "QUEST_FIRST_GATHER", "QUEST_FIRST_TOOLS", "QUEST_USE_TOOLS", "QUEST_EXPLORE"]
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


func setup(h: CanvasLayer, gather_world: GatherWorld, workshop: Interactable, p: Player) -> void:
	hud = h
	player = p
	InputManager.device_changed.connect(func(_d): _refresh())
	GameState.inventory.changed.connect(_refresh)
	gather_world.resource_gathered.connect(_on_gathered)
	workshop.interacted.connect(_on_workshop)
	workshop.message_key = ""
	workshop.action_key = "ACTION_USE"
	_advance_if_ready()
	GameState.set_quest(QUESTS[GameState.tutorial_step])
	_refresh()


func _needed() -> Dictionary:
	var total := {}
	for kind: String in ["axe", "pickaxe"]:
		if GameState.inventory.has_tool(kind):
			continue
		var cost: Dictionary = Materials.first_tool_recipe(kind).get("cost", {})
		for id in cost:
			total[id] = int(total.get(id, 0)) + int(cost[id])
	return total


func _set_step(s: int) -> void:
	if s == GameState.tutorial_step:
		return
	GameState.tutorial_step = s
	GameState.set_quest(QUESTS[s])


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
		step = Step.DONE
	_set_step(step)


func _refresh() -> void:
	_advance_if_ready()
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
			card.set_persistent(["branch", "plus", "stone", "arrow", "workshop", "arrow", "axe", "pickaxe"])
		Step.USE:
			card.set_persistent([["axe", "", _chopped], "arrow", ["tree", "", _chopped], ["pickaxe", "", _mined], "arrow", ["rock", "", _mined]])
		_:
			card.set_persistent([])


func _on_gathered(resource_id: String) -> void:
	if resource_id.ends_with("_tree"):
		_chopped = true
	elif resource_id in ["boulder", "copper_vein", "iron_vein"]:
		_mined = true
	_refresh()


## Atölye: Aşama 3'te kalıplı üretim arayüzü açılacak. Şimdilik ilk aletleri yapar.
func _on_workshop(_by: Node) -> void:
	var made := []
	for kind: String in ["axe", "pickaxe"]:
		if GameState.inventory.has_tool(kind):
			continue
		var r := Materials.first_tool_recipe(kind)
		if GameState.inventory.spend(r.get("cost", {})):
			GameState.inventory.add_tool(ToolItem.create(kind, str(r.get("head", "stone")), str(r.get("handle", "branch"))))
			made.append(kind)
	if not made.is_empty():
		AudioManager.play_sfx("craft_success")
		hud.show_toast("MSG_FIRST_TOOLS")
		# Aletler heybede: heybe tuşunu da göster.
		hud.hint_card.flash(made + ["arrow", "inventory"], 3.5)
	elif not _needed().is_empty():
		AudioManager.play_sfx("craft_fail")
		var items: Array = []
		var need := _needed()
		for id: String in need:
			items.append([id, "%d/%d" % [mini(GameState.inventory.count(id), need[id]), need[id]]])
		items.append("arrow")
		items.append("workshop")
		hud.hint_card.flash(items, 3.0)
	else:
		hud.show_toast("MSG_WORKSHOP")
	_refresh()


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
