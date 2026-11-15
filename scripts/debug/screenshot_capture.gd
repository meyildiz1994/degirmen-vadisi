class_name ScreenshotCapture
extends Node
## Geliştirici aracı: komut satırından ekran görüntüsü alır ve çıkar.
## Örnek:
##   godot --path . -- --screenshot=user://shot.png --quality=2 --cam=-14,6,22,-2,1,-6
## --cam verilmezse oyuncu kamerası kullanılır. --frames: beklenecek kare sayısı.
## Toplama sahneleri: --player=x,z,yaw_derece  --give=1 (taş aletler + malzeme)
##   --hits=N (odaktaki kaynağa N vuruş)  --fell=N (en yakın N ağacı kes)
##   --inventory_open=1  --ring=0.85 (oturum açık, halka bu aşamada dondurulur)

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
	if _args.has("inventory_open"):
		world.get_node("HUD").toggle_inventory()


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
