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

	_test_item_memory()
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
	await _frames(2)
	var gt: Control = wp._guide_target()
	check(wp.guide_enabled and gt != null and gt == wp._craft_button, "yol gösterici Üret'i gösteriyor (dal kendiliğinden kondu)")
	wp.select_mold("beam")
	await _frames(2)
	check(wp._guide_target() == wp._mold_buttons["handle"], "başka kalıba geçince vurgulu kalıbı gösteriyor")
	wp.select_mold("handle")
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
	await _test_bridge(world, player)
	await _test_mouse(player)
	await _test_polish(world, player)
	await _test_combat(world, player)
	await _test_net(world, player)
	# Ritim kapalı: basılı tutunca vurur
	gs.set_rhythm_hits(false)
	print("\nSonuç: %s (%d hata)" % ["BAŞARILI" if _fails == 0 else "BAŞARISIZ", _fails])
	get_tree().quit(1 if _fails else 0)


## Köprü onarımı: eşikler, zayıf parça, geçiş, çatlama, kayıt.
func _test_bridge(world: Node, player: Player) -> void:
	print("== köprü onarımı")
	var n_beam := Repair.needs("bridge", "beam_north")
	var n_link := Repair.needs("bridge", "link")
	check(Repair.meets("beam:oak", n_beam), "meşe kiriş istenenleri karşılar")
	check(not Repair.meets("beam:pine", n_beam), "çam kiriş zayıf (güç az)")
	check(Repair.failing("beam:stone", n_beam) == ["flexibility"], "taş kiriş kırılgan (esneklik az)")
	check(Repair.meets("connector:copper", n_link) and not Repair.meets("connector:reed", n_link), "bakır bağlantı sağlam, saz zayıf")
	var bridge: RepairSite = world.get_node("Bridge")
	var inv: Inventory = gs.inventory
	var bx := ValleyShape.river_x(ValleyShape.BRIDGE_Z)
	var start := Vector3(bx - 6.0, 0, ValleyShape.BRIDGE_Z)
	check(not await _walk_across(player, start), "yıkık köprüden geçilemez")
	check(player.global_position.y > ValleyShape.WATER_LEVEL, "oyuncu dereye düşmedi")
	world.hud.open_repair(bridge)
	var rp: RepairPanel = world.hud.repair_panel
	check(rp.is_open and rp.slot_id == "beam_north" and rp.choice == "", "onarım paneli açıldı, parça yok")
	inv.add_part("beam:oak", 1)
	inv.add_part("beam:pine", 1)
	inv.add_part("connector:copper", 1)
	rp.select_slot("beam_north")
	check(rp.choice == "beam:oak", "en uygun parça önce seçili")
	rp._on_install()
	check(Repair.is_filled(bridge.state, "beam_north") and inv.part_count("beam:oak") == 0, "kuzey kiriş takıldı, heybeden düştü")
	check(rp.slot_id == "beam_south" and rp.choice == "beam:pine", "sıradaki yere geçti")
	rp._on_install()
	check(bool(Repair.slot_state(bridge.state, "beam_south")["weak"]), "çam kiriş zayıf olarak takıldı")
	rp._on_install()
	check(bridge.is_complete(), "köprü tamamlandı")
	check(gs.tutorial_step == Tutorial.Step.IRON or gs.tutorial_step < Tutorial.Step.BRIDGE, "eğitim adımı ilerledi (%d)" % gs.tutorial_step)
	await _frames(40)
	check(await _walk_across(player, start), "onarılan köprüden karşıya geçildi")
	check(not bridge.state["slots"]["beam_south"].has("cracked"), "doğu kıyıda çatlamaz")
	var data := {}
	bridge.save_state(data)
	check(await _walk_across(player, start + Vector3(12.0, 0, 0), -1.0), "geri dönüldü")
	await _frames(5)
	check(Repair.is_cracked(bridge.state, "beam_south") and not bridge.is_complete(), "zayıf kiriş batı kıyıda çatladı")
	check(Repair.is_filled(bridge.state, "beam_north"), "sağlam kiriş yerinde")
	await _frames(90)
	check(not await _walk_across(player, start), "çatlayınca geçiş yine kapandı")
	bridge.load_state(data)
	check(bridge.is_complete() and Repair.is_filled(bridge.state, "link"), "köprü kayıttan yüklendi")
	check(data.get("repaired", []).has("bridge"), "onarılan yapı listesi")
	rp.close_panel()


## Oyuncuyu köprünün önüne koyup doğuya (dir=1) ya da batıya yürüt; karşı kıyıya vardı mı?
func _walk_across(player: Player, from: Vector3, dir := 1.0) -> bool:
	player.global_position = Vector3(from.x, ValleyShape.height(from.x, from.z) + 0.3, from.z)
	player.velocity = Vector3.ZERO
	player.yaw = -PI * 0.5 * dir
	player.input_enabled = true
	var goal := from.x + 12.0 * dir
	Input.action_press("move_forward")
	for i in 420:
		await get_tree().physics_frame
		player.yaw = -PI * 0.5 * dir
		if (player.global_position.x - goal) * dir > 0.0:
			break
	Input.action_release("move_forward")
	await get_tree().physics_frame
	return (player.global_position.x - goal) * dir > -1.0


## Fare: sağ tuşla sürükleyince bakış, imlecin altındaki hedefe sol tık = etkileşim.
func _test_mouse(player: Player) -> void:
	print("== fare")
	InputManager.set_touch_preview(false)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(1)
	InputManager.consume_look(0.0)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 0)
	Input.parse_input_event(motion)
	await _frames(1)
	check(InputManager.consume_look(0.0).x > 0.0, "sağ tuşla sürükleyince kamera döner")
	var release := press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.parse_input_event(motion)
	await _frames(1)
	check(InputManager.consume_look(0.0) == Vector2.ZERO, "sağ tuş bırakılınca imleç serbest, bakış yok")
	var clicked := [0]
	var bridge_it: Interactable = player.get_parent().get_node("Bridge/InteractableWest")
	bridge_it.interacted.connect(func(_by): clicked[0] += 1)
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	player.hovered = null
	player._unhandled_input(left)
	check(clicked[0] == 0, "boşluğa sol tık bir şey yapmaz")
	player.hovered = bridge_it
	player._unhandled_input(left)
	check(clicked[0] == 1, "imlecin altındaki hedefe sol tık = etkileşim")
	player.get_parent().hud.repair_panel.close_panel()


## Üretim netliği, elde alet, köprü sonrası hedefler, görev işaretçisi, animasyonlar.
func _test_polish(world: Node, player: Player) -> void:
	print("== netlik / yeni hedefler")
	var gs := GameState
	var inv := gs.inventory
	var hud = world.hud
	# Malzeme kartı
	var card: MaterialCard = hud.inventory_panel._mat_card
	card.show_item("oak")
	check(card.visible and card._bars.get_child_count() == 5, "malzeme kartı: 5 özellik çubuğu")
	check(card._hint.text != "" and not card._hint.text.begins_with("MAT_"), "malzeme kartı: 'neye yarar' notu çevrildi")
	card.show_item("")
	check(not card.visible, "boş seçimde kart gizli")
	# Atölye: üretince "Yapıldı" kartı
	inv.add("iron", 2)
	inv.add_part("handle:branch", 1)
	var wp: WorkshopPanel = hud.workshop_panel
	world.workshop.interactable.interact(player)
	wp.select_mold("axe_head")
	wp.choices = ["iron", "handle:branch"]
	wp._on_craft()
	await _frames(2)
	check(wp._made_popup != null and is_instance_valid(wp._made_popup) and wp._made_popup.visible, "üretim sonucu kartı göründü")
	wp.close_panel()
	await _frames(2)
	check(wp._made_popup == null or not is_instance_valid(wp._made_popup) or wp._made_popup.is_queued_for_deletion(), "panel kapanınca kart da kapandı")
	# Alet kemeri ve elde alet
	check(hud.tool_belt.get_child_count() >= 2, "alet kemerinde balta ve kazma (%d)" % hud.tool_belt.get_child_count())
	var tree: Gatherable = null
	for g in world.gather_world._gatherables:
		if g.tool_kind() == "axe" and g.state == Gatherable.State.READY:
			tree = g
			break
	player.global_position = tree.global_position + Vector3(1.5, 0.2, 0)
	await _frames(4)
	check(player.focus == tree and player.model.held_tool_kind() == "axe", "ağaca yaklaşınca balta ele alındı")
	player.global_position = Vector3(-6.0, ValleyShape.height(-6.0, 12.0) + 0.3, 12.0)
	await _frames(4)
	# Vuruş animasyonu sırası ve toparlanma
	player.model.strike(true)
	check(player.model.is_striking(), "vuruş zaman çizelgesi başladı")
	await get_tree().create_timer(0.6).timeout
	check(not player.model.is_striking(), "vuruş bitti, kol toparlandı")
	player.model.pickup()
	await get_tree().create_timer(1.2).timeout
	check(absf(player.model._rig.rotation.x) < 0.1, "çömelip kalktı, gövde dik (%.2f)" % player.model._rig.rotation.x)
	# Köprüden sonra: demir → demir alet → değirmen
	var tut: Tutorial = world.tutorial
	gs.tutorial_step = Tutorial.Step.IRON
	tut._refresh()
	check(gs.tutorial_step == Tutorial.Step.MILL, "demir balta zaten var: değirmen adımı (%d)" % gs.tutorial_step)
	check(gs.current_quest_key == "QUEST_VISIT_MILL", "görev: değirmene git")
	check(tut.goal_icon() == "mill" and tut.goal_position().distance_to(world.mill.interactable.global_position) < 2.0, "işaretçi değirmeni gösteriyor")
	await _frames(3)
	check(hud.quest_marker.visible, "görev işaretçisi görünür (uzakta)")
	world.mill.interactable.interact(player)
	check(gs.tutorial_step == Tutorial.Step.MILL_WALL and gs.current_quest_key == "QUEST_REPAIR_WALL", "değirmen incelendi: duvarı ör")
	check(tut.goal_position().distance_to(world.workshop.interactable.global_position) < 2.0, "duvar taşı yok: işaretçi atölyede")
	await _test_mill(world, player)


## Aşama 5: değirmen duvarı (taş + kil), çark (aks + dişli + 6 kanat), dönme, çatlama, final.
func _test_mill(world: Node, player: Player) -> void:
	print("== değirmen")
	var gs := GameState
	var inv := gs.inventory
	var mill: Mill = world.mill
	var tut: Tutorial = world.tutorial
	# Duvar taşı: gövde + harç; eşikler
	inv.add("stone", 10)
	inv.add("clay", 4)
	inv.add("reed", 2)
	var good := Crafting.craft(inv, "block", ["stone", "clay"])
	check(good.get("key", "") == "block:stone:clay", "duvar taşı = taş gövde + kil harç (%s)" % good.get("key", ""))
	var n := Repair.needs("mill_wall", "wall_low")
	check(Repair.meets("block:stone:clay", n), "taş+kil duvar şartlarını tutar")
	check(not Repair.meets("block:stone:reed", n), "sazlı harç zayıf (bağlama düşük)")
	check(not Repair.meets("block:oak:clay", n), "meşe gövde hafif kalır")
	check(Crafting.part_name("block:stone:clay").contains("·"), "parça adında harç da var")
	check(tut._mold_to_highlight() == "block", "atölyede Duvar Taşı vurgulu")
	Crafting.craft(inv, "block", ["stone", "clay"])
	Crafting.craft(inv, "block", ["stone", "reed"])
	check(tut.goal_icon() == "mill", "parçalar hazır: işaretçi değirmen duvarında")
	var rp: RepairPanel = world.hud.repair_panel
	mill.wall.interactable.interact(player)
	check(rp.is_open and rp.site == mill.wall, "duvar onarım paneli açıldı")
	check(rp.choice == "block:stone:clay", "en uygun duvar taşı önce seçili")
	rp._on_install()
	rp._on_install()
	check(rp.choice == "block:stone:reed", "kalan zayıf taş seçildi")
	rp._on_install()
	check(mill.wall.is_complete() and Repair.has_weak(mill.wall.state), "duvar örüldü (bir sıra zayıf)")
	await _frames(2)
	check(gs.tutorial_step == Tutorial.Step.MILL_WHEEL and gs.current_quest_key == "QUEST_REPAIR_WHEEL", "sıradaki: çark")
	# Zayıf sıra bir süre sonra çatlar
	mill.wall.state["crossings"] = Repair.crack_after_seconds("mill_wall") - 0.01
	await _frames(3)
	check(not mill.wall.is_complete() and Repair.is_cracked(mill.wall.state, "wall_top"), "zayıf sıra zamanla çatladı")
	Crafting.craft(inv, "block", ["stone", "clay"])
	mill.wall.install("wall_top", "block:stone:clay")
	check(mill.wall.is_complete() and not Repair.has_weak(mill.wall.state), "duvar sağlam taşla yeniden örüldü")
	rp.close_panel()
	await _frames(2)
	# Çark: kalıp şartları (meşe ideal kanat, taş dönmez, çam çürür)
	var pn := Repair.needs("mill_wheel", "paddle_1")
	check(Repair.meets("paddle:oak", pn), "meşe kanat ideal")
	check(not Repair.meets("paddle:stone", pn), "taş kanat ağır")
	check(not Repair.meets("paddle:pine", pn), "çam kanat suya dayanmaz")
	check(Repair.meets("gear:oak", Repair.needs("mill_wheel", "gear")) and Repair.meets("axle:iron", Repair.needs("mill_wheel", "axle")), "meşe dişli, demir aks uygun")
	check(tut._mold_to_highlight() == "axle", "atölyede önce Aks vurgulu")
	inv.add_part("axle:oak", 1)
	inv.add_part("gear:oak", 1)
	inv.add_part("paddle:oak", 6)
	mill.wheel.interactable.interact(player)
	check(rp.is_open and rp.site == mill.wheel and rp._slot_list.columns == 2, "çark paneli iki sütunlu açıldı")
	var finished := [false]
	world.finale.finished.connect(func(): finished[0] = true)
	for i in 8:
		rp._on_install()
	check(mill.wheel.is_complete(), "çark tamamlandı: aks + dişli + 6 kanat")
	check(mill.wheel.interactable.display_name_key == "NAME_MILL_WHEEL_FIXED" and mill.wheel._rim_fix.visible, "çark tamam görünümünde (jant kapandı)")
	await get_tree().create_timer(1.5).timeout
	check(mill.wheel.spin > 0.0, "çark dönmeye başladı")
	check(world.finale.playing and not player.input_enabled, "final sahnesi başladı, oyuncu bekliyor")
	await get_tree().create_timer(2.0).timeout
	var skip := InputEventAction.new()
	skip.action = "interact"
	skip.pressed = true
	world.finale._unhandled_input(skip)
	await _frames(3)
	check(finished[0] and world.finale.done and player.input_enabled, "final geçildi, oyuncu serbest")
	check(player.camera.current, "kamera oyuncuya döndü")
	check(gs.tutorial_step == Tutorial.Step.DONE and gs.current_quest_key == "QUEST_VALLEY_DONE", "görev: vadi canlandı")
	check(tut.goal_position() == Vector3.INF, "son adımda işaretçi yok")
	var data := {}
	world.finale.save_state(data)
	mill.wheel.save_state(data)
	check(bool(data["finale_done"]) and data["repaired"].has("mill_wheel"), "final ve çark kayda girdi")


## Aşama 6: eşya hafızası (isim, geçmiş, koyulaşma, tamir), başarımlar bir kez, ses ayarı.
func _test_item_memory() -> void:
	print("== eşya hafızası")
	SaveSystem.autosave_enabled = false
	var t := ToolItem.create("axe", "stone", "branch")
	for i in 49:
		t.wear()
	check(not ItemMemory.maybe_name(t), "49 kullanımda isim yok")
	t.wear()
	check(ItemMemory.maybe_name(t) and ItemMemory.is_named(t), "50 kullanımda isim kazanır")
	check(not ItemMemory.maybe_name(t), "isim bir kez verilir")
	var tr_name := t.display_name()
	check(tr_name.ends_with(t.base_name()) and tr_name != t.base_name(), "isim: sıfat + alet (%s)" % tr_name)
	var old_loc := TranslationServer.get_locale()
	TranslationServer.set_locale("tr")
	tr_name = t.display_name()
	TranslationServer.set_locale("en")
	check(t.display_name() != tr_name, "isim dile göre çevrilir (%s)" % t.display_name())
	TranslationServer.set_locale(old_loc)
	for i in 12:
		ItemMemory.record_gather(t, "oak_tree")
	ItemMemory.record_gather(t, "boulder")
	ItemMemory.record_gather(t, "reeds")
	ItemMemory.record_deed([t], "bridge")
	ItemMemory.record_deed([t], "bridge")
	var fresh := ToolItem.create("pickaxe", "stone", "branch")
	ItemMemory.record_deed([fresh], "bridge")
	check(fresh.deeds.is_empty(), "hiç kullanılmamış alet onarıma katılmış sayılmaz")
	var hist := ItemMemory.history_text(t)
	check("12" in hist and t.deeds == ["bridge"], "geçmiş: 12 ağaç, köprü (%s)" % hist)
	check(ItemMemory.darkness(t) > 0.2 and ItemMemory.wear_level(t) >= 1, "kullandıkça koyulaşır")
	check(ItemMemory.darkness(fresh) == 0.0 and ItemMemory.wear_level(fresh) == 0, "yeni alet açık renkli")
	var back := ToolItem.from_dict(JSON.parse_string(JSON.stringify(t.to_dict())))
	check(back.display_name() == t.display_name() and back.history == t.history and back.deeds == t.deeds, "isim ve geçmiş kayda girer")
	# Tamir
	var inv := Inventory.new()
	check(not ItemMemory.can_repair(t, inv), "malzeme yoksa tamir yok")
	inv.add("stone", 2)
	check(ItemMemory.repair(t, inv) and t.durability == t.max_durability and inv.count("stone") == 1 and t.repairs == 1, "tamir: 1 taş, dayanıklılık dolar")
	check(not ItemMemory.can_repair(t, inv), "dolu alet tamir edilmez")
	# Başarımlar bir kez
	var had: Array = SaveSystem.data.get("achievements", []).duplicate()
	SaveSystem.data["achievements"] = []
	var fired := [0]
	var cb := func(_id): fired[0] += 1
	PlatformServices.achievement_unlocked.connect(cb)
	check(not SaveSystem.persistent, "test oyuncunun kaydına dokunmaz")
	check(PlatformServices.unlock_achievement("ACH_TEST"), "başarım ilk kez açılır")
	check(not PlatformServices.unlock_achievement("ACH_TEST") and fired[0] == 1, "başarım tekrar açılmaz")
	PlatformServices.achievement_unlocked.disconnect(cb)
	SaveSystem.data["achievements"] = had
	# Ses ayarı
	var vs := VolumeSettings.new()
	add_child(vs)
	vs.sliders["Music"].value = 0.3
	check(is_equal_approx(float(SaveSystem.data["settings"]["volume"]["Music"]), 0.3), "müzik çubuğu kayda yazılır")
	check(vs.sliders["Music"].custom_minimum_size.y >= 48.0, "ses çubuğu ≥48 px")
	vs.sliders["Music"].value = 0.8
	vs.queue_free()


## Mürekkep lekeleri ve iki kişilik oyun.
func _test_combat(world: Node, player: Player) -> void:
	print("== mürekkep lekeleri")
	var d: EnemyDirector = world.director
	var c1 := EnemyDirector.composition(1, 1, 1)
	var c5 := EnemyDirector.composition(5, 3, 1)
	var c5co := EnemyDirector.composition(5, 3, 2)
	check(c1["small"] == 2 and c1["big"] == 0, "ilk dalga küçük bir tanışma")
	check(c5["small"] > c1["small"] and c5["big"] >= 1, "dalgalar büyür, Kara Leke gelir")
	check(c5co["small"] > c5["small"] and c5co["big"] > c5["big"], "iki kişide daha kalabalık")
	await _frames(3)
	check(d.phase != EnemyDirector.Phase.DORMANT, "onarım sonrası dalga yöneticisi uyandı")
	var bridge: RepairSite = world.bridge
	var slot: String = bridge.damageable_slots()[0]
	var hp := Repair.slot_max_hp("bridge", bridge.state, slot)
	check(hp > 20.0, "takılı parçanın dayanıklılığı var (%.0f)" % hp)
	# Dalgayı başlat
	d.timer = 0.0
	d.phase = EnemyDirector.Phase.CALM
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(d.phase == EnemyDirector.Phase.WARNING, "uyarı aşaması")
	d.timer = 0.0
	for i in 4:
		await get_tree().physics_frame
	check(d.phase == EnemyDirector.Phase.WAVE and d.blots.size() >= 1, "dalga başladı, leke sızdı")
	var b: ValleyEnemy = d.blots[0]
	check(b.site != null and b.slot_id != "", "leke bir yapı ve parça seçti")
	# Lekeyi yapıya taşı: parçayı aşındırsın
	b.global_position = b.goal
	b.state = ValleyEnemy.State.GNAW
	b.player_damage = 0
	for i in 30:
		await get_tree().physics_frame
	check(b.site.slot_health(b.slot_id) < 1.0, "leke parçayı eritiyor")
	var target_site := b.site
	var target_slot := b.slot_id
	var broke := target_site.damage_slot(target_slot, 9999.0)
	check(broke and Repair.is_cracked(target_site.state, target_slot) and target_site.crack_cause == "ink", "eriyen parça çatladı")
	check(not target_site.is_complete(), "yapı yeniden onarım bekliyor")
	# Vuruş: alet hasarı, leke dağılır
	player.input_enabled = true
	b.global_position = player.global_position + Vector3(1.0, 0, 0)
	var t := player.best_weapon()
	check(t != null and Player.weapon_damage(t) > Player.HAND_DAMAGE, "alet yumruktan güçlü")
	var hits := 0
	while is_instance_valid(b) and b.alive() and hits < 20:
		player._attack_cd = 0.0
		player.try_attack(b)
		hits += 1
	check(hits <= 3 and not d.blots.has(b), "küçük leke birkaç vuruşta dağıldı (%d)" % hits)
	print("== can ve sersemleme")
	player._invuln = 0.0
	player.take_damage(1, player.global_position + Vector3(1, 0, 0))
	check(player.health == Player.MAX_HEALTH - 1, "darbe canı azaltır")
	for i in Player.MAX_HEALTH:
		player._invuln = 0.0
		player.take_damage(1, player.global_position)
	check(player.downed and player.health == 0, "can bitince sersemler")
	print("== iki kişilik")
	var coop: CoopManager = world.coop
	var p2 := coop.join(0)
	await _frames(2)
	check(coop.is_active() and p2.index == 1 and p2.partner == player, "2. oyuncu katıldı")
	check(world.hud.players.size() == 2, "arayüz iki oyuncuyu biliyor")
	check(get_viewport().get_camera_3d() == player.camera, "ortak kamera 1. oyuncuda")
	check(InputManager.p2_pad == 0, "gamepad 2. oyuncuya ayrıldı")
	var ev := InputMap.action_get_events("interact")
	var moved := true
	for e in ev:
		if e is InputEventJoypadButton and e.device == 0:
			moved = false
	check(moved, "1. oyuncunun aksiyonları 2. gamepad'i dinlemiyor")
	p2.global_position = player.global_position + Vector3(0.8, 0, 0)
	for i in 160:
		await get_tree().physics_frame
	check(not player.downed, "arkadaş yanında durunca kaldırdı")
	check(p2.pinput.move_vector() == Vector2.ZERO, "2. oyuncunun girişi kendi gamepad'inden")
	var data := {}
	player.save_state(data)
	p2.save_state(data)
	check(data.has("player") and data["player"]["x"] == player.global_position.x, "kayıtta yalnızca 1. oyuncu")
	coop.leave()
	await _frames(2)
	check(not coop.is_active() and InputManager.p2_pad == -1 and player.partner == null, "2. oyuncu ayrıldı")
	var restored := false
	for e in InputMap.action_get_events("interact"):
		if e is InputEventJoypadButton and e.device == -1:
			restored = true
	check(restored, "gamepad yeniden 1. oyuncunun")
	print("== kemirgen, orman ruhu, sel")
	check(ValleyEnemy.damage_factor(ValleyEnemy.Kind.RODENT, "beam:oak") > ValleyEnemy.damage_factor(ValleyEnemy.Kind.RODENT, "beam:stone"), "kemirgen ahşabı taştan çok kemirir")
	var c2 := EnemyDirector.composition(2, 1, 1)
	var c3 := EnemyDirector.composition(3, 1, 1)
	var c4 := EnemyDirector.composition(4, 2, 1)
	check(c2["rodent"] >= 3 and c2["spirit"] == 0, "2. dalgada kemirgenler")
	check(c3["spirit"] >= 1, "3. dalgada orman ruhu")
	check(c4["flood"] >= 1 and EnemyDirector.composition(4, 2, 1, false)["flood"] == 0, "4. dalgada sel (dere yapısı varsa)")
	# Yapıları tazele
	for site: RepairSite in d.sites:
		for id: String in site.damageable_slots():
			Repair.slot_state(site.state, id)["wear"] = 0.0
	var wall: RepairSite = world.mill.wall
	var rod := d._spawn(ValleyEnemy.Kind.RODENT)
	check(rod.site != null and rod.slot_id != "", "kemirgen bir parça seçti")
	var spi := d._spawn(ValleyEnemy.Kind.SPIRIT)
	spi.site = wall
	spi.goal = wall.attack_points()[0]
	spi.global_position = spi.goal + Vector3(1.5, 0, 0)
	spi.state = ValleyEnemy.State.GNAW
	for i in 20:
		await get_tree().physics_frame
	var all_worn := true
	for id: String in wall.damageable_slots():
		if wall.slot_health(id) >= 1.0:
			all_worn = false
	check(all_worn, "orman ruhu yapının bütün parçalarını sarıyor")
	var before_pos := spi.global_position
	player._attack_cd = 0.0
	player.try_attack(spi)
	check(spi.alive() and spi.global_position.distance_to(before_pos) > 1.0, "vurulan ruh ışınlandı")
	var fl := d._spawn(ValleyEnemy.Kind.FLOOD)
	var z0 := fl.global_position.z
	fl.global_position.z = bridge.global_position.z - 2.0
	var bridge_before := 0.0
	for id: String in bridge.damageable_slots():
		bridge_before += bridge.slot_health(id)
	for i in 30:
		await get_tree().physics_frame
	var bridge_after := 0.0
	for id: String in bridge.damageable_slots():
		bridge_after += bridge.slot_health(id)
	check(z0 < 0.0 and fl.global_position.z > bridge.global_position.z - 2.0, "sel dere boyunca güneye akıyor")
	check(bridge_after < bridge_before, "sel köprüyü dövüyor")
	var fhp := fl.hp
	player._attack_cd = 0.0
	player.global_position = fl.global_position + Vector3(1.0, 0, 0)
	player.try_attack(fl)
	check(fl.hp < fhp, "sel vurulunca küçülür")
	check(d.seen.has(ValleyEnemy.Kind.FLOOD), "görülen türler kaydediliyor")
	print("== ayar ve kayıt")
	var sd := {}
	d.save_state(sd)
	check(sd["enemies"]["phase"] == EnemyDirector.Phase.CALM, "süren dalga sakin olarak kaydedilir")
	gs.set_enemies_enabled(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(d.blots.is_empty() and d.phase != EnemyDirector.Phase.WAVE, "ayardan kapatınca lekeler gider (%d, %d, %s)" % [d.blots.size(), d.phase, get_tree().paused])
	gs.set_enemies_enabled(true)


## Çevrimiçi: ağa giden özetler aynı durumu karşı tarafta kurar (bağlantısız sınama).
func _test_net(world: Node, player: Player) -> void:
	print("== çevrimiçi özetler")
	var d: EnemyDirector = world.director
	GameState.set_enemies_enabled(true)
	await _frames(2)
	d.phase = EnemyDirector.Phase.WAVE
	d._queue = [0]
	var e1 := d._spawn(ValleyEnemy.Kind.RODENT)
	var e2 := d._spawn(ValleyEnemy.Kind.SPIRIT)
	check(e1.net_id != e2.net_id and e1.net_id > 0, "düşmanların ağ kimliği var")
	var pack := d.net_pack()
	# Katılan tarafı aynı sahnede ikinci bir yöneticiyle taklit et
	var mirror := EnemyDirector.new()
	world.add_child(mirror)
	mirror.setup([world.bridge, world.mill.wall, world.mill.wheel], world.gather_world.fx)
	mirror.mirror = true
	mirror.apply_net(pack)
	check(mirror.blots.size() == pack[3].size() and mirror.blots.all(func(b): return b.puppet), "katılan tarafta kopyalar kuruldu")
	var copy: ValleyEnemy = mirror._by_net.get(e1.net_id)
	check(copy != null and copy.kind == ValleyEnemy.Kind.RODENT, "kopya doğru tür")
	e1.global_position += Vector3(2, 0, 0)
	e1.hp = 1.0
	e1.set_physics_process(false)
	var target := e1.global_position
	mirror.apply_net(d.net_pack())
	for i in 30:
		await get_tree().physics_frame
	check(copy.global_position.distance_to(target) < 0.3 and is_equal_approx(copy.hp, 1.0), "kopya ev sahibini izliyor")
	mirror.net_died(e2.net_id)
	await _frames(2)
	check(not mirror.blots.any(func(b): return is_instance_valid(b) and b.net_id == e2.net_id), "dağılan düşman katılanda da dağıldı")
	var pack2 := d.net_pack()
	pack2[3] = []
	mirror.apply_net(pack2)
	await _frames(2)
	check(mirror.blots.is_empty(), "artık olmayan kopya kaldırıldı")
	mirror.queue_free()
	for b in d.blots.duplicate():
		b.queue_free()
	d.blots.clear()
	d._calm_down()
	# Yapı durumu: karşı tarafın taktığı parça buraya da takılır
	var bridge: RepairSite = world.bridge
	var st := bridge.state.duplicate(true)
	var slot: String = bridge.damageable_slots()[0]
	Repair.erode(st, "bridge", slot, 99999.0)
	var got_crack := [false]
	var cb := func(_ids): got_crack[0] = true
	bridge.cracked.connect(cb)
	bridge.net_apply(st)
	bridge.cracked.disconnect(cb)
	check(Repair.is_cracked(bridge.state, slot) and not bridge.is_complete(), "karşıdaki çatlak buraya geldi")
	# Oyuncu özeti
	var ghost: Player = preload("res://scenes/player/player.tscn").instantiate()
	ghost.index = 1
	ghost.net_remote = true
	world.add_child(ghost)
	player.health = 3
	ghost.apply_net(player.net_state())
	check(ghost.health == 3 and ghost.global_position.distance_to(player.global_position) < 0.01, "karakter özeti konum ve canı taşıyor")
	var moved := player.net_state()
	moved[0] = float(moved[0]) + 3.0
	moved[8] = true
	ghost.apply_net(moved)
	for i in 30:
		await get_tree().physics_frame
	check(ghost.downed and absf(ghost.global_position.x - float(moved[0])) < 0.2, "uzaktaki karakter yürüyüp sersemledi")
	ghost.queue_free()
	player.heal_full()
	check(Net.is_room_code("kxrwta") and not Net.is_room_code("192.168.1.4") and not Net.is_room_code("ABC12"), "oda kodu adresten ayrılıyor")
	check(Net.local_address() == "" or Net.local_address().contains("."), "yerel adres okunuyor (%s)" % Net.local_address())
	await _test_steam_lobby()


## Steam daveti: lobi oda kodunu taşır, davet edilen o kodla katılır (sahte Steam ile).
func _test_steam_lobby() -> void:
	print("== steam daveti")
	var fake := FakeSteam.new()
	SteamLobby.bind(fake)
	check(not SteamLobby.can_invite(), "oyun açılmadan davet yok")
	Net.host_code = "QWERTY"
	Net._set_status(Net.Status.HOSTING)
	await _frames(3)
	var lid := SteamLobby.lobby_id
	check(lid != 0 and fake.getLobbyData(lid, SteamLobby.CODE_KEY) == "QWERTY", "lobi kuruldu, oda kodu lobiye yazıldı")
	check(SteamLobby.can_invite(), "davet düğmesi açık")
	SteamLobby.invite()
	check(fake.calls.has("invite"), "Steam davet penceresi açıldı")
	Net._close()
	check(SteamLobby.lobby_id == 0 and fake.calls.has("leaveLobby"), "oyun kapanınca lobiden çıkıldı")
	# Katılan: davet kabul edilir -> lobiye girer -> kodu okur -> aracıya bağlanır
	fake.data[lid] = {SteamLobby.CODE_KEY: "QWERTY"}
	var seen := [false]
	var watch := func(st): if st == Net.Status.CONNECTING and Net.is_guest(): seen[0] = true
	Net.status_changed.connect(watch)
	fake.join_requested.emit(lid, 7)
	await _frames(3)
	Net.status_changed.disconnect(watch)
	check(seen[0], "davetle oda koduna bağlanmaya başladı")
	Net._close()
	seen[0] = false
	Net.status_changed.connect(watch)
	fake.join_game_requested.emit(7, "+connect_lobby %d" % lid)
	await _frames(3)
	Net.status_changed.disconnect(watch)
	check(seen[0], "arkadaş listesinden 'Oyuna katıl' da bağlanıyor")
	Net._close()
	fake.join_requested.emit(424242, 7)
	await _frames(3)
	check(not Net.active(), "olmayan lobiye davet bağlanmaz")
	SteamLobby.steam = null
	fake.free()
