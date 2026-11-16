class_name ScreenshotCapture
extends Node
## Geliştirici aracı: komut satırından ekran görüntüsü alır ve çıkar.
## Örnek:
##   godot --path . -- --screenshot=user://shot.png --quality=2 --cam=-14,6,22,-2,1,-6
## --cam verilmezse oyuncu kamerası kullanılır. --frames: beklenecek kare sayısı.
## Toplama sahneleri: --player=x,z,yaw_derece  --give=1 (taş aletler + malzeme)
##   --hits=N (odaktaki kaynağa N vuruş)  --fell=N (en yakın N ağacı kes)
##   --inventory_open=1  --ring=0.85 (oturum açık, halka bu aşamada dondurulur)
## Onarım: --step=5 (eğitim adımı)  --bridge=oak,pine,copper (kuzey, güney, bağlantı; "-" boş)
##   --repair_open=1 (onarım panelini aç)  --repair_slot=beam_south  --crack=1

var _args := {}
var _near: Gatherable


static func parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


static func requested() -> bool:
	return parse_args().has("screenshot")


func _ready() -> void:
	_args = parse_args()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _args.has("quality"):
		GameState.set_quality(int(_args["quality"]))
	if _args.has("locale"):
		GameState.set_locale(str(_args["locale"]))
	if _args.has("touch"):
		InputManager.set_touch_preview(true)
	if _args.has("cam"):
		var v: PackedFloat64Array = str(_args["cam"]).split_floats(",")
		var cam := Camera3D.new()
		cam.fov = 60.0
		cam.far = 300.0
		get_parent().add_child(cam)
		cam.look_at_from_position(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
		cam.make_current()
	if _args.has("toast"):
		var hud := get_parent().get_node_or_null("HUD")
		if hud:
			hud.show_toast(str(_args["toast"]), 30.0)
	_capture.call_deferred()


func _capture() -> void:
	# SaveSystem ayarları bir kare sonra uyguladığı için burada tekrar zorla
	if _args.has("locale"):
		GameState.set_locale(str(_args["locale"]))
	if _args.has("quality"):
		GameState.set_quality(int(_args["quality"]))
	if _args.has("quest_open"):
		var hud := get_parent().get_node_or_null("HUD")
		if hud:
			hud.set_quest_log_open(true)
	await _gather_scenario()
	var frames := int(_args.get("frames", "90"))
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := str(_args["screenshot"])
	var err := img.save_png(path)
	print("ScreenshotCapture: %s -> %s (%d)" % [path, ProjectSettings.globalize_path(path), err])
	get_tree().quit()


func _gather_scenario() -> void:
	var world := get_parent()
	var player: Player = world.get_node_or_null("Player")
	if player == null:
		return
	if _args.has("player"):
		var v: PackedFloat64Array = str(_args["player"]).split_floats(",")
		player.global_position = Vector3(v[0], ValleyShape.height(v[0], v[1]) + 0.2, v[1])
		player.yaw = deg_to_rad(v[2])
		player.model.rotation.y = player.yaw
		player.camera_rig.global_position = player.global_position + Vector3(0, 1.45, 0)
	if _args.has("near"):
		_move_near(world, player, str(_args["near"]))
	if _args.has("give"):
		var inv := GameState.inventory
		inv.add_tool(ToolItem.create("axe", "stone", "branch"))
		inv.add_tool(ToolItem.create("pickaxe", "stone", "branch"))
		for id: String in ["oak", "pine", "stone", "branch", "clay", "reed", "acorn"]:
			inv.add(id, [7, 4, 9, 3, 2, 5, 2][["oak", "pine", "stone", "branch", "clay", "reed", "acorn"].find(id)])
	for i in 10:
		await get_tree().physics_frame
	if _args.has("fell"):
		var gw: GatherWorld = world.get_node("Gathering")
		var trees := gw.tree_field.trees.filter(func(t): return t.active)
		trees.sort_custom(func(a, b): return a.base.distance_to(player.global_position) < b.base.distance_to(player.global_position))
		for i in int(_args["fell"]):
			trees[i].gatherable.set_hitter(player.global_position)
			trees[i].gatherable.complete()
	var focus_g: Gatherable = _near if _near != null else player.focus as Gatherable
	if _args.has("hits") and focus_g != null:
		var g := focus_g
		player.gather.on_interact_pressed(g)
		for i in int(_args["hits"]):
			if not player.gather.active():
				break
			player.gather.cycle = player.gather.swing
			player.gather._hit(i % 2 == 0)
			await get_tree().create_timer(0.12).timeout
	if _args.has("ring") and focus_g != null:
		if not player.gather.active():
			player.gather.on_interact_pressed(focus_g)
		player.gather.set_physics_process(false)
		player.gather.cycle = player.gather.swing * float(_args["ring"])
	if _args.has("step"):
		GameState.tutorial_step = int(_args["step"])
		GameState.set_quest(Tutorial.QUESTS[GameState.tutorial_step])
	if _args.has("mouse"):
		var mv: PackedFloat64Array = str(_args["mouse"]).split_floats(",")
		get_viewport().warp_mouse(Vector2(mv[0], mv[1]))
	if _args.has("cursor_png"):
		var img := CursorArt._arrow_image()
		img.resize(160, 160, Image.INTERPOLATE_NEAREST)
		img.save_png(str(_args["cursor_png"]))
	if _args.has("workshop"):
		# --workshop=kalıp[,seçim1,seçim2]  örn. axe_head,iron,handle:oak
		var parts := str(_args["workshop"]).split(",")
		var inv := GameState.inventory
		for id: String in ["iron", "copper", "oak", "pine", "stone"]:
			inv.add(id, 6)
		if not _args.has("step"):
			inv.add_part("handle:oak", 1)
		inv.add_part("handle:branch", 2)
		var hud = world.get_node("HUD")
		hud.open_workshop()
		hud.workshop_panel.select_mold(parts[0])
		for i in range(1, parts.size()):
			hud.workshop_panel.active_slot = i - 1
			hud.workshop_panel.choose(parts[i])
	if _args.has("craft"):
		world.get_node("HUD").workshop_panel._on_craft()
	if _args.has("side_cam"):
		# Oyuncuyu yandan gösteren kamera (animasyon kareleri için). Değer: uzaklık.
		var d := float(_args["side_cam"])
		var basis := Basis(Vector3.UP, player.model.rotation.y)
		var at := player.global_position + Vector3(0, 0.95, 0)
		var cam := Camera3D.new()
		cam.fov = 50.0
		world.add_child(cam)
		cam.look_at_from_position(at + basis * Vector3(d, 0.35, -d * 0.35), at)
		cam.make_current()
	if _args.has("anim"):
		await _anim_pose(player, str(_args["anim"]))
	if _args.has("mill_wall") or _args.has("mill_wheel") or _args.has("mill_open") or _args.has("finale"):
		await _mill_scenario(world, player)
	if _args.has("bridge") or _args.has("repair_open"):
		await _bridge_scenario(world)
	if _args.has("enemy"):
		await _enemy_portrait(world)
	if _args.has("coop") or _args.has("ink") or _args.has("hurt") or _args.has("warn"):
		await _combat_scenario(world, player)
	if _args.has("tool_memory"):
		_aged_tools()
	if _args.has("inventory_open"):
		world.get_node("HUD").toggle_inventory()
	if _args.has("pause"):
		world.get_node("HUD").set_paused(true)


## --coop=1 (2. oyuncu katılır) --ink=küçük,iri (lekeler köprüde / oyuncuda)
## --wear=0..1 (köprü parçaları aşınmış) --hurt=N (1. oyuncunun canı) --downed=revive(0..1)
## --warn=1 (dalga uyarısı) --first_wave=1 (ilk dalga kartı)
func _combat_scenario(world: Node, player: Player) -> void:
	var d: EnemyDirector = world.director
	if _args.has("coop"):
		var p2: Player = world.coop.join(0)
		var side := Basis(Vector3.UP, player.yaw) * Vector3(1.6, 0, -0.6)
		p2.global_position = player.global_position + side
		p2.global_position.y = ValleyShape.height(p2.global_position.x, p2.global_position.z) + 0.1
	await get_tree().process_frame
	if _args.has("wear"):
		var bridge: RepairSite = world.bridge
		var w := float(_args["wear"])
		var i := 0
		for id: String in bridge.damageable_slots():
			var m := Repair.slot_max_hp("bridge", bridge.state, id)
			Repair.slot_state(bridge.state, id)["wear"] = m * w * (0.5 + 0.5 * i)
			i += 1
	if _args.has("warn"):
		d.phase = EnemyDirector.Phase.CALM
		d.timer = 0.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		if _args.has("first_wave"):
			world._on_wave_warning(1, d._spawn_dir)
		d.timer = 999.0
	if _args.has("ink"):
		var n := str(_args["ink"]).split_floats(",")
		d.phase = EnemyDirector.Phase.WAVE
		d.wave = maxi(d.wave, 3)
		for k in int(n[0]):
			var b := ValleyEnemy.new().setup(ValleyEnemy.Kind.SMALL, d)
			d.add_child(b)
			d.blots.append(b)
			d.retarget(b)
			b.global_position = b.goal + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
			b.state = ValleyEnemy.State.GNAW
		for k in (int(n[1]) if n.size() > 1 else 0):
			var b := ValleyEnemy.new().setup(ValleyEnemy.Kind.BIG, d)
			d.add_child(b)
			d.blots.append(b)
			d.retarget(b)
			var fwd := Basis(Vector3.UP, player.yaw) * Vector3(-1.2, 0, -2.6)
			b.global_position = player.global_position + fwd
			b.player_damage = 0  # poz için sabit dursun
			b.state = ValleyEnemy.State.FLEE
			b._flee_t = 999.0
		d._queue = [0, 0]
	if _args.has("hurt"):
		player.health = int(_args["hurt"])
		player._since_hurt = 0.0
	if _args.has("downed"):
		var target: Player = world.coop.p2 if world.coop.p2 != null else player
		target.health = 0
		target._set_downed(true)
		await get_tree().create_timer(0.6).timeout
		target.revive = float(_args["downed"])
		target.set_physics_process(false)


## --enemy=small|big|rodent|spirit|flood[,N] — o türden N tane köprünün batı ucunda;
## --enemy_cam=dx,dy,dz kamera düşmana göre (varsayılan yakın plan).
func _enemy_portrait(world: Node) -> void:
	var d: EnemyDirector = world.director
	var parts := str(_args["enemy"]).split(",")
	var kinds := {"small": ValleyEnemy.Kind.SMALL, "big": ValleyEnemy.Kind.BIG, "rodent": ValleyEnemy.Kind.RODENT, "spirit": ValleyEnemy.Kind.SPIRIT, "flood": ValleyEnemy.Kind.FLOOD}
	var kind: int = kinds.get(parts[0], ValleyEnemy.Kind.SMALL)
	var n := int(parts[1]) if parts.size() > 1 else 1
	var bridge: RepairSite = world.bridge
	var anchor: Vector3 = bridge.attack_points()[0]
	if kind == ValleyEnemy.Kind.SPIRIT:
		anchor = world.mill.wall.attack_points()[0]
	d.phase = EnemyDirector.Phase.WAVE
	d._queue = [0]
	var focus := anchor
	var first: ValleyEnemy = null
	for i in n:
		var e := d._spawn(kind)
		if kind == ValleyEnemy.Kind.FLOOD:
			var z := bridge.global_position.z - 5.0
			e.global_position = Vector3(ValleyShape.river_x(z), ValleyShape.water_y(z) - 0.1, z)
			e.speed = 0.0
			focus = e.global_position
		else:
			var off := Vector3(cos(i * 2.1) * 1.1, 0, sin(i * 2.1) * 1.1) if n > 1 else Vector3.ZERO
			e.global_position = anchor + off
			e.goal = e.global_position
			if kind == ValleyEnemy.Kind.SPIRIT:
				e.site = world.mill.wall
			e.state = ValleyEnemy.State.GNAW
			e.player_damage = 0
			if i == 0:
				focus = e.global_position
		if i == 0:
			first = e
	if _args.has("enemy_at"):
		# Portre: açık bir yerde, kameraya dönük ve yerinde.
		var at: PackedFloat64Array = str(_args["enemy_at"]).split_floats(",")
		var i := 0
		for e: ValleyEnemy in d.blots:
			var p := Vector3(at[0] + (i - (n - 1) * 0.5) * 0.9, 0, at[1] + absf(i - (n - 1) * 0.5) * 0.4)
			e.global_position = Vector3(p.x, e._ground_y(p.x, p.z), p.z)
			e.speed = 0.0
			e.state = ValleyEnemy.State.FLEE
			e._flee_t = 999.0
			e.rotation.y = deg_to_rad(float(at[2]) if at.size() > 2 else 0.0)
			i += 1
	for i in 8:
		await get_tree().physics_frame
	# Varsayılan: düşmanın yüzüne, hafif yandan ve yukarıdan bakan kamera.
	var fwd := -first.global_transform.basis.z
	fwd.y = 0.0
	var dist := 5.5 if kind == ValleyEnemy.Kind.FLOOD else (3.6 if kind == ValleyEnemy.Kind.SPIRIT else 2.6)
	var v := (fwd.normalized().rotated(Vector3.UP, 0.45) * dist) + Vector3(0, dist * 0.45, 0)
	focus = first.global_position
	if _args.has("enemy_cam"):
		var a: PackedFloat64Array = str(_args["enemy_cam"]).split_floats(",")
		v = Vector3(a[0], a[1], a[2])
	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.look_at_from_position(focus + v, focus + Vector3(0, 0.5, 0))
	cam.make_current()


## --tool_memory=1: heybedeki ilk alet yaşlanmış, isim kazanmış, geçmişli ve aşınmış.
func _aged_tools() -> void:
	var tools := GameState.inventory.tools
	if tools.is_empty():
		return
	var t: ToolItem = tools[0]
	t.uses = 64
	t.durability = int(t.max_durability * 0.35)
	ItemMemory.maybe_name(t)
	for i in 12:
		ItemMemory.record_gather(t, "oak_tree")
	ItemMemory.record_deed([t], "bridge")
	if tools.size() > 1:
		tools[1].uses = 18
		for i in 3:
			ItemMemory.record_gather(tools[1], "boulder")
	GameState.inventory.notify_tool_changed()


## --anim=strike:0.05 | pickup:0.25 | windup:0.9 — pozu o anda dondur (animasyon karesi).
func _anim_pose(player: Player, spec: String) -> void:
	var kv := spec.split(":")
	var t := float(kv[1]) if kv.size() > 1 else 0.1
	var m = player.model
	if GameState.inventory.best_tool("axe", "oak_tree") != null:
		m.set_held_tool("axe", GameState.inventory.best_tool("axe", "oak_tree").head)
	player.set_process(false)  # elde alet seçimini ezmesin
	match kv[0]:
		"strike":
			m.set_windup(1.0)
			await get_tree().create_timer(0.4).timeout
			m.strike(true)
		"pickup":
			m.pickup()
		"windup":
			m.set_windup(t)
			t = 0.5
	await get_tree().create_timer(t).timeout
	m.set_process(false)


## --mill_wall=stone,iron,-  (her sıra: gövde malzemesi + kil; "-" boş)
## --mill_wheel=N  (ilk N yuva meşe/demir parçalarla) --mill_open=wall|wheel
## --mill_cam=dx,dy,dz (değirmene göre kamera) --finale=sn (final sahnesi, o anda çek)
func _mill_scenario(world: Node, player: Player) -> void:
	var mill: Mill = world.get_node("Mill")
	var inv := GameState.inventory
	if _args.has("no_finale"):
		world.finale.done = true  # sahne oynamasın, onarılmış hali göster
		world.finale._light_step(1.0)
		world.finale._motes_on()
	var walls := str(_args.get("mill_wall", "")).split(",", false)
	var ids := ["wall_low", "wall_mid", "wall_top"]
	for i in mini(walls.size(), 3):
		if walls[i] == "-":
			continue
		var key := "block:%s:clay" % walls[i]
		inv.add_part(key, 1)
		mill.wall.install(ids[i], key)
	var n := int(_args.get("mill_wheel", "0"))
	var slots := Repair.slots("mill_wheel")
	for i in mini(n, slots.size()):
		var id: String = slots[i]["id"]
		var key := "axle:iron" if id == "axle" else ("gear:copper" if id == "gear" else "paddle:oak")
		inv.add_part(key, 1)
		mill.wheel.install(id, key)
	for key: String in ["block:stone:clay", "block:stone:reed", "block:iron:clay", "paddle:oak", "paddle:pine", "gear:oak", "axle:oak"]:
		inv.add_part(key, 2)
	if _args.has("mill_open"):
		var hud = world.get_node("HUD")
		hud.open_repair(mill.wall if str(_args["mill_open"]) == "wall" else mill.wheel)
	if _args.has("mill_cam"):
		var v: PackedFloat64Array = str(_args["mill_cam"]).split_floats(",")
		var cam := Camera3D.new()
		cam.fov = 55.0
		world.add_child(cam)
		var focus := mill.wheel.global_position.lerp(mill.global_position, 0.4) + Vector3(0, 0.6, 0)
		cam.look_at_from_position(mill.global_position + Vector3(v[0], v[1], v[2]), focus)
		cam.make_current()
	if _args.has("finale"):
		world.finale.play()
		await get_tree().create_timer(float(_args["finale"])).timeout
		get_tree().paused = false


func _bridge_scenario(world: Node) -> void:
	var bridge: RepairSite = world.get_node("Bridge")
	var inv := GameState.inventory
	var mats := str(_args.get("bridge", "")).split(",", false)
	var slot_ids := ["beam_north", "beam_south", "link"]
	for i in mini(mats.size(), slot_ids.size()):
		if mats[i] == "-":
			continue
		var mold_id := str(Repair.slot_def("bridge", slot_ids[i])["mold"])
		var key := Crafting.part_key(mold_id, mats[i])
		inv.add_part(key, 1)
		bridge.install(slot_ids[i], key)
	for key: String in ["beam:oak", "beam:pine", "beam:stone", "connector:copper", "connector:reed"]:
		inv.add_part(key, 1)
	if _args.has("crack"):
		bridge.crack_weak_parts()
		await get_tree().create_timer(1.5).timeout
	if _args.has("repair_open"):
		var hud = world.get_node("HUD")
		hud.open_repair(bridge)
		if _args.has("repair_slot"):
			hud.repair_panel.select_slot(str(_args["repair_slot"]))
		if _args.has("repair_choice"):
			hud.repair_panel.choose(str(_args["repair_choice"]))


## Oyuncuyu verilen türdeki en yakın kaynağın 1.9 m önüne, ona bakacak şekilde koy.
func _move_near(world: Node, player: Player, res_id: String) -> void:
	var gw: GatherWorld = world.get_node("Gathering")
	var best: Gatherable = null
	for g: Gatherable in gw._gatherables:
		if g.resource_id == res_id and g.can_focus() and (best == null or g.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = g
	if best == null:
		return
	_near = best
	var off := float(_args.get("near_angle", "200"))
	var dir := Vector3(sin(deg_to_rad(off)), 0, cos(deg_to_rad(off)))
	var p := best.global_position + dir * float(_args.get("near_dist", "1.9"))
	player.global_position = Vector3(p.x, ValleyShape.height(p.x, p.z) + 0.2, p.z)
	var to := best.global_position - player.global_position
	player.yaw = atan2(-to.x, -to.z) + deg_to_rad(float(_args.get("near_yaw", "-12")))
	player.model.rotation.y = atan2(-to.x, -to.z)
	player.camera_rig.global_position = player.global_position + Vector3(0, 1.45, 0)
