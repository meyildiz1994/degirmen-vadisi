extends Node3D
## Oyuncu modeli: primitive'lerden mesh (tunik, atkı, hasır şapka). Bacaklar kökte,
## gövde kalçadan eğilen ayrı bir "rig" düğümünde; sağ kol rig içinde ayrı eklem.
## Animasyonlar kod ile: yay-sönüm (spring) ile eğilme/ezilme, zaman çizelgeli vuruş
## (kurulma → çarpma → kısa duraksama → savrulma → toparlanma) ve çömelip alma.
## Yüz yönü -Z. Alet başının rengi malzemesinden gelir (bakır, demir...).

const ARM_IDLE := 0.12
const ARM_CONTACT := 1.25     ## vuruş anı: alet ileri-aşağı
const ARM_FOLLOW := 0.72      ## savrulma: çarpmadan sonra biraz daha aşağı
const ARM_RAISED := 3.35      ## baş üstü, geriye kurulmuş
const HIP_Y := 0.62

const STRIKE_SNAP := 0.045    ## kolun temasa inme süresi
const STRIKE_HOLD := 0.07     ## çarpma duraksaması (hit-stop)
const STRIKE_FOLLOW := 0.12
const STRIKE_TOTAL := 0.42
const PICKUP_TIME := 0.62
## Bilek açısı (aletin kola göre dönüşü). Taşırken ileri-aşağı, çarpmada kolla aynı
## çizgide hedefe, kurulunca başın arkasına.
const WRIST_CARRY := 2.0
const WRIST_CONTACT := 1.45
const WRIST_COCKED := 2.9

var arm_pivot: Node3D
var _rig: Node3D
var _tool_root: Node3D
var _tool_mesh_cache := {}
var _tool_mi: MeshInstance3D
var _held := ""
var _held_head := ""
var _windup := -1.0           ## <0: oturum yok
var _strike_t := -1.0
var _strike_sweet := false
var _strike_from := ARM_RAISED
var _pickup_t := -1.0
# Yay-sönüm durumları: gövde eğilmesi (x), ezilme (y ölçeği), çömelme (y konumu).
var _lean := 0.0
var _lean_v := 0.0
var _squash := 1.0
var _squash_v := 0.0
var _crouch := 0.0
var _crouch_v := 0.0


func _ready() -> void:
	var legs := MeshInstance3D.new()
	legs.mesh = _legs_mesh()
	legs.material_override = WatercolorMaterials.vertex_colored(true)
	add_child(legs)
	_rig = Node3D.new()
	_rig.name = "Rig"
	_rig.position = Vector3(0, HIP_Y, 0)
	add_child(_rig)
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh()
	body.position = Vector3(0, -HIP_Y, 0)
	body.material_override = WatercolorMaterials.vertex_colored(true)
	_rig.add_child(body)
	arm_pivot = Node3D.new()
	arm_pivot.name = "RightArm"
	arm_pivot.position = Vector3(0.31, 1.16 - HIP_Y, 0)
	_rig.add_child(arm_pivot)
	var arm := MeshInstance3D.new()
	arm.mesh = _arm_mesh()
	arm.material_override = WatercolorMaterials.vertex_colored(true)
	arm_pivot.add_child(arm)
	_tool_root = Node3D.new()
	_tool_root.position = Vector3(0.02, -0.55, 0)
	arm_pivot.add_child(_tool_root)
	_tool_mi = MeshInstance3D.new()
	_tool_mi.name = "Tool"
	_tool_mi.material_override = WatercolorMaterials.vertex_colored(true)
	_tool_mi.visible = false
	_tool_root.add_child(_tool_mi)
	arm_pivot.rotation.x = ARM_IDLE
	_tool_root.rotation.x = WRIST_CARRY


func _legs_mesh() -> ArrayMesh:
	var kit := MeshKit.new()
	for x: float in [-0.12, 0.12]:
		kit.cylinder(Vector3(x, 0.3, 0), 0.08, 0.09, 0.6, Palette.EARTH.darkened(0.2), Vector3.ZERO, 8)
		kit.box(Vector3(x, 0.05, -0.05), Vector3(0.15, 0.1, 0.26), Palette.WOOD_DARK)
	return kit.commit()


func _body_mesh() -> ArrayMesh:
	var kit := MeshKit.new()
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


## Sap elden ileri (+Z yerel) uzanır; vuruş anında aşağıyı gösterir. Baş rengi = malzeme.
func _tool_mesh(kind: String, head: String) -> ArrayMesh:
	var key := kind + ":" + head
	if _tool_mesh_cache.has(key):
		return _tool_mesh_cache[key]
	var c := Palette.STONE if head == "stone" or not Materials.is_material(head) else Materials.color(head)
	var kit := MeshKit.new()
	kit.cylinder(Vector3(0, 0, 0.3), 0.025, 0.03, 0.72, Palette.WOOD, Vector3(PI * 0.5, 0, 0), 6)
	if kind == "axe":
		# Ağız sapın +Y tarafında: vuruşta hareket yönüne (hedefe) bakar.
		kit.box(Vector3(0, 0.07, 0.6), Vector3(0.07, 0.2, 0.12), c)
		kit.prism(Vector3(0, 0.2, 0.6), Vector3(0.06, 0.1, 0.18), c.lightened(0.2))
		kit.box(Vector3(0, 0.0, 0.6), Vector3(0.08, 0.06, 0.06), Palette.REED)  # bağ
	else:
		kit.box(Vector3(0, 0, 0.62), Vector3(0.07, 0.07, 0.1), Palette.REED)
		kit.box(Vector3(0, -0.12, 0.62), Vector3(0.06, 0.24, 0.07), c, Vector3(0.25, 0, 0))
		kit.box(Vector3(0, 0.12, 0.62), Vector3(0.06, 0.24, 0.07), c.lightened(0.12), Vector3(-0.25, 0, 0))
	var m := kit.commit()
	_tool_mesh_cache[key] = m
	return m


# --- Dış arayüz --------------------------------------------------------------------------
func set_held_tool(kind: String, head := "stone") -> void:
	if kind == _held and head == _held_head:
		return
	var appeared := _held == "" and kind != ""
	_held = kind
	_held_head = head
	_tool_mi.visible = kind != ""
	if kind != "":
		_tool_mi.mesh = _tool_mesh(kind, head)
	if appeared:
		# Alet ele gelince küçük bir "pop".
		_tool_root.scale = Vector3.ONE * 0.4
		create_tween().tween_property(_tool_root, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func held_tool_kind() -> String:
	return _held


## Oturum dışı: kol rahat, yalnızca alet görünür.
func end_session() -> void:
	_windup = -1.0


## p: halkanın hedefe yaklaşma oranı (0..1). Alet halkayla birlikte kalkar.
func set_windup(p: float) -> void:
	_windup = p


func strike(sweet := false) -> void:
	_strike_from = arm_pivot.rotation.x
	_strike_t = 0.0
	_strike_sweet = sweet
	# Çarpma: gövde öne atılır ve ezilir; yaylar gerisini toparlar.
	_lean_v -= 9.0 if sweet else 7.0
	_squash_v -= 3.2 if sweet else 2.4


func pickup() -> void:
	_pickup_t = 0.0


func is_striking() -> bool:
	return _strike_t >= 0.0


# --- Kare kare --------------------------------------------------------------------------
func _process(delta: float) -> void:
	var lean_goal := 0.0
	var crouch_goal := 0.0
	var arm := ARM_IDLE if _held == "" else 0.35
	var wrist := WRIST_CARRY
	if _windup >= 0.0:
		var w := smoothstep(0.05, 0.95, _windup)
		arm = lerpf(ARM_CONTACT, ARM_RAISED, w)
		wrist = lerpf(WRIST_CONTACT, WRIST_COCKED, w)
		lean_goal = 0.16 * w          # kurulurken geriye yaslanır
		crouch_goal = -0.03 * w
	if _strike_t >= 0.0:
		arm = _strike_arm(delta)
		wrist = WRIST_CONTACT
		lean_goal = -0.22
	if _pickup_t >= 0.0:
		var pk := _pickup_pose(delta)
		arm = lerpf(arm, pk.x, pk.z)
		lean_goal = pk.y
		crouch_goal = -0.22 * pk.z
	# Kol: vuruşta doğrudan, diğer durumlarda yumuşak.
	if _strike_t >= 0.0:
		arm_pivot.rotation.x = arm
		_tool_root.rotation.x = lerpf(_tool_root.rotation.x, wrist, clampf(delta * 40.0, 0.0, 1.0))
	else:
		_tool_root.rotation.x = lerpf(_tool_root.rotation.x, wrist, clampf(delta * 14.0, 0.0, 1.0))
		arm_pivot.rotation.x = lerpf(arm_pivot.rotation.x, arm, clampf(delta * 16.0, 0.0, 1.0))
	_springs(delta, lean_goal, crouch_goal)


## Vuruş zaman çizelgesi; kolun açısını döndürür.
func _strike_arm(delta: float) -> float:
	_strike_t += delta
	var t := _strike_t
	var a: float
	if t < STRIKE_SNAP:
		a = lerpf(_strike_from, ARM_CONTACT, ease(t / STRIKE_SNAP, 0.4))
	elif t < STRIKE_SNAP + STRIKE_HOLD:
		# Duraksama: alet hedefte titrer (darbenin ağırlığı).
		var j := (t - STRIKE_SNAP) / STRIKE_HOLD
		a = ARM_CONTACT + sin(j * PI * 4.0) * 0.06 * (1.0 - j)
	elif t < STRIKE_SNAP + STRIKE_HOLD + STRIKE_FOLLOW:
		var f := (t - STRIKE_SNAP - STRIKE_HOLD) / STRIKE_FOLLOW
		a = lerpf(ARM_CONTACT, ARM_FOLLOW, ease(f, 0.5))
	else:
		# Geri tepme: alet biraz kalkar, sonra kurulmaya devreder.
		var r := clampf((t - STRIKE_SNAP - STRIKE_HOLD - STRIKE_FOLLOW) / (STRIKE_TOTAL - STRIKE_SNAP - STRIKE_HOLD - STRIKE_FOLLOW), 0.0, 1.0)
		var goal := lerpf(ARM_CONTACT, ARM_RAISED, smoothstep(0.05, 0.95, maxf(_windup, 0.0))) if _windup >= 0.0 else 0.35
		a = lerpf(ARM_FOLLOW, goal, ease(r, -1.6))
	if t >= STRIKE_TOTAL:
		_strike_t = -1.0
	return a


## Çömel → uzan → kalk. Döner: (kol, eğilme, ağırlık).
func _pickup_pose(delta: float) -> Vector3:
	_pickup_t += delta
	var u := clampf(_pickup_t / PICKUP_TIME, 0.0, 1.0)
	var down := smoothstep(0.0, 0.35, u) * (1.0 - smoothstep(0.55, 1.0, u))
	# Kalkarken kol kısa bir an havaya (alınan şeyi gösterir gibi).
	var lift := smoothstep(0.5, 0.7, u) * (1.0 - smoothstep(0.75, 1.0, u))
	var arm := lerpf(0.75, 2.1, lift)
	if _pickup_t >= PICKUP_TIME:
		_pickup_t = -1.0
		_squash_v += 2.0   # kalkışta hafif uzama
	return Vector3(arm, -0.62 * down + 0.08 * lift, maxf(down, lift))


## Kritik altı sönümlü yaylar: organik toparlanma ve küçük bir taşma.
func _springs(delta: float, lean_goal: float, crouch_goal: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	_lean_v += ((lean_goal - _lean) * 220.0 - _lean_v * 18.0) * dt
	_lean += _lean_v * dt
	_squash_v += ((1.0 - _squash) * 260.0 - _squash_v * 14.0) * dt
	_squash += _squash_v * dt
	_crouch_v += ((crouch_goal - _crouch) * 240.0 - _crouch_v * 22.0) * dt
	_crouch += _crouch_v * dt
	var s := clampf(_squash, 0.8, 1.2)
	_rig.rotation.x = _lean
	_rig.scale = Vector3(1.0 / sqrt(s), s, 1.0 / sqrt(s))
	_rig.position.y = HIP_Y + _crouch
