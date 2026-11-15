class_name MillWheel
extends RepairSite
## Değirmen çarkı: 1 aks + 1 dişli + 6 kanat. Kökeni çarkın merkezi; aks -X yönünde duvara gider.
## Yıkıkken çark eğik, aks kopuk, jantta boşluk, kanat yerlerinde kırık kütükler var.
## Aks takılınca çark doğrulur; hepsi takılınca jant kapanır ve çark dönmeye başlar
## (spinning). Zayıf parça varsa bir süre dönüp çatlar ve durur.

signal spinning_changed(on: bool)

const R := 1.7
const PADDLES := 6
const SPIN_SPEED := 0.75     ## rad/sn
const AXLE_LEN := 1.9        ## merkezden duvara

var interactable: Interactable
var spin := 0.0              ## anlık açısal hız
var _tilt: Node3D            ## yıkıkken eğik duran gövde
var _rotor: Node3D           ## dönen kısım
var _rng := RandomNumberGenerator.new()
var _mat: Material
var _ghost_mat: StandardMaterial3D
var _broken := {}
var _pieces := {}
var _piece_keys := {}
var _ghosts := {}
var _rim_fix: MeshInstance3D
var _splash: CPUParticles3D
var _ambience: AudioStreamPlayer3D
var _pulse := 0.0
var _was_spinning := false


func _init() -> void:
	site_id = "mill_wheel"


func _ready() -> void:
	super._ready()
	_rng.seed = 11
	_mat = WatercolorMaterials.vertex_colored(true)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(Palette.SUNSET_LIGHT.lightened(0.35), 0.5)
	_tilt = Node3D.new()
	add_child(_tilt)
	_rotor = Node3D.new()
	_tilt.add_child(_rotor)
	_build_frame()
	_build_broken()
	_build_ghosts()
	_build_splash()
	interactable = Interactable.new()
	interactable.name = "WheelInteractable"
	interactable.position = Vector3(-0.8, 0.0, R + 1.3)
	interactable.radius = 3.0
	interactable.focus_bias = 0.2
	interactable.interacted.connect(func(_by): open_requested.emit(self))
	add_child(interactable)
	GameState.quest_changed.connect(func(_k): _refresh_ghosts())
	_apply_visuals(false)


func _paddle_angle(i: int) -> float:
	return TAU * i / PADDLES + 0.3


func _instance(mesh: Mesh, parent: Node3D, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat != null else _mat
	parent.add_child(mi)
	return mi


## Göbek, iki jant (kırık bölümlerle), kollar. Jant boşluğu onarım bitince kapanır.
func _build_frame() -> void:
	var kit := MeshKit.new()
	var fix := MeshKit.new()
	var segs := 16
	kit.cylinder(Vector3.ZERO, 0.32, 0.32, 0.6, Palette.WOOD_DARK, Vector3(0, 0, PI * 0.5), 10)
	for side: float in [-0.24, 0.24]:
		for i in segs:
			var a := TAU * i / segs + PI / segs
			var r := Vector3(0, cos(a), sin(a))
			var seg_kit := fix if (i == 5 or i == 6 or (side > 0 and i == 11)) else kit
			var col := Palette.WOOD.lerp(Palette.WOOD_OLD, 0.4) if seg_kit == kit else Palette.WOOD.lightened(0.1)
			seg_kit.box(r * R + Vector3(side, 0, 0), Vector3(0.12, 0.14, TAU * R / segs + 0.05), col, Vector3(a, 0, 0))
	for i in PADDLES:
		var a := _paddle_angle(i)
		var r := Vector3(0, cos(a), sin(a))
		for side: float in [-0.2, 0.2]:
			kit.box(r * R * 0.5 + Vector3(side, 0, 0), Vector3(0.09, R, 0.1), Palette.WOOD_DARK, Vector3(a, 0, 0))
	_instance(kit.commit(), _rotor)
	_rim_fix = _instance(fix.commit(), _rotor)


## Yıkık hal: kanat yerlerinde kısa kırık kütükler, kopuk aks parçası.
func _build_broken() -> void:
	for i in PADDLES:
		var a := _paddle_angle(i)
		var r := Vector3(0, cos(a), sin(a))
		var kit := MeshKit.new()
		kit.box(r * (R + 0.02), Vector3(0.5, 0.16, 0.06), Palette.WOOD_OLD.darkened(0.15), Vector3(a + _rng.randf_range(-0.3, 0.3), 0, 0))
		_broken["paddle_%d" % (i + 1)] = _instance(kit.commit(), _rotor)
	var stub := MeshKit.new()
	stub.cylinder(Vector3(-AXLE_LEN + 0.35, 0, 0), 0.12, 0.12, 0.7, Palette.WOOD_DARK, Vector3(0, 0, PI * 0.5), 8)
	_broken["axle"] = _instance(stub.commit(), self)
	# Suya düşmüş eski kanat
	var drift := MeshKit.new()
	drift.box(Vector3(0.9, -0.62, 2.1), Vector3(0.62, 0.06, 0.5), Palette.WOOD_OLD, Vector3(0.1, 0.7, 0.05))
	_broken["drift"] = _instance(drift.commit(), self)


func _slot_mesh(id: String, col: Color) -> ArrayMesh:
	var kit := MeshKit.new()
	if id == "axle":
		kit.cylinder(Vector3(-AXLE_LEN * 0.5 + 0.1, 0, 0), 0.13, 0.13, AXLE_LEN + 0.6, col, Vector3(0, 0, PI * 0.5), 10)
		for x: float in [-AXLE_LEN + 0.2, 0.42]:
			kit.cylinder(Vector3(x, 0, 0), 0.17, 0.17, 0.08, col.darkened(0.25), Vector3(0, 0, PI * 0.5), 10)
	elif id == "gear":
		var gx := -AXLE_LEN + 0.55
		kit.cylinder(Vector3(gx, 0, 0), 0.42, 0.42, 0.12, col, Vector3(0, 0, PI * 0.5), 16)
		for t in 12:
			var a := TAU * t / 12.0
			kit.box(Vector3(gx, cos(a) * 0.48, sin(a) * 0.48), Vector3(0.12, 0.1, 0.1), col.darkened(0.15), Vector3(a, 0, 0))
	else:
		var i := int(id.get_slice("_", 1)) - 1
		var a := _paddle_angle(i)
		var r := Vector3(0, cos(a), sin(a))
		kit.box(r * (R + 0.2), Vector3(0.66, 0.56, 0.07), col, Vector3(a, 0, 0))
	return kit.commit()


func _build_ghosts() -> void:
	for s: Dictionary in Repair.slots(site_id):
		var id: String = s["id"]
		var parent := _rotor if id.begins_with("paddle") or id == "gear" else self
		_ghosts[id] = _instance(_slot_mesh(id, Color.WHITE), parent, _ghost_mat)
		_ghosts[id].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Çarkın altında dönen suyun sıçrattığı damlalar.
func _build_splash() -> void:
	_splash = CPUParticles3D.new()
	_splash.amount = 24
	_splash.lifetime = 0.9
	_splash.emitting = false
	_splash.position = Vector3(0, -R + 0.2, 0.6)
	_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_splash.emission_box_extents = Vector3(0.35, 0.05, 0.4)
	_splash.direction = Vector3(0, 1, 0.6)
	_splash.spread = 35.0
	_splash.initial_velocity_min = 1.2
	_splash.initial_velocity_max = 2.4
	_splash.gravity = Vector3(0, -6.0, 0)
	_splash.scale_amount_min = 0.5
	_splash.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(Palette.PAPER.lerp(Palette.SKY, 0.4), 0.8)
	quad.material = m
	_splash.mesh = quad
	add_child(_splash)


func is_spinning() -> bool:
	return is_complete()


func _apply_visuals(animate: bool) -> void:
	if _broken.is_empty():
		return
	for s: Dictionary in Repair.slots(site_id):
		var id: String = s["id"]
		var filled := Repair.is_filled(state, id)
		if _broken.has(id):
			_broken[id].visible = not filled
		if filled:
			_show_piece(id, str(Repair.slot_state(state, id)["part"]), animate)
		elif _pieces.has(id):
			_pieces[id].visible = false
	var axle := Repair.is_filled(state, "axle")
	var tilt := Vector3.ZERO if axle else Vector3(0.0, 0.0, 0.1)
	if animate:
		create_tween().tween_property(_tilt, "rotation", tilt, 0.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	else:
		_tilt.rotation = tilt
	var done := is_complete()
	_rim_fix.visible = done
	_broken["drift"].visible = not done
	interactable.display_name_key = "NAME_MILL_WHEEL_FIXED" if done else "NAME_MILL_WHEEL"
	interactable.action_key = "ACTION_INSPECT" if done else "ACTION_REPAIR"
	_refresh_ghosts()


func _show_piece(id: String, key: String, animate: bool) -> void:
	var mi: MeshInstance3D = _pieces.get(id)
	if mi == null or _piece_keys.get(id, "") != key:
		if mi != null:
			mi.queue_free()
		var col := Materials.color(Crafting.part_material(key)).lerp(Palette.WOOD, 0.12)
		var parent := _rotor if id.begins_with("paddle") or id == "gear" else self
		mi = _instance(_slot_mesh(id, col), parent)
		_pieces[id] = mi
		_piece_keys[id] = key
		if animate:
			mi.scale = Vector3.ONE * 0.2
			create_tween().tween_property(mi, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	mi.visible = true


func _refresh_ghosts() -> void:
	var show_hint := GameState.tutorial_step >= Tutorial.Step.MILL_WHEEL and GameState.tutorial_step < Tutorial.Step.DONE
	for id: String in _ghosts:
		_ghosts[id].visible = show_hint and not Repair.is_filled(state, id)


## Dönüş: tamamlanınca yavaşça hızlanır, çatlayınca/eksilince yavaşlayıp durur.
func _process(delta: float) -> void:
	super._process(delta)
	_pulse += delta * 2.4
	_ghost_mat.albedo_color.a = 0.25 + 0.2 * (0.5 + 0.5 * sin(_pulse))
	var target := SPIN_SPEED if is_spinning() else 0.0
	spin = move_toward(spin, target, delta * (0.25 if target > 0.0 else 0.6))
	_rotor.rotation.x -= spin * delta
	var on := spin > 0.05
	if on != _was_spinning:
		_was_spinning = on
		_splash.emitting = on
		if on and _ambience == null:
			_ambience = AudioManager.create_ambience("amb_mill_wheel", self, Vector3.ZERO, 6.0, 30.0)
		if _ambience != null and _ambience.stream != null:
			if on:
				_ambience.play()
			else:
				_ambience.stop()
		spinning_changed.emit(on)


func _on_installed(_slot_id: String, _weak: bool) -> void:
	AudioManager.play_sfx_3d("slot_place", global_position)
	_apply_visuals(true)


func _on_completed() -> void:
	AudioManager.play_sfx("repair_done")
	PlatformServices.vibrate(60)
	_apply_visuals(false)  # "done" bayrağı artık açık: ad, jant vb. tamam haline geçsin


## Zayıf parça kopar: kanat suya düşer, çark yavaşlar.
func _on_cracked(slot_ids: Array) -> void:
	AudioManager.play_sfx_3d("part_crack", global_position)
	PlatformServices.vibrate(80)
	for id: String in slot_ids:
		var mi: MeshInstance3D = _pieces.get(id)
		if mi != null:
			var t := create_tween()
			t.tween_property(mi, "position:y", -0.8, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_callback(func(): mi.position = Vector3.ZERO; _apply_visuals(false))
