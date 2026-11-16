class_name ValleyEnemy
extends Interactable
## Vadinin onarılan yapılarına dadanan canlılar. Hepsi suluboya, kan yok: vurulunca
## boya damlalarına, yapraklara ya da su sıçramasına dağılır.
##   SMALL  Mürekkep lekesi: hızlı, zayıf, bir parçayı eritir.
##   BIG    Kara Leke: yavaş, dayanıklı, yakındaki oyuncuya da saldırır.
##   RODENT Kemirgen: çok hızlı, sürü halinde; ahşap parçaları (meşe, çam, kamış, dal)
##          kemirir, taş/demiri zor. Vurulunca kaçar, sonra geri döner.
##   SPIRIT Orman ruhu: süzülen yosunlu ruh; uzaktan sarmaşık salıp yapının bütün
##          parçalarını yavaşça sarar. Vurulunca kısa bir mesafeye ışınlanır.
##   FLOOD  Sel suyu: kuzeydeki şelaleden dere boyunca akan dalga; yoluna çıkan köprüyü
##          ve çarkı hızla aşındırır, önündeki oyuncuyu iter. Vurdukça küçülür, vadinin
##          güneyinden çıkıp gider.
## Fizik gövdesi yok: araziyi ValleyShape'ten okur, suyun üstünde yüzer.

signal died(enemy: ValleyEnemy)

enum Kind { SMALL, BIG, RODENT, SPIRIT, FLOOD }
enum State { SEEK, GNAW, CHASE, FLEE, DYING }

## Mavi-siyah mürekkep (morumsu değil; gölgeler gibi nötr kalsın).
const INK := Color(0.10, 0.14, 0.18)
const INK_SHEEN := Color(0.22, 0.34, 0.40)
const FUR := Color(0.55, 0.44, 0.36)
const SPIRIT_MOSS := Color(0.45, 0.78, 0.48)
const SPIRIT_GLOW := Color(1.0, 0.88, 0.45)
const FLOOD_WATER := Color(0.30, 0.58, 0.82)
const FLOOD_FOAM := Color(0.92, 0.96, 0.98)
const WOOD_MATS := ["oak", "pine", "reed", "branch"]
## tür -> [can, hız m/sn, yapıya hasar /sn, boy, oyuncuya hasar]
const STATS := {
	Kind.SMALL: [4.0, 1.75, 2.2, 0.36, 0],
	Kind.BIG: [12.0, 1.05, 4.5, 0.66, 1],
	Kind.RODENT: [2.0, 2.7, 3.2, 0.26, 0],
	Kind.SPIRIT: [7.0, 1.2, 1.1, 0.42, 0],
	Kind.FLOOD: [14.0, 2.0, 7.0, 0.95, 1],
}
const NAMES := {
	Kind.SMALL: "NAME_INK_BLOT", Kind.BIG: "NAME_INK_BIG", Kind.RODENT: "NAME_RODENT",
	Kind.SPIRIT: "NAME_FOREST_SPIRIT", Kind.FLOOD: "NAME_FLOOD",
}
## Hint kartı ikonu ve vuruş parçacığı.
const ICONS := {Kind.SMALL: "ink_blot", Kind.BIG: "ink_blot", Kind.RODENT: "rodent", Kind.SPIRIT: "spirit", Kind.FLOOD: "flood"}
const FX := {Kind.SMALL: "ink", Kind.BIG: "ink", Kind.RODENT: "dust", Kind.SPIRIT: "leaf", Kind.FLOOD: "splash"}
const GNAW_REACH := 1.3
const SPIRIT_REACH := 3.2
const FLOOD_REACH := 3.4
const CHASE_RANGE := 6.0
const CHASE_GIVE_UP := 10.0
const BITE_RANGE := 1.35
const BITE_EVERY := 1.4

var kind := Kind.SMALL
var hp := 4.0
var max_hp := 4.0
var speed := 1.75
var bite := 2.2
var size := 0.36
var player_damage := 0
var state := State.SEEK
var director: Node
var site: RepairSite
var slot_id := ""
var goal := Vector3.ZERO
var chase: Player = null
var _knock := Vector3.ZERO
var _t := 0.0
var _bite_cd := 0.0
var _flee_t := 0.0
var _hurt := 0.0
var _drip_t := 0.0
var _phase := 0.0
var _pivot: Node3D
var _body: MeshInstance3D
var _eyes: Node3D
var _tail: Node3D
var _push_cd := {}


func setup(k: int, dir: Node) -> ValleyEnemy:
	kind = k
	director = dir
	var st: Array = STATS[k]
	max_hp = st[0]
	hp = max_hp
	speed = st[1] * randf_range(0.9, 1.1)
	bite = st[2]
	size = st[3]
	player_damage = st[4]
	return self


func _ready() -> void:
	super._ready()
	display_name_key = NAMES[kind]
	action_key = "ACTION_HIT"
	radius = 3.0 if kind in [Kind.BIG, Kind.FLOOD, Kind.SPIRIT] else 2.6
	focus_bias = -2.5   # yakındaki düşmanlar kaynak ve yapılardan önce hedeflenir
	_phase = randf() * TAU
	_build()


func alive() -> bool:
	return state != State.DYING


func can_focus() -> bool:
	return visible and alive()


func hint_text() -> String:
	return "%s: %s" % [tr(action_key), tr(display_name_key)]


func icon() -> String:
	return ICONS[kind]


func fx_kind() -> String:
	return FX[kind]


## Odak ışığı (FocusHighlight) için gövde.
func highlight_parts() -> Array:
	return [[_body.mesh, _body.global_transform]]


## Parça malzemesine göre aşındırma çarpanı (kemirgen ahşabı sever, sel her şeyi döver).
static func damage_factor(k: int, part_key: String) -> float:
	var mat := Crafting.part_material(part_key)
	var wood := mat in WOOD_MATS
	match k:
		Kind.RODENT:
			return 1.0 if wood else 0.2
		Kind.SPIRIT:
			return 1.0 if wood else 0.6
		Kind.FLOOD:
			return 1.0 if wood else 0.7
	return 1.0


# --- Görünüm -----------------------------------------------------------------------------
func _build() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_eyes = Node3D.new()
	_pivot.add_child(_eyes)
	var body_kit := MeshKit.new()
	var eye_kit := MeshKit.new()
	match kind:
		Kind.RODENT:
			_build_rodent(body_kit, eye_kit)
		Kind.SPIRIT:
			_build_spirit(body_kit, eye_kit)
		Kind.FLOOD:
			_build_flood(body_kit, eye_kit)
		_:
			_build_blot(body_kit, eye_kit)
	_body = MeshInstance3D.new()
	_body.mesh = body_kit.commit()
	_body.material_override = WatercolorMaterials.vertex_colored(true)
	_pivot.add_child(_body)
	if not eye_kit.is_empty():
		var eyes := MeshInstance3D.new()
		eyes.mesh = eye_kit.commit()
		eyes.material_override = WatercolorMaterials.vertex_colored(false)
		_eyes.add_child(eyes)


func _build_blot(kit: MeshKit, ek: MeshKit) -> void:
	var r := size
	kit.sphere(Vector3(0, r * 0.7, 0), r, INK, Vector3(1.0, 0.78, 1.0), 14)
	# Yanlardan sarkan damlalar ve tepede parlak bir boya yansıması.
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		kit.sphere(Vector3(cos(a) * r * 0.85, r * 0.25, sin(a) * r * 0.85), r * 0.32, INK, Vector3(1.0, 0.7, 1.0), 8)
	kit.sphere(Vector3(-r * 0.25, r * 1.18, r * 0.1), r * 0.22, INK_SHEEN, Vector3(1.4, 0.4, 1.0), 8)
	if kind == Kind.BIG:
		# Kara Leke: tepede iki sivri damla (boynuz gibi).
		for sx: float in [-1.0, 1.0]:
			kit.cylinder(Vector3(sx * r * 0.42, r * 1.25, 0), 0.0, r * 0.2, r * 0.55, INK, Vector3(0, 0, -sx * 0.35), 8)
	var ey := r * (0.95 if kind == Kind.SMALL else 0.85)
	for sx: float in [-1.0, 1.0]:
		ek.sphere(Vector3(sx * r * 0.32, ey, -r * 0.78), r * 0.2, Palette.PAPER, Vector3.ONE, 10)
		ek.sphere(Vector3(sx * r * 0.3, ey - r * 0.02, -r * 0.94), r * 0.09, Color(0.05, 0.05, 0.06), Vector3.ONE, 8)
	if kind == Kind.BIG:
		# Çatık kaşlar: kızgın görünsün.
		for sx: float in [-1.0, 1.0]:
			ek.box(Vector3(sx * r * 0.32, ey + r * 0.24, -r * 0.82), Vector3(r * 0.34, r * 0.07, r * 0.06), Palette.SUNSET.darkened(0.1), Vector3(0, 0, sx * 0.4))


## Kemirgen: tombul gövde, büyük kulaklar, öne çıkık dişler, uzun kuyruk. Yüz -Z.
func _build_rodent(kit: MeshKit, ek: MeshKit) -> void:
	var r := size
	kit.sphere(Vector3(0, r * 0.75, r * 0.15), r, FUR, Vector3(0.9, 0.8, 1.25), 12)
	kit.sphere(Vector3(0, r * 0.62, r * 0.35), r * 0.75, FUR.lightened(0.25), Vector3(0.8, 0.6, 1.0), 10)  # açık karın
	kit.sphere(Vector3(0, r * 0.95, -r * 0.85), r * 0.6, FUR, Vector3(1.0, 0.9, 1.1), 10)  # kafa
	kit.sphere(Vector3(0, r * 0.85, -r * 1.4), r * 0.16, Color(0.85, 0.48, 0.48), Vector3.ONE, 8)  # burun
	for sx: float in [-1.0, 1.0]:
		kit.sphere(Vector3(sx * r * 0.42, r * 1.45, -r * 0.75), r * 0.32, FUR.darkened(0.08), Vector3(1.0, 1.0, 0.35), 10)
		kit.sphere(Vector3(sx * r * 0.42, r * 1.45, -r * 0.82), r * 0.2, Color(0.92, 0.62, 0.60), Vector3(1.0, 1.0, 0.3), 8)
		kit.box(Vector3(sx * r * 0.45, r * 0.12, -r * 0.3), Vector3(r * 0.22, r * 0.2, r * 0.35), FUR.darkened(0.2))  # ayak
	kit.box(Vector3(0, r * 0.62, -r * 1.33), Vector3(r * 0.22, r * 0.2, r * 0.06), Palette.PAPER)  # dişler
	for sx: float in [-1.0, 1.0]:
		ek.sphere(Vector3(sx * r * 0.27, r * 1.1, -r * 1.3), r * 0.11, Color(0.06, 0.05, 0.05), Vector3.ONE, 8)
	_tail = Node3D.new()
	_tail.position = Vector3(0, r * 0.5, r * 1.3)
	_pivot.add_child(_tail)
	var tk := MeshKit.new()
	tk.cylinder(Vector3(0, 0, r * 0.7), r * 0.04, r * 0.1, r * 1.5, Color(0.86, 0.6, 0.56), Vector3(PI * 0.5 - 0.3, 0, 0), 6)
	var tail := MeshInstance3D.new()
	tail.mesh = tk.commit()
	tail.material_override = WatercolorMaterials.vertex_colored(false)
	_tail.add_child(tail)


## Orman ruhu: yosundan damla gövde, yaprak taç, sıcak ışıklı gözler, havada süzülür.
func _build_spirit(kit: MeshKit, ek: MeshKit) -> void:
	var r := size
	kit.sphere(Vector3(0, r * 0.9, 0), r, SPIRIT_MOSS, Vector3(1.0, 1.15, 1.0), 14)
	kit.cylinder(Vector3(0, r * 0.05, 0), r * 0.55, 0.0, r * 0.7, SPIRIT_MOSS.darkened(0.12), Vector3.ZERO, 10)  # kuyruk ucu
	for i in 6:
		var a := TAU * i / 6.0
		var leaf := Palette.MOSS_LIGHT if i % 2 == 0 else Palette.PINE.lightened(0.15)
		kit.prism(Vector3(cos(a) * r * 0.5, r * 2.05, sin(a) * r * 0.5), Vector3(r * 0.5, r * 0.95, r * 0.14), leaf, Vector3(cos(a) * 0.5, -a, sin(a) * 0.5))
	for sx: float in [-1.0, 1.0]:
		kit.sphere(Vector3(sx * r * 0.95, r * 0.85, 0), r * 0.28, SPIRIT_MOSS.lightened(0.15), Vector3(0.6, 1.4, 0.6), 8)  # kollar
	kit.sphere(Vector3(r * 0.3, r * 1.45, r * 0.4), r * 0.14, Palette.SUNSET_LIGHT, Vector3.ONE, 6)  # küçük çiçek
	for sx: float in [-1.0, 1.0]:
		ek.sphere(Vector3(sx * r * 0.33, r * 1.05, -r * 0.88), r * 0.17, SPIRIT_GLOW, Vector3(1.0, 1.3, 0.5), 10)


## Sel suyu: dereyi kaplayan köpüklü dalga; önde kızgın gözler, tepede köpük.
func _build_flood(kit: MeshKit, ek: MeshKit) -> void:
	var r := size
	kit.sphere(Vector3(0, r * 0.4, 0), r * 1.3, FLOOD_WATER, Vector3(1.6, 0.6, 1.0), 14)
	kit.sphere(Vector3(0, r * 0.7, -r * 0.3), r, FLOOD_WATER.lightened(0.12), Vector3(1.5, 0.8, 0.9), 12)
	for i in 7:
		var x := (i - 3) * r * 0.45
		kit.sphere(Vector3(x, r * 1.25 - absf(i - 3) * r * 0.08, -r * 0.55), r * 0.32, FLOOD_FOAM, Vector3(1.0, 0.6, 1.0), 8)
	for sx: float in [-1.0, 1.0]:
		ek.sphere(Vector3(sx * r * 0.4, r * 0.85, -r * 1.0), r * 0.16, Palette.PAPER, Vector3.ONE, 10)
		ek.sphere(Vector3(sx * r * 0.38, r * 0.83, -r * 1.12), r * 0.08, Color(0.05, 0.1, 0.18), Vector3.ONE, 8)
		ek.box(Vector3(sx * r * 0.4, r * 1.06, -r * 1.02), Vector3(r * 0.3, r * 0.06, r * 0.05), Color(0.12, 0.3, 0.5), Vector3(0, 0, sx * 0.35))


# --- Davranış ----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_t += delta
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	_hurt = maxf(_hurt - delta * 4.0, 0.0)
	if state == State.DYING:
		return
	if kind == Kind.FLOOD:
		_flood_step(delta)
		return
	var move := Vector3.ZERO
	match state:
		State.SEEK:
			if not _site_valid() and not director.retarget(self):
				_hunt_player()
			elif _big_should_chase():
				pass
			else:
				var to := goal - global_position
				to.y = 0.0
				var reach := SPIRIT_REACH if kind == Kind.SPIRIT else GNAW_REACH
				if to.length() < reach:
					state = State.GNAW
				else:
					move = to.normalized() * speed
		State.GNAW:
			if not _site_valid():
				if not director.retarget(self):
					_hunt_player()
			elif not _big_should_chase():
				_gnaw(delta)
				_face(goal if kind != Kind.SPIRIT else site.global_position)
		State.CHASE:
			if chase == null or not is_instance_valid(chase) or chase.downed \
					or chase.global_position.distance_to(global_position) > CHASE_GIVE_UP:
				chase = null
				state = State.SEEK
			else:
				var to := chase.global_position - global_position
				to.y = 0.0
				if to.length() > BITE_RANGE * 0.8:
					move = to.normalized() * speed * 1.15
				if to.length() < BITE_RANGE and _bite_cd <= 0.0:
					_bite_cd = BITE_EVERY
					_lunge()
					chase.take_damage(maxi(player_damage, 1), global_position)
		State.FLEE:
			_flee_t -= delta
			if kind == Kind.RODENT and chase != null and is_instance_valid(chase):
				var away := global_position - chase.global_position
				away.y = 0.0
				move = away.normalized() * speed * 1.3
			if _flee_t <= 0.0:
				chase = null
				state = State.SEEK
	move += _knock
	_knock = _knock.move_toward(Vector3.ZERO, delta * 12.0)
	move += director.separation(self) * 1.6
	var p := global_position + move * delta
	p.x = clampf(p.x, -ValleyShape.HALF_SIZE + 1.0, ValleyShape.HALF_SIZE - 1.0)
	p.z = clampf(p.z, -ValleyShape.HALF_SIZE + 1.0, ValleyShape.HALF_SIZE - 1.0)
	p.y = _ground_y(p.x, p.z)
	global_position = p
	if move.length() > 0.2 and state != State.GNAW:
		_face(global_position + move)
	_animate(delta, move.length())


## Yapıyı aşındır: ruh bütün parçaları sarar, diğerleri seçtiği parçayı kemirir.
func _gnaw(delta: float) -> void:
	var ids: Array = site.damageable_slots() if kind == Kind.SPIRIT else [slot_id]
	for id: String in ids:
		var key := str(Repair.slot_state(site.state, id).get("part", ""))
		if site.damage_slot(id, bite * delta * damage_factor(kind, key)):
			director.on_part_broken(self, site, id)
			if id == slot_id:
				director.retarget(self)
				return
	_drip_t -= delta
	if _drip_t <= 0.0:
		_drip_t = 0.7
		var at := global_position + Vector3(0, size * 0.6, 0)
		if kind == Kind.SPIRIT:
			at = site.attack_points()[0] + Vector3(0, 0.6, 0)
		director.drip(at, fx_kind())


## Sel: dere boyunca güneye akar; yolundaki yapıları ve oyuncuları döver.
func _flood_step(delta: float) -> void:
	var p := global_position
	p.z += speed * delta
	p.x = lerpf(p.x, ValleyShape.river_x(p.z), clampf(delta * 3.0, 0.0, 1.0))
	p.y = ValleyShape.water_y(p.z) - 0.1
	global_position = p
	rotation.y = PI  # yüz akış yönünde (+Z)
	for s: RepairSite in director.sites:
		for ap: Vector3 in [s.global_position] + s.attack_points():
			if Vector2(ap.x - p.x, ap.z - p.z).length() < FLOOD_REACH:
				var hit := false
				for id: String in s.damageable_slots():
					var key := str(Repair.slot_state(s.state, id).get("part", ""))
					if s.damage_slot(id, bite * delta * damage_factor(kind, key)):
						director.on_part_broken(self, s, id)
					hit = true
				if hit:
					_drip_t -= delta
					if _drip_t <= 0.0:
						_drip_t = 0.5
						director.drip(ap + Vector3(0, 0.5, 0), "splash")
				break
	for pl: Player in director.players():
		var d := Vector2(pl.global_position.x - p.x, pl.global_position.z - p.z).length()
		var cd := float(_push_cd.get(pl, 0.0)) - delta
		_push_cd[pl] = cd
		if d < size * 1.6 + 0.5 and cd <= 0.0:
			_push_cd[pl] = 1.5
			pl.take_damage(1, p - Vector3(0, 0, 1.0))
	if p.z > ValleyShape.HALF_SIZE - 1.5:
		director.on_left(self)
		queue_free()
	_animate(delta, speed)


func _site_valid() -> bool:
	if site == null or not is_instance_valid(site):
		return false
	if kind == Kind.SPIRIT:
		return not site.damageable_slots().is_empty()
	return Repair.is_filled(site.state, slot_id)


## Kara Leke yakındaki oyuncuya döner.
func _big_should_chase() -> bool:
	if player_damage <= 0:
		return false
	var p := director.nearest_player(global_position, CHASE_RANGE) as Player
	if p == null:
		return false
	chase = p
	state = State.CHASE
	return true


## Saldıracak yapı kalmadıysa oyunculara yönel.
func _hunt_player() -> void:
	var p := director.nearest_player(global_position, 999.0) as Player
	if p != null:
		chase = p
		state = State.CHASE
		if player_damage <= 0:
			player_damage = 1


func _ground_y(x: float, z: float) -> float:
	var y := maxf(ValleyShape.height(x, z), ValleyShape.water_y(z) - 0.05)
	if kind == Kind.SPIRIT:
		y += 0.9 + sin(_t * 1.7 + _phase) * 0.18   # süzülür
	return y


func _face(at: Vector3) -> void:
	var to := at - global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 0.2)


func _animate(delta: float, spd: float) -> void:
	_phase += delta * (4.0 + spd * 3.0)
	var hurt := _hurt * 0.35
	match kind:
		Kind.RODENT:
			# Seke seke koşar; kemirirken kafa hızla iner kalkar.
			var hop := absf(sin(_phase * 1.6)) * 0.12 * clampf(spd, 0.0, 1.0)
			_pivot.position.y = hop
			_pivot.rotation.x = (sin(_t * 22.0) * 0.12 if state == State.GNAW else 0.0)
			_pivot.scale = Vector3.ONE * (1.0 + hurt)
			if _tail != null:
				_tail.rotation.y = sin(_t * 6.0) * 0.5
		Kind.SPIRIT:
			_pivot.rotation.y = sin(_t * 0.9) * 0.3
			var s := 1.0 + sin(_t * 2.3) * 0.05 + hurt
			_pivot.scale = Vector3(s, s, s)
			_pivot.rotation.z = (sin(_t * 5.0) * 0.08 if state == State.GNAW else 0.0)
		Kind.FLOOD:
			var shrink := 0.55 + 0.45 * clampf(hp / max_hp, 0.0, 1.0)
			var w := sin(_phase) * 0.06
			_pivot.scale = Vector3(shrink * (1.0 + w), shrink * (1.0 - w + hurt), shrink)
		_:
			var wob := sin(_phase) * 0.08
			var gnaw := absf(sin(_t * 9.0)) * 0.18 if state == State.GNAW else 0.0
			_pivot.scale = Vector3(1.0 + wob + hurt, 1.0 - wob - gnaw - hurt * 0.6, 1.0 + wob + hurt)
			_pivot.rotation.x = -gnaw * 0.8
	_eyes.scale = Vector3.ONE * (1.0 + _hurt * 0.4)


func _lunge() -> void:
	var t := create_tween()
	t.tween_property(_pivot, "position:z", -size * 0.8, 0.08)
	t.tween_property(_pivot, "position:z", 0.0, 0.2)


## Oyuncunun vuruşu: geri savrulur, parçacık saçar. Türüne göre tepki verir.
func take_hit(amount: float, by: Node3D) -> void:
	if not alive():
		return
	hp -= amount
	_hurt = 1.0
	var away := global_position - by.global_position
	away.y = 0.0
	var push: float = {Kind.SMALL: 6.5, Kind.BIG: 3.0, Kind.RODENT: 7.5, Kind.SPIRIT: 0.0, Kind.FLOOD: 0.0}[kind]
	_knock = away.normalized() * push if away.length() > 0.01 else Vector3.ZERO
	director.on_hit(self)
	if hp <= 0.0:
		_die()
		return
	match kind:
		Kind.SPIRIT:
			_blink(by)
		Kind.RODENT:
			chase = by as Player
			state = State.FLEE
			_flee_t = 2.2
		Kind.FLOOD:
			pass   # sel durmaz, yalnızca küçülür
		_:
			if player_damage > 0 and by is Player:
				chase = by
				state = State.CHASE
			else:
				state = State.FLEE
				_flee_t = 0.5


## Orman ruhu vurulunca yapraklar arasında birkaç metre ötede belirir.
func _blink(by: Node3D) -> void:
	director.fx.burst("leaf", global_position + Vector3(0, size, 0), Vector3.UP, 1.4)
	var center := goal if site != null else global_position
	var away := center - by.global_position
	away.y = 0.0
	var dir := away.normalized() if away.length() > 0.1 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	dir = dir.rotated(Vector3.UP, randf_range(-0.9, 0.9))
	var p := center + dir * 3.0
	p.y = _ground_y(p.x, p.z)
	global_position = p
	director.fx.burst("leaf", p + Vector3(0, size, 0), Vector3.UP, 1.4)
	state = State.SEEK


func _die() -> void:
	state = State.DYING
	remove_from_group(GROUP)
	director.on_died(self)
	died.emit(self)
	var t := create_tween()
	t.tween_property(_pivot, "scale", Vector3(1.6, 0.15, 1.6), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_pivot, "scale", Vector3.ZERO, 0.25)
	t.tween_callback(queue_free)
