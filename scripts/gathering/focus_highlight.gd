class_name FocusHighlight
extends Node3D
## Odaktaki kaynağı yumuşak, sıcak bir ışık çizgisiyle belirtir (dokunmatikte şart,
## PC'de de açık). Hedefin highlight_parts() verdiği mesh'leri ters kabukla çizer.

const SHADER := preload("res://shaders/focus_glow.gdshader")

var target: Node = null
var _pool: Array[MeshInstance3D] = []
var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	top_level = true


func set_target(t: Node) -> void:
	target = t if t != null and t.has_method("highlight_parts") else null
	if target == null:
		_hide_from(0)


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_hide_from(0)
		return
	var parts: Array = target.highlight_parts()
	var visible_now: bool = target.can_focus() if target.has_method("can_focus") else true
	if not visible_now:
		parts = []
	for i in parts.size():
		var mi := _slot(i)
		mi.mesh = parts[i][0]
		mi.global_transform = parts[i][1]
		mi.visible = true
	_hide_from(parts.size())


func _slot(i: int) -> MeshInstance3D:
	while _pool.size() <= i:
		var mi := MeshInstance3D.new()
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_pool.append(mi)
	return _pool[i]


func _hide_from(n: int) -> void:
	for i in range(n, _pool.size()):
		_pool[i].visible = false
