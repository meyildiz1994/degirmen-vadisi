class_name ScreenshotCapture
extends Node
## Geliştirici aracı: komut satırından ekran görüntüsü alır ve çıkar.
## Örnek:
##   godot --path . -- --screenshot=user://shot.png --quality=2 --cam=-14,6,22,-2,1,-6
## --cam verilmezse oyuncu kamerası kullanılır. --frames: beklenecek kare sayısı.

var _args := {}


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
	var frames := int(_args.get("frames", "90"))
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := str(_args["screenshot"])
	var err := img.save_png(path)
	print("ScreenshotCapture: %s -> %s (%d)" % [path, ProjectSettings.globalize_path(path), err])
	get_tree().quit()
