extends Node3D
## Küçük atölye kulübesi: taş temel, dikey tahta duvarlar, kiremit rengi çatı,
## taş baca, sundurma altında tezgâh. Atölye arayüzü Aşama 3'te açılacak.

@onready var interactable: Interactable = $Interactable

const W := 3.6
const D := 3.0
const H := 2.3

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 12
	var mi := MeshInstance3D.new()
	mi.name = "Hut"
	mi.mesh = _build()
	mi.material_override = WatercolorMaterials.vertex_colored(true)
	add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	sb.add_child(cs)
	add_child(sb)


func _build() -> ArrayMesh:
	var kit := MeshKit.new()
	var hw := W * 0.5
	var hd := D * 0.5
	kit.box(Vector3(0, 0.0, 0), Vector3(W + 0.4, 0.5, D + 0.4), Palette.STONE)
	# Dikey tahtalar (kapı güney yüzünde, +z)
	var boards := int(W / 0.3)
	for i in boards:
		var x := -hw + 0.15 + i * 0.3
		var c := Palette.WOOD.lerp(Palette.WOOD_DARK, _rng.randf() * 0.5)
		kit.box(Vector3(x, H * 0.5 + 0.25, -hd), Vector3(0.28, H, 0.1), c)
		var door := absf(x - 0.3) < 0.5
		if door:
			kit.box(Vector3(x, H * 0.5 + 0.25, hd - 0.15), Vector3(0.28, H, 0.06), Palette.INK.lerp(Palette.WOOD_DARK, 0.5))
		else:
			kit.box(Vector3(x, H * 0.5 + 0.25, hd), Vector3(0.28, H, 0.1), c)
	var sideb := int(D / 0.3)
	for i in sideb:
		var z := -hd + 0.15 + i * 0.3
		for sx: float in [-hw, hw]:
			kit.box(Vector3(sx, H * 0.5 + 0.25, z), Vector3(0.1, H, 0.28), Palette.WOOD.lerp(Palette.WOOD_DARK, _rng.randf() * 0.5))
	# Köşe dikmeleri ve pencere
	for sx: float in [-hw, hw]:
		for sz: float in [-hd, hd]:
			kit.box(Vector3(sx, H * 0.5 + 0.25, sz), Vector3(0.2, H + 0.1, 0.2), Palette.WOOD_DARK)
	kit.box(Vector3(-hw - 0.06, 1.5, 0.0), Vector3(0.06, 0.6, 0.8), Palette.SUNSET_LIGHT)
	kit.box(Vector3(-hw - 0.09, 1.5, 0.0), Vector3(0.05, 0.7, 0.08), Palette.WOOD_DARK)
	# Üçgen alınlıklar + çatı
	var top := H + 0.25
	for sz: float in [-hd, hd]:
		kit.prism(Vector3(0, top + 0.6, sz), Vector3(W, 1.2, 0.1), Palette.WOOD_OLD)
	var slope := atan2(1.2, hw)
	var roof_len := sqrt(hw * hw + 1.44) + 0.5
	for side: float in [-1.0, 1.0]:
		var rows := 6
		for r in rows:
			var t := (r + 0.5) / rows
			var pos := Vector3(side * (hw + 0.25) * (1.0 - t), top + 1.2 * t + 0.1, 0)
			var c := Palette.ROOF.lerp(Palette.SUNSET, _rng.randf() * 0.25).lerp(Palette.MOSS, 0.12 if r == 0 else 0.0)
			kit.box(pos, Vector3(roof_len / rows + 0.08, 0.1, D + 1.2), c, Vector3(0, 0, -side * slope))
	# Baca
	kit.box(Vector3(hw - 0.6, top + 1.2, -hd + 0.6), Vector3(0.55, 1.8, 0.55), Palette.STONE.lerp(Palette.STONE_DARK, 0.3))
	# Sundurma + tezgâh (doğu tarafı)
	for z: float in [-hd + 0.1, hd - 0.1]:
		kit.box(Vector3(hw + 1.4, 1.05, z), Vector3(0.14, 2.1, 0.14), Palette.WOOD_DARK)
	kit.box(Vector3(hw + 0.8, 2.15, 0), Vector3(1.7, 0.08, D + 0.2), Palette.ROOF.lerp(Palette.WOOD, 0.4), Vector3(0, 0, -0.18))
	kit.box(Vector3(hw + 0.8, 0.85, 0), Vector3(0.9, 0.12, 2.0), Palette.WOOD)
	for z: float in [-0.8, 0.8]:
		kit.box(Vector3(hw + 0.8, 0.42, z), Vector3(0.7, 0.8, 0.12), Palette.WOOD_DARK)
	kit.box(Vector3(hw + 0.8, 1.0, 0.4), Vector3(0.3, 0.18, 0.5), Palette.STONE_DARK)  # örs taşı
	kit.cylinder(Vector3(hw + 0.75, 1.02, -0.5), 0.22, 0.25, 0.22, Palette.CLAY, Vector3.ZERO, 10)  # kil çanak
	# Kapı önünde odun yığını
	for i in 5:
		kit.cylinder(Vector3(-hw - 0.5, 0.15 + (i % 2) * 0.22 + (i / 3) * 0.22, -0.8 + i * 0.3), 0.12, 0.12, 0.9, Palette.WOOD.lerp(Palette.EARTH, 0.4), Vector3(PI * 0.5, 0, 0), 7)
	return kit.commit()
