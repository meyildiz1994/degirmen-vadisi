class_name Finale
extends Node
## Final sahnesi: değirmen duvarı ve çarkı ilk kez birlikte tamamlanınca bir kez oynar.
## Kamera oyuncudan ayrılıp yavaşça değirmene ve dönen çarka süzülür, final müziği başlar,
## pencere yanar, vadiye sıcak ışık ve uçuşan ışık tozları gelir; ortada kısa bir kart.
## Etkileşim/duraklat tuşu ile geçilebilir. Kayıtta "finale_done" tutulur; yüklenince
## vadi aydınlık başlar (sahne tekrar oynamaz).

signal finished

const CAM_TIME := 11.0
const ORBIT_R := 7.5
const ORBIT_H := 2.6

var mill: Mill
var player: Player
var hud: CanvasLayer
var atmosphere: Node3D
var done := false
var playing := false

var _cam: Camera3D
var _from: Transform3D
var _seq: Tween
var _card: Control
var _motes: CPUParticles3D
var _base_sun := 1.5
var _base_ambient := 0.9


func setup(m: Mill, p: Player, h: CanvasLayer, atmo: Node3D) -> void:
	mill = m
	player = p
	hud = h
	atmosphere = atmo
	add_to_group(SaveSystem.PERSIST_GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if atmo != null and atmo.get("sun") != null:
		_base_sun = atmo.sun.light_energy
		_base_ambient = atmo.environment.ambient_light_energy
	m.wall.completed.connect(_check)
	m.wheel.completed.connect(_check)


func _check() -> void:
	if done or playing or not mill.wall.is_complete() or not mill.wheel.is_complete():
		return
	# Onarım paneli kendini kapatsın, çark dönmeye başlasın.
	get_tree().create_timer(1.1).timeout.connect(play)


# --- Sahne ------------------------------------------------------------------------------
func play() -> void:
	if done or playing:
		return
	playing = true
	player.input_enabled = false
	player.gather.stop()
	InputManager.release_all_virtual()
	_cam = Camera3D.new()
	_cam.fov = player.camera.fov
	_cam.far = player.camera.far
	add_child(_cam)
	_from = player.camera.global_transform
	_cam.global_transform = _from
	_cam.make_current()
	AudioManager.play_music("music_finale", 3.0)
	_build_card()
	_seq = create_tween().set_parallel(true)
	_seq.tween_property(hud.root, "modulate:a", 0.0, 0.6)
	_seq.tween_method(_cam_step, 0.0, 1.0, CAM_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_seq.tween_method(_light_step, 0.0, 1.0, 3.5).set_delay(2.2)
	_seq.tween_callback(_motes_on).set_delay(2.6)
	_seq.tween_property(_card, "modulate:a", 1.0, 1.2).set_delay(3.8)
	_seq.tween_property(_card, "modulate:a", 0.0, 1.0).set_delay(9.0)
	_seq.chain().tween_callback(_return_to_player)


## Oyuncu kamerasından değirmenin etrafında yavaş bir yaya.
func _cam_step(t: float) -> void:
	var center := _focus_point()
	var a := lerpf(0.25, 0.95, t)
	var orbit := center + Vector3(cos(a) * ORBIT_R, ORBIT_H, sin(a) * ORBIT_R)
	var to_orbit := smoothstep(0.0, 0.25, t)
	var pos := _from.origin.lerp(orbit, to_orbit)
	var look_from := _from.origin - _from.basis.z * 6.0
	var look := look_from.lerp(center, smoothstep(0.0, 0.2, t))
	_cam.global_position = pos
	if pos.distance_to(look) > 0.1:
		_cam.look_at(look, Vector3.UP)


func _focus_point() -> Vector3:
	return mill.wheel.global_position.lerp(mill.global_position, 0.35) + Vector3(0, 0.6, 0)


## "Vadiye ışık gelir": güneş ve ortam ışığı ısınır, pencere yanar.
func _light_step(t: float) -> void:
	mill.set_glow(t)
	if atmosphere == null or atmosphere.get("sun") == null:
		return
	atmosphere.sun.light_energy = lerpf(_base_sun, _base_sun * 1.22, t)
	atmosphere.sun.light_color = Color(1.0, 0.93, 0.82).lerp(Color(1.0, 0.86, 0.66), t * 0.6)
	atmosphere.environment.ambient_light_energy = lerpf(_base_ambient, _base_ambient * 1.12, t)


## Vadide süzülen sıcak ışık tozları (kalıcı).
func _motes_on() -> void:
	if _motes != null:
		_motes.emitting = true
		return
	_motes = CPUParticles3D.new()
	_motes.amount = 70 if GameState.quality == 0 else 140
	_motes.lifetime = 7.0
	_motes.preprocess = 3.0
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(22, 3, 22)
	_motes.direction = Vector3.UP
	_motes.spread = 60.0
	_motes.initial_velocity_min = 0.1
	_motes.initial_velocity_max = 0.35
	_motes.gravity = Vector3(0.05, 0.04, 0)
	_motes.scale_amount_min = 0.5
	_motes.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(0.8, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_motes.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(Palette.SUNSET_LIGHT.lightened(0.45), 0.85)
	quad.material = m
	_motes.mesh = quad
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mill.get_parent().add_child(_motes)
	_motes.global_position = mill.global_position.lerp(Vector3(0, mill.global_position.y, 4), 0.5) + Vector3(0, 2.5, 0)


func _build_card() -> void:
	# Kart altta: ortadaki değirmeni ve dönen çarkı kapatmasın.
	_card = CenterContainer.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_card.offset_top = -210.0
	_card.offset_bottom = -20.0
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	layer.add_child(_card)
	var panel := WatercolorPanel.new()
	panel.card = true
	panel.padding = Vector2(48, 26)
	panel.blob_seed = 12.5
	_card.add_child(panel)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	var ic := ItemIcon.new()
	ic.icon = "mill"
	ic.custom_minimum_size = Vector2(56, 56)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(ic)
	for d: Array in [["FINALE_TITLE", 36], ["FINALE_SUB", 22], ["FINALE_SKIP", 15]]:
		var l := Label.new()
		l.text = d[0]
		l.add_theme_font_size_override("font_size", d[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if d[0] == "FINALE_SKIP":
			l.modulate.a = 0.6
		vb.add_child(l)


func _return_to_player() -> void:
	if not playing:
		return
	var t := create_tween()
	var target := player.camera.global_transform
	t.tween_method(func(k: float): _cam.global_transform = _cam.global_transform.interpolate_with(target, k), 0.0, 1.0, 1.4)
	t.tween_callback(_end)


func _end() -> void:
	if not playing:
		return
	playing = false
	done = true
	if _seq and _seq.is_valid():
		_seq.kill()
	_light_step(1.0)
	_motes_on()
	player.camera.make_current()
	if _cam != null:
		_cam.queue_free()
		_cam = null
	if _card != null:
		_card.get_parent().queue_free()
		_card = null
	player.input_enabled = true
	create_tween().tween_property(hud.root, "modulate:a", 1.0, 0.6)
	PlatformServices.unlock_achievement("ACH_VALLEY_RESTORED")
	# Final müziği bitince keşif temasına yumuşakça dön.
	get_tree().create_timer(95.0).timeout.connect(func():
		if AudioManager.get("_music_id") == "music_finale":
			AudioManager.play_music("music_explore", 6.0))
	finished.emit()


## Etkileşim ya da duraklat: sahneyi geç.
func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("pause") or InputManager.is_click_interact(event):
		get_viewport().set_input_as_handled()
		_end()


# --- Kayıt ---------------------------------------------------------------------------
func save_state(data: Dictionary) -> void:
	data["finale_done"] = done


func load_state(data: Dictionary) -> void:
	done = bool(data.get("finale_done", false))
	if done:
		_light_step(1.0)
		_motes_on()
