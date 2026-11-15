extends RepairSite
## Derenin üstündeki köprü. Kökeni dere merkezinde, su seviyesinde.
## Yıkıkken ortası boş: iki kıyıdaki ayaklar ve uç kalaslar yürünebilir, ortada bariyer var.
## Onarım yuvaları (data/repairs.json): kuzey kiriş, güney kiriş, ortadaki bağlantı.
## Hepsi takılınca orta kalaslar tek tek yerine iner, geçiş açılır (demir damarına yol).
## Zayıf parça takıldıysa oyuncu birkaç kez geçtikten sonra, batı kıyıya döndüğünde çatlar;
## oyuncu hiçbir zaman doğu kıyıda mahsur kalmaz.

@onready var interactable_west: Interactable = $InteractableWest
@onready var interactable_east: Interactable = $InteractableEast

const DECK_WIDTH := 1.9
const PLANK_STEP := 0.36

var half_span := 3.4
var deck_y := 1.05
var gap_half := 1.4
var beam_z := 0.8
var player: Node3D

var _rng := RandomNumberGenerator.new()
var _mat: ShaderMaterial
var _ghost_mat: StandardMaterial3D
var _broken := {}        ## slot_id → MeshInstance3D (yıkık hali)
var _pieces := {}        ## slot_id → MeshInstance3D (takılan parça)
var _piece_keys := {}    ## slot_id → takılı parçanın anahtarı (renk için)
var _ghosts := {}        ## slot_id → MeshInstance3D (yarı saydam "buraya" ipucu)
var _debris: MeshInstance3D
var _mid_planks: Array[MeshInstance3D] = []
var _gates: Array[CollisionShape3D] = []
var _mid_deck: CollisionShape3D
var _last_side := 0
var _pulse := 0.0
var _anim: Tween


func _ready() -> void:
	super._ready()
	_rng.seed = 5
	# _ready, dünya köprüyü yerleştirmeden önce çalışır: z'yi sabitten al.
	half_span = ValleyShape.river_half_width(ValleyShape.BRIDGE_Z) + 2.0
	gap_half = half_span * 0.42
	beam_z = DECK_WIDTH * 0.5 - 0.15
	_mat = WatercolorMaterials.vertex_colored(true)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(Palette.SUNSET_LIGHT.lightened(0.35), 0.5)
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_base()
	_build_broken()
	_build_mid_planks()
	_build_ghosts()
	_build_blockers()
	interactable_west.position = Vector3(-half_span - 0.6, 0.6, 0)
	interactable_east.position = Vector3(half_span + 0.6, 0.6, 0)
	for it: Interactable in [interactable_west, interactable_east]:
		it.message_key = ""
		it.interacted.connect(func(_by): open_requested.emit(self))
	GameState.quest_changed.connect(func(_k): _refresh_ghosts())
	_apply_visuals(false)


# --- Yapım ---------------------------------------------------------------------------
func _plank_color() -> Color:
	return Palette.WOOD_OLD.lerp(Palette.WOOD, _rng.randf() * 0.6).lerp(Palette.MOSS_DARK, _rng.randf() * 0.12)


func _instance(mesh: Mesh, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat != null else _mat
	add_child(mi)
	return mi


## Taş ayaklar, uç kalaslar, korkuluk dikmeleri: her durumda var, yürünebilir.
func _build_base() -> void:
	var kit := MeshKit.new()
	var bed := -ValleyShape.BED_DEPTH - 0.2
	for side: float in [-1.0, 1.0]:
		var x: float = side * (half_span - 0.7)
		var h := deck_y - bed
		for r in int(h / 0.45) + 1:
			var y := bed + r * 0.45 + 0.22
			if y > deck_y - 0.05:
				break
			kit.box(Vector3(x, y, 0), Vector3(1.3, 0.44, DECK_WIDTH + 0.5), Palette.STONE.lerp(Palette.STONE_DARK, _rng.randf() * 0.5))
	var x := -half_span + 0.2
	while x < half_span - 0.2:
		if absf(x) >= gap_half and _rng.randf() > 0.12:
			var tilt := Vector3(_rng.randf_range(-0.04, 0.04), _rng.randf_range(-0.05, 0.05), 0)
			kit.box(Vector3(x, deck_y + 0.02, _rng.randf_range(-0.05, 0.05)), Vector3(0.3, 0.07, DECK_WIDTH), _plank_color(), tilt)
		x += PLANK_STEP
	for side: float in [-1.0, 1.0]:
		var px: float = side * (half_span - 0.35)
		kit.box(Vector3(px, deck_y + 0.5, -DECK_WIDTH * 0.5), Vector3(0.12, 1.0, 0.12), Palette.WOOD_DARK)
		kit.box(Vector3(px, deck_y + 0.5, DECK_WIDTH * 0.5), Vector3(0.12, 1.0, 0.12), Palette.WOOD_DARK)
	kit.box(Vector3(-half_span + 0.6, deck_y + 0.9, -DECK_WIDTH * 0.5), Vector3(1.0, 0.08, 0.08), Palette.WOOD)
	_add_ramps(kit)
	var mi := _instance(kit.commit())
	mi.name = "BridgeBase"
	var sb := StaticBody3D.new()
	sb.set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	sb.add_child(cs)
	add_child(sb)


## İki uçta kıyıdan güverteye eğimli kalas rampa (yürünebilir, trimesh çarpışmasına girer).
## _ready'de köprü henüz yerleşmediği için zemin yüksekliği sabit köprü konumundan okunur.
func _add_ramps(kit: MeshKit) -> void:
	var bz := ValleyShape.BRIDGE_Z
	var bx := ValleyShape.river_x(bz)
	var base_y := ValleyShape.water_y(bz)
	for side: float in [-1.0, 1.0]:
		var x0: float = side * (half_span + 1.6)
		var x1: float = side * (half_span - 0.2)
		var y0 := ValleyShape.height(bx + x0, bz) - base_y - 0.06
		var y1 := deck_y + 0.03
		var run := absf(x1 - x0)
		var ang := atan2(y1 - y0, run)
		var mid := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0)
		var length := sqrt(run * run + (y1 - y0) * (y1 - y0))
		kit.box(mid, Vector3(length, 0.1, DECK_WIDTH - 0.1), Palette.WOOD_OLD.lerp(Palette.WOOD, 0.3), Vector3(0, 0, -side * ang))
		for i in 4:
			var t := (i + 0.5) / 4.0
			var p := Vector3(lerpf(x0, x1, t), lerpf(y0, y1, t) + 0.06, 0)
			kit.box(p, Vector3(0.12, 0.05, DECK_WIDTH - 0.05), Palette.WOOD_DARK, Vector3(0, 0, -side * ang))


## Yıkık hal: sarkan kuzey kiriş, suya düşmüş güney kiriş, sarkan ve yüzen kalaslar.
func _build_broken() -> void:
	var y := deck_y - 0.12
	var north := MeshKit.new()
	north.box(Vector3(-half_span * 0.55, y, -beam_z), Vector3(half_span * 0.9, 0.2, 0.2), Palette.WOOD_DARK, Vector3(0, 0, -0.08))
	north.box(Vector3(half_span * 0.62, y, -beam_z), Vector3(half_span * 0.75, 0.2, 0.2), Palette.WOOD_DARK, Vector3(0, 0, 0.05))
	_broken["beam_north"] = _instance(north.commit())
	var south := MeshKit.new()
	south.box(Vector3(-half_span * 0.75, y, beam_z), Vector3(half_span * 0.55, 0.2, 0.2), Palette.WOOD_DARK)
	south.box(Vector3(half_span * 0.1, -0.15, beam_z + 0.2), Vector3(half_span * 1.1, 0.2, 0.2), Palette.WOOD_DARK.lerp(Palette.MOSS_DARK, 0.3), Vector3(0.1, 0.25, 0.32))
	_broken["beam_south"] = _instance(south.commit())
	var debris := MeshKit.new()
	debris.box(Vector3(-half_span * 0.38, deck_y - 0.5, 0.1), Vector3(0.3, 0.07, DECK_WIDTH), _plank_color(), Vector3(0.0, 0.1, 1.1))
	debris.box(Vector3(half_span * 0.2, 0.02, 1.8), Vector3(0.3, 0.07, DECK_WIDTH * 0.8), _plank_color(), Vector3(0, 0.9, 0.05))
	debris.box(Vector3(-0.4, 0.0, -2.2), Vector3(0.3, 0.07, DECK_WIDTH * 0.7), _plank_color(), Vector3(0.05, -0.6, 0))
	debris.box(Vector3(half_span - 0.35, deck_y + 0.5, DECK_WIDTH * 0.5 + 0.2), Vector3(0.12, 1.0, 0.12), Palette.WOOD_DARK, Vector3(0.0, 0.0, 0.45))
	_debris = _instance(debris.commit())


func _beam_mesh(color: Color, z: float) -> ArrayMesh:
	var kit := MeshKit.new()
	kit.box(Vector3(0, deck_y - 0.12, z), Vector3(half_span * 2.0 - 0.5, 0.22, 0.22), color)
	return kit.commit()


func _link_mesh(color: Color) -> ArrayMesh:
	var kit := MeshKit.new()
	for z: float in [-beam_z, beam_z]:
		kit.box(Vector3(0, deck_y - 0.12, z), Vector3(0.34, 0.3, 0.3), color)
	kit.box(Vector3(0, deck_y - 0.14, 0), Vector3(0.18, 0.14, beam_z * 2.0), color.darkened(0.1))
	return kit.commit()


func _slot_mesh(slot_id: String, color: Color) -> ArrayMesh:
	match slot_id:
		"beam_north": return _beam_mesh(color, -beam_z)
		"beam_south": return _beam_mesh(color, beam_z)
		_: return _link_mesh(color)


## Orta kalaslar ayrı ayrı: onarım bitince sırayla yerine iner.
func _build_mid_planks() -> void:
	var x := -half_span + 0.2
	while x < half_span - 0.2:
		if absf(x) < gap_half:
			var kit := MeshKit.new()
			kit.box(Vector3.ZERO, Vector3(0.3, 0.07, DECK_WIDTH), Palette.WOOD.lerp(Palette.WOOD_OLD, _rng.randf() * 0.35))
			var mi := _instance(kit.commit())
			mi.position = Vector3(x, deck_y + 0.02, 0)
			mi.set_meta("home", mi.position)
			_mid_planks.append(mi)
		x += PLANK_STEP


func _build_ghosts() -> void:
	for s: Dictionary in Repair.slots(site_id):
		var mi := _instance(_slot_mesh(s["id"], Color.WHITE), _ghost_mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghosts[s["id"]] = mi


## Yan duvarlar hep var (dereye düşülmez). Boşluğun iki ucunda kapı, onarılınca orta zemin.
func _build_blockers() -> void:
	var walls := StaticBody3D.new()
	walls.name = "BridgeBlockers"
	add_child(walls)
	for side: float in [-1.0, 1.0]:
		walls.add_child(_box_shape(Vector3(0, deck_y + 1.0, side * (DECK_WIDTH * 0.5 + 0.12)), Vector3(half_span * 2.0 + 1.0, 2.6, 0.2)))
	for side: float in [-1.0, 1.0]:
		var g := _box_shape(Vector3(side * (gap_half + 0.05), deck_y + 1.0, 0), Vector3(0.2, 2.6, DECK_WIDTH + 0.2))
		walls.add_child(g)
		_gates.append(g)
	var deck := StaticBody3D.new()
	deck.set_meta("surface", "wood")
	add_child(deck)
	_mid_deck = _box_shape(Vector3(0, deck_y - 0.02, 0), Vector3(gap_half * 2.0 + 0.6, 0.14, DECK_WIDTH))
	deck.add_child(_mid_deck)


func _box_shape(pos: Vector3, size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	return cs


# --- Görünüm -------------------------------------------------------------------------
func _apply_visuals(animate: bool) -> void:
	if _debris == null:
		return  # henüz kurulmadı (kayıt _ready'den önce yüklenmez ama güvenli olsun)
	var passable := Repair.is_complete(state)
	for s: Dictionary in Repair.slots(site_id):
		var id: String = s["id"]
		var filled := Repair.is_filled(state, id)
		if _broken.has(id):
			_broken[id].visible = not filled
		if filled:
			_show_piece(id, str(Repair.slot_state(state, id)["part"]), animate)
		elif _pieces.has(id):
			_pieces[id].visible = false
	_debris.visible = not passable
	for g: CollisionShape3D in _gates:
		g.set_deferred("disabled", passable)
	_mid_deck.set_deferred("disabled", not passable)
	if passable and animate:
		_drop_planks()
	else:
		for p: MeshInstance3D in _mid_planks:
			p.visible = passable
			p.position = p.get_meta("home")
			p.rotation = Vector3.ZERO
	for it: Interactable in [interactable_west, interactable_east]:
		it.display_name_key = "NAME_BRIDGE_FIXED" if passable else "NAME_BRIDGE"
		it.action_key = "ACTION_INSPECT" if passable else "ACTION_REPAIR"
	_refresh_ghosts()


func _show_piece(slot_id: String, key: String, animate: bool) -> void:
	var mi: MeshInstance3D = _pieces.get(slot_id)
	if mi == null or _piece_keys.get(slot_id, "") != key:
		if mi != null:
			mi.queue_free()
		var col := Materials.color(Crafting.part_material(key)).lerp(Palette.WOOD_DARK, 0.15)
		mi = _instance(_slot_mesh(slot_id, col))
		_pieces[slot_id] = mi
		_piece_keys[slot_id] = key
		if animate:
			mi.position = Vector3(0, 0.8, 0)
			var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(mi, "position", Vector3.ZERO, 0.45)
	mi.visible = true


func _drop_planks() -> void:
	if _anim and _anim.is_valid():
		_anim.kill()
	_anim = create_tween()
	for i in _mid_planks.size():
		var p := _mid_planks[i]
		var home: Vector3 = p.get_meta("home")
		p.visible = false
		p.position = home + Vector3(0, 1.2, 0)
		_anim.tween_callback(p.show)
		_anim.tween_property(p, "position", home, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_anim.tween_callback(AudioManager.play_sfx_3d.bind("footstep_wood", global_position + home, -6.0))


func _refresh_ghosts() -> void:
	var show_hint := GameState.tutorial_step >= Tutorial.Step.BRIDGE
	for id: String in _ghosts:
		_ghosts[id].visible = show_hint and not Repair.is_filled(state, id)


func _process(delta: float) -> void:
	_pulse += delta * 2.4
	_ghost_mat.albedo_color.a = 0.4 + 0.3 * (0.5 + 0.5 * sin(_pulse))


# --- Onarım olayları ---------------------------------------------------------------------
func _on_installed(slot_id: String, _weak: bool) -> void:
	AudioManager.play_sfx_3d("slot_place", global_position)
	_apply_visuals(true)


func _on_completed() -> void:
	AudioManager.play_sfx("repair_done")
	PlatformServices.vibrate(60)


## Çatlama: zayıf parça sarkıp suya düşer, orta kalaslar da onunla gider.
func _on_cracked(slot_ids: Array) -> void:
	AudioManager.play_sfx_3d("part_crack", global_position)
	PlatformServices.vibrate(80)
	if _anim and _anim.is_valid():
		_anim.kill()
	_anim = create_tween().set_parallel(true)
	for id: String in slot_ids:
		var mi: MeshInstance3D = _pieces.get(id)
		if mi != null:
			_anim.tween_property(mi, "rotation:z", 0.25, 0.5)
			_anim.tween_property(mi, "position:y", -1.6, 0.8).set_delay(0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for p: MeshInstance3D in _mid_planks:
		_anim.tween_property(p, "position:y", -1.2, 0.7).set_delay(0.25 + _rng.randf() * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_anim.tween_property(p, "rotation:x", _rng.randf_range(-0.6, 0.6), 0.7).set_delay(0.25)
	_anim.chain().tween_callback(_after_crack)
	# Geçiş hemen kapanır (oyuncu zaten batı kıyıda).
	for g: CollisionShape3D in _gates:
		g.set_deferred("disabled", false)
	_mid_deck.set_deferred("disabled", true)


func _after_crack() -> void:
	for id: String in _pieces:
		_pieces[id].position = Vector3.ZERO
		_pieces[id].rotation = Vector3.ZERO
	_apply_visuals(false)


## Geçişleri say: oyuncu köprünün bir ucundan öbür ucuna geçince +1.
## Zayıf parça varsa her geçişte köprü gıcırdar; yeterince geçilince batı kıyıda çatlar.
func _physics_process(_delta: float) -> void:
	if player == null or not Repair.is_complete(state):
		_last_side = 0
		return
	var local := to_local(player.global_position)
	if absf(local.z) > 3.0 or absf(local.x) < half_span + 0.3:
		return
	var side := 1 if local.x > 0.0 else -1
	if _last_side != 0 and side != _last_side:
		state["crossings"] = int(state["crossings"]) + 1
		if Repair.has_weak(state):
			AudioManager.play_sfx_3d("part_crack", global_position, -12.0)
			_wobble()
	_last_side = side
	if side < 0 and Repair.has_weak(state) and int(state["crossings"]) >= Repair.crack_after():
		crack_weak_parts()


func _wobble() -> void:
	for p: MeshInstance3D in _mid_planks:
		var home: Vector3 = p.get_meta("home")
		var t := create_tween()
		t.tween_property(p, "position:y", home.y - 0.06, 0.12)
		t.tween_property(p, "position:y", home.y, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
