extends Node3D
## Oyuncu modeli: primitive'lerden tek mesh (tunik, atkı, hasır şapka).
## Yüz yönü -Z.


func _ready() -> void:
	var kit := MeshKit.new()
	# Bacaklar
	for x: float in [-0.12, 0.12]:
		kit.cylinder(Vector3(x, 0.3, 0), 0.08, 0.09, 0.6, Palette.EARTH.darkened(0.2), Vector3.ZERO, 8)
		kit.box(Vector3(x, 0.05, -0.05), Vector3(0.15, 0.1, 0.26), Palette.WOOD_DARK)
	# Gövde (tunik)
	kit.cylinder(Vector3(0, 0.88, 0), 0.22, 0.32, 0.72, Palette.TUNIC, Vector3.ZERO, 12)
	kit.cylinder(Vector3(0, 0.62, 0), 0.33, 0.33, 0.08, Palette.WOOD_DARK, Vector3.ZERO, 12)  # kemer
	# Kollar
	for s: float in [-1.0, 1.0]:
		kit.cylinder(Vector3(s * 0.3, 0.9, 0), 0.07, 0.08, 0.55, Palette.TUNIC.lightened(0.1), Vector3(0, 0, s * 0.18), 8)
		kit.sphere(Vector3(s * 0.35, 0.62, 0), 0.075, Palette.SKIN, Vector3.ONE, 8)
	# Atkı
	kit.cylinder(Vector3(0, 1.25, 0), 0.2, 0.24, 0.12, Palette.SCARF, Vector3.ZERO, 12)
	kit.box(Vector3(0.12, 1.08, 0.2), Vector3(0.1, 0.3, 0.05), Palette.SCARF, Vector3(0.2, 0, 0.1))
	# Baş
	kit.sphere(Vector3(0, 1.48, 0), 0.2, Palette.SKIN, Vector3(1, 1.05, 1), 12)
	kit.sphere(Vector3(0, 1.44, -0.19), 0.04, Palette.SKIN.darkened(0.08), Vector3.ONE, 6)  # burun
	# Hasır şapka
	kit.cylinder(Vector3(0, 1.62, 0), 0.4, 0.42, 0.03, Palette.REED, Vector3.ZERO, 16)
	kit.cylinder(Vector3(0, 1.72, 0), 0.14, 0.2, 0.18, Palette.REED.darkened(0.05), Vector3.ZERO, 12)
	kit.cylinder(Vector3(0, 1.66, 0), 0.205, 0.205, 0.05, Palette.SUNSET, Vector3.ZERO, 12)
	# Sırt çantası
	kit.box(Vector3(0, 0.95, 0.28), Vector3(0.32, 0.38, 0.14), Palette.WOOD)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	mi.material_override = WatercolorMaterials.vertex_colored(true)
	add_child(mi)
