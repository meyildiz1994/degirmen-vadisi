class_name DropFlyer
extends Node3D
## Ganimet parçaları kaynaktan fırlar, kısa bir yay çizer ve oyuncuya uçar.
## Malzeme heybeye vuruş anında eklenir; bu yalnızca görsel + "geldi" bildirimi.

signal arrived(id: String, amount: int)

const POP_TIME := 0.32
const MAX_BITS_PER_ITEM := 3

class Bit:
	var node: MeshInstance3D
	var vel := Vector3.ZERO
	var t := 0.0
	var id := ""
	var amount := 0     ## 0 değilse bu parça varınca bildirim gönderilir

var player: Node3D
var _bits: Array[Bit] = []
var _meshes := {}
var _materials := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	_rng.randomize()


func spawn(drops: Dictionary, from: Vector3) -> void:
	for id: String in drops:
		var n: int = drops[id]
		var bits := clampi(n, 1, MAX_BITS_PER_ITEM)
		for i in bits:
			var b := Bit.new()
			b.id = id
			b.amount = n if i == bits - 1 else 0
			b.node = MeshInstance3D.new()
			b.node.mesh = _mesh_for(id)
			b.node.material_override = _material_for(id)
			b.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(b.node)
			b.node.global_position = from + Vector3(_rng.randf_range(-0.2, 0.2), 0.1, _rng.randf_range(-0.2, 0.2))
			var a := _rng.randf() * TAU
			b.vel = Vector3(cos(a) * 1.6, _rng.randf_range(3.2, 4.4), sin(a) * 1.6)
			b.t = -i * 0.07
			_bits.append(b)


func _process(delta: float) -> void:
	if _bits.is_empty() or player == null:
		return
	var goal := player.global_position + Vector3(0, 1.0, 0)
	for b: Bit in _bits.duplicate():
		b.t += delta
		if b.t < 0.0:
			continue
		var p := b.node.global_position
		if b.t < POP_TIME:
			b.vel.y -= 14.0 * delta
			p += b.vel * delta
		else:
			var k := clampf((b.t - POP_TIME) * 3.2, 0.0, 1.0)
			var speed := lerpf(4.0, 16.0, k)
			p = p.move_toward(goal, speed * delta)
		b.node.global_position = p
		b.node.rotate_y(delta * 6.0)
		if b.t > POP_TIME and p.distance_to(goal) < 0.25:
			_arrive(b)


func _arrive(b: Bit) -> void:
	_bits.erase(b)
	b.node.queue_free()
	if b.amount > 0:
		AudioManager.play_sfx("gather_pickup", -4.0)
		arrived.emit(b.id, b.amount)


func _mesh_for(id: String) -> Mesh:
	var icon := Materials.icon(id)
	if _meshes.has(icon):
		return _meshes[icon]
	var m: Mesh
	match icon:
		"log", "branch", "reed":
			var c := CylinderMesh.new()
			c.top_radius = 0.07 if icon == "log" else 0.03
			c.bottom_radius = c.top_radius
			c.height = 0.32
			c.radial_segments = 7
			c.rings = 1
			m = c
		"stone", "ore":
			m = MeshKit.rock_mesh(0.11, 3, Color.WHITE)
		_:
			var s := SphereMesh.new()
			s.radius = 0.09
			s.height = 0.16
			s.radial_segments = 8
			s.rings = 4
			m = s
	_meshes[icon] = m
	return m


func _material_for(id: String) -> Material:
	if not _materials.has(id):
		_materials[id] = WatercolorMaterials.object(Materials.color(id), false, false)
	return _materials[id]
