class_name RockGatherable
extends Gatherable
## Kaya, bakır ya da demir damarı: kazmayla kırılır, geride çakıl kalır,
## süre dolunca topraktan yeniden yükselir. Çarpışması kırılınca kapanır.

var _visual: Node3D
var _rubble: Node3D
var _collider: CollisionShape3D
var _shake := 0.0
var _rest := Vector3.ZERO


## meshes: [Mesh, yerel Transform3D] listesi (ana kaya ve yan kayalar).
func setup(meshes: Array, collider_radius: float, rubble_color: Color) -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	for m in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m[0]
		mi.transform = m[1]
		mi.material_override = WatercolorMaterials.vertex_colored(true)
		_visual.add_child(mi)
	_rubble = Node3D.new()
	_rubble.name = "Rubble"
	add_child(_rubble)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(save_id)
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.rock_mesh(0.14, 40 + i, rubble_color)
		mi.material_override = WatercolorMaterials.vertex_colored(false)
		mi.position = Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
		_rubble.add_child(mi)
	_rubble.visible = false
	var body := StaticBody3D.new()
	body.set_meta("surface", "stone")
	add_child(body)
	_collider = CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = collider_radius
	_collider.shape = sph
	_collider.position = Vector3(0, collider_radius * 0.4, 0)
	body.add_child(_collider)
	_rest = _visual.position


func _apply_state() -> void:
	if _visual == null:
		return
	_visual.visible = state != State.DEPLETED
	_rubble.visible = state != State.READY
	_collider.disabled = state == State.DEPLETED
	_update_growth()


func _update_growth() -> void:
	if state == State.GROWING:
		var g := ease(growth, 0.6)
		_visual.scale = Vector3.ONE * lerpf(0.2, 1.0, g)
		_visual.position = _rest + Vector3(0, lerpf(-0.4, 0.0, g), 0)
		_collider.disabled = growth < 0.6
	else:
		_visual.scale = Vector3.ONE
		_visual.position = _rest


func _on_hit(sweet: bool) -> void:
	_shake = 0.3 if sweet else 0.22
	set_process(true)


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(_shake - delta, 0.0)
		var k := _shake / 0.3
		_visual.position = _rest + Vector3(sin(_shake * 90.0), 0, cos(_shake * 70.0)) * 0.05 * k
		# Darbede kaya kısa bir an basılır, sonra yaylanarak geri gelir.
		var sq := sin(k * PI) * 0.09 * k
		_visual.scale = Vector3(1.0 + sq * 0.6, 1.0 - sq, 1.0 + sq * 0.6)
		if _shake <= 0.0:
			_visual.position = _rest
			_visual.scale = Vector3.ONE
	if state == State.READY:
		if _shake <= 0.0:
			set_process(false)
		return
	super._process(delta)


func fx_point() -> Vector3:
	return global_position + Vector3(0, 0.55, 0)


func highlight_parts() -> Array:
	var out := []
	if _visual == null:
		return out
	for c in _visual.get_children():
		var mi := c as MeshInstance3D
		out.append([mi.mesh, mi.global_transform])
	return out
