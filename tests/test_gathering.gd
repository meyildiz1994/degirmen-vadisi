extends Node
## Toplama sistemi duman testi (başsız):
##   godot --headless --path . res://tests/test_gathering.tscn
## Formüller, heybe kaydı, ritim vuruşu, ağaç kesme/yeniden büyüme ve kayıt/yükleme.

var _fails := 0
var gs: Node


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_fails += 1
		print("  FAIL ", msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	gs = GameState
	print("== formüller")
	var stone_axe := ToolItem.create("axe", "stone", "branch")
	var iron_axe := ToolItem.create("axe", "iron", "oak")
	check(stone_axe.hits_for("oak_tree") == 5, "taş balta meşe = 5 vuruş (%d)" % stone_axe.hits_for("oak_tree"))
	check(iron_axe.hits_for("oak_tree") == 2, "demir balta meşe = 2 vuruş (%d)" % iron_axe.hits_for("oak_tree"))
	var stone_pick := ToolItem.create("pickaxe", "stone", "branch")
	var iron_hits := stone_pick.hits_for("iron_vein")
	check(iron_hits > 5 and iron_hits <= 24, "yumuşak alet yavaş ama engellenmez (%d)" % iron_hits)
	check(iron_axe.swing_time() != stone_axe.swing_time(), "sallanma süresi ağırlığa bağlı")
	stone_axe.durability = 0
	check(stone_axe.hits_for("oak_tree") > 5, "körelmiş alet daha yavaş")

	print("== kalıplar")
	var pine := Crafting.stats_for_part("paddle:pine")
	var oak := Crafting.stats_for_part("paddle:oak")
	var stone := Crafting.stats_for_part("paddle:stone")
	check(Crafting.stat_value(pine, "water") < Crafting.stat_value(oak, "water"), "çam kanat suya meşeden az dayanır (çürür)")
	check(Crafting.stat_value(stone, "lightness") < 2.0, "taş kanat çok ağır (çark dönmez)")
	check(Crafting.stat_value(oak, "lightness") >= 3.5 and Crafting.stat_value(oak, "water") >= 6.0, "meşe kanat dengeli")
	var st_axe := Crafting.predict("axe_head", ["stone", "handle:pine"])
	var cu_axe := Crafting.predict("axe_head", ["copper", "handle:pine"])
	var fe_axe := Crafting.predict("axe_head", ["iron", "handle:pine"])
	check(Crafting.stat_value(fe_axe, "power") > Crafting.stat_value(st_axe, "power"), "demir başlı balta en güçlü")
	check(Crafting.stat_value(cu_axe, "durability") < Crafting.stat_value(st_axe, "durability"), "bakır başlı çabuk körelir")
	check(Crafting.stat_value(st_axe, "weight") > Crafting.stat_value(cu_axe, "weight"), "taş başlı ağır")
	check(Crafting.predict("beam", [""]).is_empty(), "boş yuvada tahmin yok")
	print("== heybe")
	var inv := Inventory.new()
	inv.add("oak", 3)
	inv.add("oak", 1000)
	check(inv.count("oak") == 1003, "malzemeler sınırsız yığılır")
	for i in Inventory.TOOL_SLOTS:
		inv.add_tool(ToolItem.create("axe", "stone", "branch"))
	check(not inv.add_tool(ToolItem.create("axe", "stone", "branch")), "slotlar dolunca alet eklenmez")
	var inv2 := Inventory.new()
	inv2.from_dict(JSON.parse_string(JSON.stringify(inv.to_dict())))
	check(inv2.count("oak") == 1003 and inv2.tools.size() == Inventory.TOOL_SLOTS, "heybe kaydı gidip geliyor")

	print("== dünya")
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	get_tree().root.add_child(world)
	for i in 5:
		await get_tree().process_frame
	var gw: GatherWorld = world.get_node("Gathering")
	var player: Player = world.get_node("Player")
	check(gw.tree_field.trees.size() > 40, "ağaçlar kaynak olarak kuruldu (%d)" % gw.tree_field.trees.size())
	check(gs.tutorial_step == 0 and gs.current_quest_key == "QUEST_WELCOME", "tanıtım ilk adımda (yürü)")
	var tut: Tutorial = world.get_node("Tutorial")
	player.global_position += Vector3(5, 0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(gs.tutorial_step == 1, "yürüyünce 'bak' adımı (%d)" % gs.tutorial_step)
	player.yaw += 1.6
	await get_tree().process_frame
	await get_tree().process_frame
	check(gs.tutorial_step == 2 and gs.current_quest_key == "QUEST_FIRST_GATHER", "bakınca toplama adımı (%d)" % gs.tutorial_step)
	gs.inventory.from_dict({})
	# Elle toplama tek dokunuş
	var pebble: Gatherable = null
	for g in gw._gatherables:
		if g.resource_id == "pebble":
			pebble = g
			break
	player.gather.on_interact_pressed(pebble)
	check(gs.inventory.count("stone") == 1 and pebble.state != Gatherable.State.READY, "küçük taş tek dokunuşta alındı")
	# Alet yokken ağaç: uyarı
	var tree: TreeGatherable = gw.tree_field.trees[0].gatherable
	var inv_g: Inventory = gs.inventory
	var missing := [false]
	player.gather.tool_missing.connect(func(_k, _g): missing[0] = true)
	player.gather.on_interact_pressed(tree)
	check(missing[0] and not player.gather.active(), "baltasız ağaç: metinsiz uyarı")
	# Eğitim: atölyede kalıplarla ilk aletler (sap → balta başı / kazma başı)
	gs.inventory.add("stone", 3)
	gs.inventory.add("branch", 2)
	world.workshop.interactable.interact(player)
	var wp: WorkshopPanel = world.hud.workshop_panel
	check(wp.is_open and wp.highlight_mold == "handle", "atölye paneli açıldı, Sap kalıbı vurgulu")
	check(not Crafting.craft(gs.inventory, "axe_head", ["stone", ""]).size(), "eksik yuvayla üretilmez")
	check(Crafting.craft(gs.inventory, "handle", ["branch"]).get("key", "") == "handle:branch", "dal sap yapıldı")
	check(Crafting.craft(gs.inventory, "handle", ["branch"]).size() > 0, "ikinci sap")
	check(Crafting.craft(gs.inventory, "axe_head", ["stone", "handle:branch"]).get("kind", "") == "tool", "taş balta kalıpla yapıldı")
	check(Crafting.craft(gs.inventory, "pickaxe_head", ["stone", "handle:branch"]).get("kind", "") == "tool", "taş kazma kalıpla yapıldı")
	await get_tree().process_frame
	wp.close_panel()
	check(gs.inventory.has_tool("axe") and gs.inventory.has_tool("pickaxe") and gs.inventory.count("stone") == 0, "aletler heybede, taşlar harcandı")
	check(gs.tutorial_step == 4, "eğitim 'kullan' adımında (%d)" % gs.tutorial_step)
	# Ritim: tatlı vuruş 2x
	player.global_position = tree.global_position + Vector3(1.5, 0, 0)
	player.gather.on_interact_pressed(tree)
	check(player.gather.active(), "kesme oturumu başladı")
	player.gather.cycle = player.gather.swing
	player.gather._press_during_session()
	check(absf(tree.progress - 0.4) < 0.01, "tatlı vuruş = 2/5 ilerleme (%.2f)" % tree.progress)
	player.gather.cycle = player.gather.swing * 0.6
	player.gather._press_during_session()
	check(absf(tree.progress - 0.6) < 0.01, "erken basış = normal vuruş, ceza yok (%.2f)" % tree.progress)
	player.gather.cycle = player.gather.swing * 0.1
	player.gather._press_during_session()
	check(absf(tree.progress - 0.6) < 0.01, "alet havadayken basış yok sayılır")
	var dur: int = gs.inventory.best_tool("axe", "oak_tree").durability
	check(dur == gs.inventory.best_tool("axe", "oak_tree").max_durability - 2, "her vuruş dayanıklılığı düşürür")
	player.gather.cycle = player.gather.swing
	player.gather._press_during_session()
	check(tree.state == Gatherable.State.DEPLETED and not player.gather.active(), "ağaç kesildi, kütük kaldı")
	check(gs.inventory.count("oak") >= 3, "meşe heybede (%d)" % gs.inventory.count("oak"))
	# Kayıt / yükleme
	var data := {}
	gw.save_state(data)
	check(data["world"]["resources"].has(tree.save_id), "kesilen ağaç kayda girdi")
	# Yeniden büyüme
	tree.timer = 0.0
	await _frames(10)
	check(tree.state == Gatherable.State.GROWING, "kütükten fidan çıktı")
	tree.timer = 0.0
	await _frames(10)
	check(tree.state == Gatherable.State.READY, "fidan ağaç oldu")
	gw.load_state(data)
	check(tree.state == Gatherable.State.DEPLETED, "kayıttan kütük olarak yüklendi")
	# Tohum dikme
	gs.inventory.add("acorn", 1)
	var before: int = gw.tree_field.planted_list().size()
	gw._on_planted("acorn", Vector3(-6.0, ValleyShape.height(-6.0, 12.0), 12.0))
	check(gw.tree_field.planted_list().size() == before + 1, "palamut dikildi")
	# Ritim kapalı: basılı tutunca vurur
	gs.set_rhythm_hits(false)
	print("\nSonuç: %s (%d hata)" % ["BAŞARILI" if _fails == 0 else "BAŞARISIZ", _fails])
	get_tree().quit(1 if _fails else 0)
