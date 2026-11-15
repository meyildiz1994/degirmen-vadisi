@tool
class_name WatercolorPanel
extends PanelContainer
## Suluboya lekesi şeklinde panel: düzensiz, noise maskeli kenar; yarı saydam krem zemin.

const BLOB_SHADER := preload("res://shaders/ui_blob.gdshader")

@export var wash_color := Color(0.97, 0.93, 0.85, 0.86)
@export var padding := Vector2(26, 16)
@export var blob_seed := 0.0

static var _mask: NoiseTexture2D

var _bg: ColorRect


static func mask_noise() -> NoiseTexture2D:
	if _mask == null:
		var n := FastNoiseLite.new()
		n.seed = 8
		n.frequency = 0.02
		n.fractal_octaves = 3
		_mask = NoiseTexture2D.new()
		_mask.width = 256
		_mask.height = 256
		_mask.seamless = true
		_mask.noise = n
	return _mask


func _ready() -> void:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = padding.x
	sb.content_margin_right = padding.x
	sb.content_margin_top = padding.y
	sb.content_margin_bottom = padding.y
	add_theme_stylebox_override("panel", sb)
	_bg = ColorRect.new()
	_bg.name = "_Wash"
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.show_behind_parent = true
	var mat := ShaderMaterial.new()
	mat.shader = BLOB_SHADER
	mat.set_shader_parameter("mask_noise", mask_noise())
	mat.set_shader_parameter("wash_color", wash_color)
	mat.set_shader_parameter("seed", blob_seed if blob_seed != 0.0 else randf() * 10.0)
	_bg.material = mat
	add_child(_bg, false, Node.INTERNAL_MODE_FRONT)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if _bg == null:
		return
	# Leke biraz taşsın: panelden geniş çiz
	_bg.position = Vector2(-10, -8)
	_bg.size = size + Vector2(20, 16)
	(_bg.material as ShaderMaterial).set_shader_parameter("rect_size", _bg.size)
