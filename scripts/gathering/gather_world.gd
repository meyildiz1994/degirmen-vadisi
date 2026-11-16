class_name GatherWorld
extends Node3D
## Toplama sisteminin dünya tarafı: tüm kaynakları dinler, ganimeti heybeye ekler,
## parçacık/ses/titreşim geri bildirimini verir, fidan dikimini yürütür ve
## kaynakların durumunu (kesilen ağaçlar, dikilen fidanlar) kaydeder.

signal item_arrived(id: String, amount: int)
signal resource_gathered(resource_id: String)

var player: Player
var vegetation: Node3D
var tree_field: TreeField
var fx: GatherFx
var drops: DropFlyer
var highlight: FocusHighlight
var plant_spot: PlantSpot
var _gatherables: Array[Gatherable] = []
var _by_id := {}


func setup(p: Player, veg: Node3D, extra: Array[Gatherable]) -> void:
	player = p
	vegetation = veg
	tree_field = veg.tree_field
	add_to_group(SaveSystem.PERSIST_GROUP)
	fx = GatherFx.new()
	fx.name = "Fx"
	add_child(fx)
	drops = DropFlyer.new()
	drops.name = "Drops"
	drops.player = p
	drops.arrived.connect(func(id, n): item_arrived.emit(id, n))
	add_child(drops)
	highlight = FocusHighlight.new()
	highlight.name = "Highlight"
	add_child(highlight)
	plant_spot = PlantSpot.new()
	plant_spot.name = "PlantSpot"
	plant_spot.player = p
	plant_spot.vegetation = veg
	plant_spot.planted.connect(_on_planted)
	add_child(plant_spot)
	for t in tree_field.trees:
		_register(t.gatherable)
	for g in extra:
		_register(g)
	tree_field.tree_fell.connect(_on_tree_fell)
	tree_field.tree_grown.connect(_on_tree_grown)
	p.focus_changed.connect(highlight.set_target)
	p.gather.hit_landed.connect(_on_hit)


func _register(g: Gatherable) -> void:
	_gatherables.append(g)
	_by_id[g.save_id] = g
	g.depleted.connect(_on_depleted.bind(g))


func _on_hit(g: Gatherable, sweet: bool) -> void:
	var dir := (player.global_position - g.fx_point())
	dir.y = 0.0
	fx.hit(g.fx_kind(), g.fx_point(), dir.normalized(), sweet)
	AudioManager.play_sfx_3d(g.sfx_hit(), g.fx_point())
	if sweet:
		AudioManager.play_sfx("sweet_hit", -2.0)
	PlatformServices.vibrate(45 if sweet else 22)


func _on_depleted(loot: Dictionary, g: Gatherable) -> void:
	for id in loot:
		GameState.inventory.add(id, loot[id])
	drops.spawn(loot, g.fx_point())
	if g.is_hand():
		fx.burst(g.fx_kind(), g.fx_point(), Vector3.UP, 0.8)
		AudioManager.play_sfx_3d("gather_pickup", g.fx_point())
	else:
		AudioManager.play_sfx_3d(g.sfx_done(), g.fx_point(), 2.0)
		PlatformServices.vibrate(70)
	resource_gathered.emit(g.resource_id)


func _on_tree_fell(pos: Vector3, _kind: String) -> void:
	fx.burst("leaf", pos + Vector3(0, 0.8, 0), Vector3.UP, 2.2)
	fx.burst("dust", pos, Vector3.UP, 1.5)


func _on_tree_grown(pos: Vector3, _kind: String) -> void:
	fx.burst("sparkle", pos + Vector3(0, 1.8, 0), Vector3.UP, 1.2)
	AudioManager.play_sfx_3d("sapling_grown", pos + Vector3(0, 1.0, 0))


func _on_planted(seed_id: String, pos: Vector3) -> void:
	var kind := "oak" if Materials.item(seed_id).get("grows", "") == "oak_tree" else "pine"
	var t := tree_field.plant(kind, pos)
	if t == null:
		GameState.inventory.add(seed_id, 1)  # yer yoksa tohum geri
		return
	fx.burst("dust", pos + Vector3(0, 0.1, 0), Vector3.UP, 0.8)
	AudioManager.play_sfx_3d("sapling_plant", pos)


# --- İki kişilik: 2. oyuncunun vuruş geri bildirimi ve odak ışığı ---------------------------
var _extra_highlights := {}


func add_player(p: Player) -> void:
	var h := FocusHighlight.new()
	h.name = "Highlight%d" % p.index
	add_child(h)
	_extra_highlights[p] = h
	p.focus_changed.connect(h.set_target)
	p.gather.hit_landed.connect(_on_hit_by.bind(p))


func remove_player(p: Player) -> void:
	var h: FocusHighlight = _extra_highlights.get(p)
	if h != null:
		h.queue_free()
	_extra_highlights.erase(p)


func _on_hit_by(g: Gatherable, sweet: bool, p: Player) -> void:
	var dir := (p.global_position - g.fx_point())
	dir.y = 0.0
	fx.hit(g.fx_kind(), g.fx_point(), dir.normalized(), sweet)
	AudioManager.play_sfx_3d(g.sfx_hit(), g.fx_point())
	if sweet:
		AudioManager.play_sfx("sweet_hit", -2.0)


# --- Kayıt -----------------------------------------------------------------------
func save_state(data: Dictionary) -> void:
	var res := {}
	for g in _gatherables:
		if g.state != Gatherable.State.READY or g.progress > 0.0:
			res[g.save_id] = g.to_save()
	data["world"] = {"resources": res, "planted": tree_field.planted_list()}


func load_state(data: Dictionary) -> void:
	var w: Dictionary = data.get("world", {})
	for e: Dictionary in w.get("planted", []):
		var g: Gatherable = _by_id.get(str(e.get("slot", "")))
		if g is TreeGatherable:
			var x := float(e.get("x", 0.0))
			var z := float(e.get("z", 0.0))
			tree_field.plant_in(g.data, Vector3(x, ValleyShape.height(x, z), z))
	var res: Dictionary = w.get("resources", {})
	for id in res:
		if _by_id.has(id) and typeof(res[id]) == TYPE_ARRAY:
			(_by_id[id] as Gatherable).from_save(res[id])
