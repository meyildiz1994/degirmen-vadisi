class_name PlantSpot
extends Interactable
## Heybede tohum varken oyuncunun önündeki uygun zemine fidan dikme noktası.
## Başka hedef yoksa seçilir (yüksek focus_bias). Yerde küçük bir toprak izi gösterir.

signal planted(seed_id: String, position: Vector3)

const AHEAD := 1.5

var player: Player
var vegetation: Node3D
var _valid := false
var _ghost: MeshInstance3D
var _ghost_mesh: ArrayMesh


func _ready() -> void:
	super._ready()
	action_key = "ACTION_PLANT"
	radius = 4.0
	focus_bias = 3.0
	top_level = true
	_ghost_mesh = _make_ghost()
	_ghost = MeshInstance3D.new()
	_ghost.mesh = _ghost_mesh
	_ghost.material_override = WatercolorMaterials.vertex_colored(false)
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var fwd := -player.model.global_transform.basis.z
	fwd.y = 0.0
	var p := player.global_position + fwd.normalized() * AHEAD
	p.y = ValleyShape.height(p.x, p.z)
	global_position = p
	var seed_id := GameState.inventory.first_seed()
	_valid = seed_id != "" and not player.gather.active() and vegetation.can_plant(p.x, p.z)
	if seed_id != "":
		display_name_key = Materials.display_name(seed_id)
	_ghost.visible = _valid and player.focus == self


func can_focus() -> bool:
	return _valid


func interact(by: Node) -> void:
	var seed_id := GameState.inventory.first_seed()
	if not _valid or seed_id == "":
		return
	if GameState.inventory.remove(seed_id, 1):
		if by is Player:
			(by as Player).play_pickup()
		planted.emit(seed_id, global_position)
	super.interact(by)


func highlight_parts() -> Array:
	return [[_ghost_mesh, global_transform]] if _valid else []


## Kazılmış toprak + minik filiz.
func _make_ghost() -> ArrayMesh:
	var kit := MeshKit.new()
	kit.cylinder(Vector3(0, 0.02, 0), 0.32, 0.4, 0.06, Palette.EARTH, Vector3.ZERO, 12)
	kit.cylinder(Vector3(0, 0.14, 0), 0.015, 0.02, 0.22, Palette.MOSS_DARK, Vector3.ZERO, 5)
	kit.sphere(Vector3(0.05, 0.25, 0), 0.06, Palette.MOSS_LIGHT, Vector3(1.2, 0.5, 0.8), 6)
	kit.sphere(Vector3(-0.05, 0.22, 0), 0.05, Palette.MOSS_LIGHT, Vector3(1.2, 0.5, 0.8), 6)
	return kit.commit()
