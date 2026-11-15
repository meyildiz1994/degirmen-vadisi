extends Node3D
## Derenin üstündeki yıkık köprü. Kökeni dere merkezinde, su seviyesinde.
## Ortadaki kirişler kırık, kalaslar eksik; yalnızca iki ayak ve uçlar yürünebilir.
## Aşama 4'te onarıldığında mesh yenisiyle Tween'le değişecek.

@onready var interactable_west: Interactable = $InteractableWest
@onready var interactable_east: Interactable = $InteractableEast

const DECK_WIDTH := 1.9

var half_span := 3.4
var deck_y := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 5
	half_span = ValleyShape.river_half_width(global_position.z) + 1.6
	deck_y = 1.05
	var mi := MeshInstance3D.new()
	mi.name = "BrokenBridge"
	mi.mesh = _build_broken()
	mi.material_override = WatercolorMaterials.vertex_colored(true)
	add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	sb.add_child(cs)
	add_child(sb)
	interactable_west.position = Vector3(-half_span - 0.6, 0.6, 0)
	interactable_east.position = Vector3(half_span + 0.6, 0.6, 0)


func _plank_color() -> Color:
	return Palette.WOOD_OLD.lerp(Palette.WOOD, _rng.randf() * 0.6).lerp(Palette.MOSS_DARK, _rng.randf() * 0.12)


func _build_broken() -> ArrayMesh:
	var kit := MeshKit.new()
	var bed := -ValleyShape.BED_DEPTH - 0.2
	# Taş ayaklar (iki kıyıda)
	for side: float in [-1.0, 1.0]:
		var x: float = side * (half_span - 0.7)
		var h := deck_y - bed
		for r in int(h / 0.45) + 1:
			var y := bed + r * 0.45 + 0.22
			if y > deck_y - 0.05:
				break
			kit.box(Vector3(x, y, 0), Vector3(1.3, 0.44, DECK_WIDTH + 0.5), Palette.STONE.lerp(Palette.STONE_DARK, _rng.randf() * 0.5))
	# Kirişler: kuzey kiriş batıdan kırık uçla sarkıyor, güney kiriş kopmuş ve suya düşmüş
	var beam_z := DECK_WIDTH * 0.5 - 0.15
	kit.box(Vector3(-half_span * 0.55, deck_y - 0.12, -beam_z), Vector3(half_span * 0.9, 0.2, 0.2), Palette.WOOD_DARK, Vector3(0, 0, -0.08))
	kit.box(Vector3(half_span * 0.62, deck_y - 0.12, -beam_z), Vector3(half_span * 0.75, 0.2, 0.2), Palette.WOOD_DARK, Vector3(0, 0, 0.05))
	kit.box(Vector3(-half_span * 0.75, deck_y - 0.12, beam_z), Vector3(half_span * 0.55, 0.2, 0.2), Palette.WOOD_DARK)
	kit.box(Vector3(half_span * 0.1, -0.15, beam_z + 0.2), Vector3(half_span * 1.1, 0.2, 0.2), Palette.WOOD_DARK.lerp(Palette.MOSS_DARK, 0.3), Vector3(0.1, 0.25, 0.32))
	# Kalaslar: uçlarda var, ortada boşluk
	var x := -half_span + 0.2
	while x < half_span - 0.2:
		var gap := absf(x) < half_span * 0.42
		if not gap and _rng.randf() > 0.12:
			var tilt := Vector3(_rng.randf_range(-0.04, 0.04), _rng.randf_range(-0.05, 0.05), 0)
			kit.box(Vector3(x, deck_y + 0.02, _rng.randf_range(-0.05, 0.05)), Vector3(0.3, 0.07, DECK_WIDTH), _plank_color(), tilt)
		x += 0.36
	# Sarkan ve suda yüzen kalaslar
	kit.box(Vector3(-half_span * 0.38, deck_y - 0.5, 0.1), Vector3(0.3, 0.07, DECK_WIDTH), _plank_color(), Vector3(0.0, 0.1, 1.1))
	kit.box(Vector3(half_span * 0.2, 0.02, 1.8), Vector3(0.3, 0.07, DECK_WIDTH * 0.8), _plank_color(), Vector3(0, 0.9, 0.05))
	kit.box(Vector3(-0.4, 0.0, -2.2), Vector3(0.3, 0.07, DECK_WIDTH * 0.7), _plank_color(), Vector3(0.05, -0.6, 0))
	# Korkuluk dikmeleri (biri devrik)
	for side: float in [-1.0, 1.0]:
		var px: float = side * (half_span - 0.35)
		kit.box(Vector3(px, deck_y + 0.5, -DECK_WIDTH * 0.5), Vector3(0.12, 1.0, 0.12), Palette.WOOD_DARK)
		kit.box(Vector3(px, deck_y + 0.5, DECK_WIDTH * 0.5), Vector3(0.12, 1.0, 0.12), Palette.WOOD_DARK, Vector3(0.0, 0.0, side * 0.45) if side > 0 else Vector3.ZERO)
	kit.box(Vector3(-half_span + 0.6, deck_y + 0.9, -DECK_WIDTH * 0.5), Vector3(1.0, 0.08, 0.08), Palette.WOOD)
	return kit.commit()
