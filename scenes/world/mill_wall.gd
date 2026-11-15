class_name MillWall
extends RepairSite
## Değirmenin dere tarafındaki yıkık duvarı: üç sıra (alt, orta, üst) Duvar Taşı ister.
## Her sıranın yıkık hali (eksik taşlar) ve örülmüş hali ayrı mesh; takılan taşın gövde
## malzemesi rengi verir. Görev adımında boş sıralar yarı saydam ipucu olarak görünür.

const BANDS := {"wall_low": [1, 2], "wall_mid": [3, 4], "wall_top": [5, 5]}
const KEEP := {"wall_low": 0.6, "wall_mid": 0.25, "wall_top": 0.0}

var size := Vector3(4.4, 3.0, 4.0)
var interactable: Interactable
var _rng := RandomNumberGenerator.new()
var _mat: Material
var _ghost_mat: StandardMaterial3D
var _broken := {}
var _pieces := {}
var _piece_keys := {}
var _ghosts := {}
var _pulse := 0.0


func _init() -> void:
	site_id = "mill_wall"


func _ready() -> void:
	super._ready()
	_mat = WatercolorMaterials.vertex_colored(true)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(Palette.SUNSET_LIGHT.lightened(0.35), 0.5)
	for id: String in BANDS:
		_rng.seed = 40 + id.length()
		if KEEP[id] > 0.0:
			var kit := MeshKit.new()
			StoneWall.rows(kit, _rng, _start(), Vector3.BACK, size.z, BANDS[id][0], BANDS[id][1], KEEP[id])
			_broken[id] = _instance(kit.commit(), _mat)
		else:
			_broken[id] = _instance(null, _mat)  # üst sıra tamamen yıkık
		var r0: int = BANDS[id][0]
		var r1: int = BANDS[id][1]
		var g := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(StoneWall.WALL_T + 0.1, (r1 - r0 + 1) * StoneWall.ROW_H, size.z)
		g.mesh = bm
		g.position = Vector3(_start().x, 0.1 + (r0 + r1 + 1) * 0.5 * StoneWall.ROW_H, 0)
		g.material_override = _ghost_mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_ghosts[id] = g
	# Duvar yıkıkken de içeri girilmesin: tam boy görünmez çarpışma.
	var sb := StaticBody3D.new()
	sb.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(StoneWall.WALL_T, size.y, size.z)
	cs.shape = shape
	cs.position = Vector3(_start().x, 0.1 + size.y * 0.5, 0)
	sb.add_child(cs)
	add_child(sb)
	interactable = Interactable.new()
	interactable.name = "WallInteractable"
	interactable.position = Vector3(size.x * 0.5 + 0.9, 0.6, -size.z * 0.5 - 0.8)
	interactable.radius = 2.8
	interactable.focus_bias = 0.3
	interactable.interacted.connect(func(_by): open_requested.emit(self))
	add_child(interactable)
	GameState.quest_changed.connect(func(_k): _refresh_ghosts())
	_apply_visuals(false)


func _start() -> Vector3:
	return Vector3(size.x * 0.5, 0.1, -size.z * 0.5)


func _instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


func _apply_visuals(animate: bool) -> void:
	if _broken.is_empty():
		return
	for id: String in BANDS:
		var filled := Repair.is_filled(state, id)
		_broken[id].visible = not filled
		if filled:
			_show_piece(id, str(Repair.slot_state(state, id)["part"]), animate)
		elif _pieces.has(id):
			_pieces[id].visible = false
	var done := is_complete()
	interactable.display_name_key = "NAME_MILL_WALL_FIXED" if done else "NAME_MILL_WALL"
	interactable.action_key = "ACTION_INSPECT" if done else "ACTION_REPAIR"
	_refresh_ghosts()


## Örülen sıra aşağıdan yukarı "büyür".
func _show_piece(id: String, key: String, animate: bool) -> void:
	var mi: MeshInstance3D = _pieces.get(id)
	if mi == null or _piece_keys.get(id, "") != key:
		if mi != null:
			mi.queue_free()
		_rng.seed = 70 + id.length()
		var kit := MeshKit.new()
		var tint := Materials.color(Crafting.part_material(key))
		StoneWall.rows(kit, _rng, _start(), Vector3.BACK, size.z, BANDS[id][0], BANDS[id][1], 1.0, tint)
		mi = _instance(kit.commit(), _mat)
		_pieces[id] = mi
		_piece_keys[id] = key
		if animate:
			var base_y := 0.1 + float(BANDS[id][0]) * StoneWall.ROW_H
			mi.scale = Vector3(1, 0.05, 1)
			mi.position = Vector3(0, base_y * 0.95, 0)
			var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(mi, "scale", Vector3.ONE, 0.55)
			t.tween_property(mi, "position", Vector3.ZERO, 0.55)
	mi.visible = true


func _refresh_ghosts() -> void:
	var show_hint := GameState.tutorial_step >= Tutorial.Step.MILL_WALL and GameState.tutorial_step < Tutorial.Step.DONE
	# Yalnız sıradaki boş sıra ipucu olur (hepsi birden duvarı tamam gibi gösterir).
	var next := ""
	for id: String in BANDS:
		if not Repair.is_filled(state, id):
			next = id
			break
	for id: String in _ghosts:
		_ghosts[id].visible = show_hint and id == next


func _process(delta: float) -> void:
	super._process(delta)
	_pulse += delta * 2.4
	_ghost_mat.albedo_color.a = 0.18 + 0.22 * (0.5 + 0.5 * sin(_pulse))


func _on_installed(_slot_id: String, _weak: bool) -> void:
	AudioManager.play_sfx_3d("slot_place", global_position)
	_apply_visuals(true)


func _on_completed() -> void:
	AudioManager.play_sfx("repair_done")
	PlatformServices.vibrate(60)
	_apply_visuals(false)  # "done" bayrağı artık açık: ad, jant vb. tamam haline geçsin


## Zayıf sıra çatlar: taşları dökülür, yıkık hali geri gelir.
func _on_cracked(slot_ids: Array) -> void:
	AudioManager.play_sfx_3d("part_crack", global_position)
	PlatformServices.vibrate(80)
	var t := create_tween().set_parallel(true)
	for id: String in slot_ids:
		var mi: MeshInstance3D = _pieces.get(id)
		if mi != null:
			t.tween_property(mi, "position", Vector3(0.6, -0.4, 0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_property(mi, "rotation:z", -0.2, 0.5)
	t.chain().tween_callback(func():
		for id: String in _pieces:
			_pieces[id].position = Vector3.ZERO
			_pieces[id].rotation = Vector3.ZERO
		_apply_visuals(false))
