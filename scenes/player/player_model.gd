extends Node3D
## Oyuncu modeli: primitive'lerden tek mesh (tunik, atkı, hasır şapka).
## Sağ kol ayrı bir eklem: alet tutar ve vuruşta sallanır. Yüz yönü -Z.

const ARM_IDLE := 0.12
const ARM_STRIKE := 1.2
const ARM_RAISED := 3.35

var arm_pivot: Node3D
var _tools := {}              ## "axe" / "pickaxe" -> MeshInstance3D
var _arm_target := ARM_IDLE
var _pickup_t := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _body_mesh()
	mi.material_override = WatercolorMaterials.vertex_colored(true)
	add_child(mi)
	arm_pivot = Node3D.new()
	arm_pivot.name = "RightArm"
	arm_pivot.position = Vector3(0.31, 1.16, 0)
	add_child(arm_pivot)
	var arm := MeshInstance3D.new()
	arm.mesh = _arm_mesh()
	arm.material_override = WatercolorMaterials.vertex_colored(true)
	arm_pivot.add_child(arm)
	for kind: String in ["axe", "pickaxe"]:
		var t := MeshInstance3D.new()
		t.name = kind.capitalize()
		t.mesh = _tool_mesh(kind)
		t.material_override = WatercolorMaterials.vertex_colored(true)
		t.position = Vector3(0.02, -0.55, 0)
		t.visible = false
		arm_pivot.add_child(t)
		_tools[kind] = t


func _body_mesh() -> ArrayMesh:
	var kit := MeshKit.new()
	for x: float in [-0.12, 0.12]:
		kit.cylinder(Vector3(x, 0.3, 0), 0.08, 0.09, 0.6, Palette.EARTH.darkened(0.2), Vector3.ZERO, 8)
		kit.box(Vector3(x, 0.05, -0.05), Vector3(0.15, 0.1, 0.26), Palette.WOOD_DARK)
	kit.cylinder(Vector3(0, 0.88, 0), 0.22, 0.32, 0.72, Palette.TUNIC, Vector3.ZERO, 12)
	kit.cylinder(Vector3(0, 0.62, 0), 0.33, 0.33, 0.08, Palette.WOOD_DARK, Vector3.ZERO, 12)  # kemer
	# Sol kol (sağ kol ayrı eklemde)
	kit.cylinder(Vector3(-0.3, 0.9, 0), 0.07, 0.08, 0.55, Palette.TUNIC.lightened(0.1), Vector3(0, 0, -0.18), 8)
	kit.sphere(Vector3(-0.35, 0.62, 0), 0.075, Palette.SKIN, Vector3.ONE, 8)
	kit.cylinder(Vector3(0, 1.25, 0), 0.2, 0.24, 0.12, Palette.SCARF, Vector3.ZERO, 12)
	kit.box(Vector3(0.12, 1.08, 0.2), Vector3(0.1, 0.3, 0.05), Palette.SCARF, Vector3(0.2, 0, 0.1))
	kit.sphere(Vector3(0, 1.48, 0), 0.2, Palette.SKIN, Vector3(1, 1.05, 1), 12)
	kit.sphere(Vector3(0, 1.44, -0.19), 0.04, Palette.SKIN.darkened(0.08), Vector3.ONE, 6)  # burun
	kit.cylinder(Vector3(0, 1.62, 0), 0.4, 0.42, 0.03, Palette.REED, Vector3.ZERO, 16)
	kit.cylinder(Vector3(0, 1.72, 0), 0.14, 0.2, 0.18, Palette.REED.darkened(0.05), Vector3.ZERO, 12)
	kit.cylinder(Vector3(0, 1.66, 0), 0.205, 0.205, 0.05, Palette.SUNSET, Vector3.ZERO, 12)
	kit.box(Vector3(0, 0.95, 0.28), Vector3(0.32, 0.38, 0.14), Palette.WOOD)  # sırt çantası
	return kit.commit()


func _arm_mesh() -> ArrayMesh:
	var kit := MeshKit.new()
	kit.cylinder(Vector3(0, -0.26, 0), 0.07, 0.08, 0.55, Palette.TUNIC.lightened(0.1), Vector3.ZERO, 8)
	kit.sphere(Vector3(0, -0.54, 0), 0.075, Palette.SKIN, Vector3.ONE, 8)
	return kit.commit()


## Sap elden ileri (+Z yerel) uzanır; vuruş anında aşağıyı gösterir.
func _tool_mesh(kind: String) -> ArrayMesh:
	var kit := MeshKit.new()
	kit.cylinder(Vector3(0, 0, 0.3), 0.025, 0.03, 0.72, Palette.WOOD, Vector3(PI * 0.5, 0, 0), 6)
	if kind == "axe":
		kit.box(Vector3(0, -0.07, 0.6), Vector3(0.07, 0.2, 0.12), Palette.STONE)
		kit.prism(Vector3(0, -0.2, 0.6), Vector3(0.06, 0.1, 0.18), Palette.STONE.lightened(0.15), Vector3(PI, 0, 0))
		kit.box(Vector3(0, 0.0, 0.6), Vector3(0.08, 0.06, 0.06), Palette.REED)  # bağ
	else:
		kit.box(Vector3(0, 0, 0.62), Vector3(0.07, 0.07, 0.1), Palette.REED)
		kit.box(Vector3(0, -0.12, 0.62), Vector3(0.06, 0.24, 0.07), Palette.STONE, Vector3(0.25, 0, 0))
		kit.box(Vector3(0, 0.12, 0.62), Vector3(0.06, 0.24, 0.07), Palette.STONE, Vector3(-0.25, 0, 0))
	return kit.commit()


func set_held_tool(kind: String) -> void:
	for k in _tools:
		_tools[k].visible = k == kind
	if kind == "":
		_arm_target = ARM_IDLE


## p: halkanın hedefe yaklaşma oranı (0..1). Alet halkayla birlikte kalkar.
func set_windup(p: float) -> void:
	_arm_target = lerpf(ARM_STRIKE, ARM_RAISED, smoothstep(0.08, 0.95, p))


func strike() -> void:
	_arm_target = ARM_STRIKE
	arm_pivot.rotation.x = lerpf(arm_pivot.rotation.x, ARM_STRIKE, 0.85)


func pickup() -> void:
	_pickup_t = 0.4


func _process(delta: float) -> void:
	var target := _arm_target
	if _pickup_t > 0.0:
		_pickup_t = maxf(_pickup_t - delta, 0.0)
		var k := sin((1.0 - _pickup_t / 0.4) * PI)
		target = lerpf(target, 1.1, k)
		rotation.x = -0.35 * k
	else:
		rotation.x = 0.0
	arm_pivot.rotation.x = lerpf(arm_pivot.rotation.x, target, clampf(delta * 18.0, 0.0, 1.0))
