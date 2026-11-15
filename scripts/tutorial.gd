class_name Tutorial
extends Node
## Metinsiz eğitim: ikonlu ipucu kartları adım adım yol gösterir.
##   0: dal ve küçük taş topla  →  1: atölyede ilk taş balta + taş kazma
##   2: bir ağaç kes, bir kaya kır  →  3: bitti, keşif görevi
## Görev kartında kısa metin de var; ipucu kartı tamamen ikon ve sayı.

enum Step { GATHER, CRAFT, USE, DONE }

const QUESTS := ["QUEST_FIRST_GATHER", "QUEST_FIRST_TOOLS", "QUEST_USE_TOOLS", "QUEST_EXPLORE"]

var hud: CanvasLayer
var _chopped := false
var _mined := false


func setup(h: CanvasLayer, gather_world: GatherWorld, workshop: Interactable) -> void:
	hud = h
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
		Step.GATHER:
			var items: Array = ["hand"]
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
		hud.hint_card.flash(made, 2.0)
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
