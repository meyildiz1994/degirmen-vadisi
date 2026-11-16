class_name InkBlot
extends Interactable
## Mürekkep lekesi: ormanın kenarından sızan canlı bir mürekkep damlası. Onarılmış
## yapılara sürünür ve takılı parçaları eritir. Oyuncu elindeki aletle vurarak dağıtır;
## leke boya damlalarına ayrılıp kaybolur. İki tür: küçük (hızlı, zayıf, yalnızca
## yapılara saldırır) ve iri Kara Leke (yavaş, dayanıklı, yakındaki oyuncuya da saldırır).
## Fizik gövdesi yok: araziyi ValleyShape'ten okur, suyun üstünde yüzer.

signal died(blot: InkBlot)

enum Kind { SMALL, BIG }
enum State { SEEK, GNAW, CHASE, FLEE, DYING }

## Mavi-siyah mürekkep (morumsu değil; gölgeler gibi nötr kalsın).
const INK := Color(0.10, 0.14, 0.18)
const INK_SHEEN := Color(0.22, 0.34, 0.40)
## tür -> [can, hız m/sn, yapıya hasar /sn, boy, oyuncuya hasar]
const STATS := {
	Kind.SMALL: [4.0, 1.75, 2.2, 0.36, 0],
	Kind.BIG: [12.0, 1.05, 4.5, 0.66, 1],
}
const GNAW_REACH := 1.3
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


func setup(k: int, dir: Node) -> InkBlot:
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
	display_name_key = "NAME_INK_BIG" if kind == Kind.BIG else "NAME_INK_BLOT"
	action_key = "ACTION_HIT"
	radius = 2.6 if kind == Kind.SMALL else 3.0
	focus_bias = -2.5   # yakındaki lekeler kaynak ve yapılardan önce hedeflenir
	_phase = randf() * TAU
	_build()


func alive() -> bool:
	return state != State.DYING


func can_focus() -> bool:
	return visible and alive()


func hint_text() -> String:
	return "%s: %s" % [tr(action_key), tr(display_name_key)]


# --- Görünüm -----------------------------------------------------------------------------
func _build() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	var kit := MeshKit.new()
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
	_body = MeshInstance3D.new()
	_body.mesh = kit.commit()
	_body.material_override = WatercolorMaterials.vertex_colored(true)
	_pivot.add_child(_body)
	_eyes = Node3D.new()
	_pivot.add_child(_eyes)
	var ek := MeshKit.new()
	var ey := r * (0.95 if kind == Kind.SMALL else 0.85)
	for sx: float in [-1.0, 1.0]:
		ek.sphere(Vector3(sx * r * 0.32, ey, -r * 0.78), r * 0.2, Palette.PAPER, Vector3.ONE, 10)
		ek.sphere(Vector3(sx * r * 0.3, ey - r * 0.02, -r * 0.94), r * 0.09, Color(0.05, 0.05, 0.06), Vector3.ONE, 8)
	if kind == Kind.BIG:
		# Çatık kaşlar: kızgın görünsün.
		for sx: float in [-1.0, 1.0]:
			ek.box(Vector3(sx * r * 0.32, ey + r * 0.24, -r * 0.82), Vector3(r * 0.34, r * 0.07, r * 0.06), Palette.SUNSET.darkened(0.1), Vector3(0, 0, sx * 0.4))
	var eyes := MeshInstance3D.new()
	eyes.mesh = ek.commit()
	eyes.material_override = WatercolorMaterials.vertex_colored(false)
	_eyes.add_child(eyes)


## Odak ışığı (FocusHighlight) için gövde.
func highlight_parts() -> Array:
	return [[_body.mesh, _body.global_transform]]


# --- Davranış ----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_t += delta
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	_hurt = maxf(_hurt - delta * 4.0, 0.0)
	var move := Vector3.ZERO
	match state:
		State.DYING:
			return
		State.SEEK:
			if not _site_valid() and not director.retarget(self):
				_hunt_player()
			elif _big_should_chase():
				pass
			else:
				var to := goal - global_position
				to.y = 0.0
				if to.length() < GNAW_REACH:
					state = State.GNAW
				else:
					move = to.normalized() * speed
		State.GNAW:
			if not _site_valid():
				if not director.retarget(self):
					_hunt_player()
			elif not _big_should_chase():
				if site.damage_slot(slot_id, bite * delta):
					director.on_part_broken(self, site, slot_id)
					director.retarget(self)
				_drip_t -= delta
				if _drip_t <= 0.0:
					_drip_t = 0.7
					director.drip(global_position + Vector3(0, size * 0.6, 0))
				_face(goal)
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
			if _flee_t <= 0.0:
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


func _site_valid() -> bool:
	return site != null and is_instance_valid(site) and Repair.is_filled(site.state, slot_id)


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
	return maxf(ValleyShape.height(x, z), ValleyShape.water_y(z) - 0.05)


func _face(at: Vector3) -> void:
	var to := at - global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 0.2)


func _animate(delta: float, spd: float) -> void:
	_phase += delta * (4.0 + spd * 3.0)
	var wob := sin(_phase) * 0.08
	var gnaw := 0.0
	if state == State.GNAW:
		gnaw = absf(sin(_t * 9.0)) * 0.18
	var hurt := _hurt * 0.35
	_pivot.scale = Vector3(1.0 + wob + hurt, 1.0 - wob - gnaw - hurt * 0.6, 1.0 + wob + hurt)
	_pivot.rotation.x = -gnaw * 0.8
	_eyes.scale = Vector3.ONE * (1.0 + _hurt * 0.4)


func _lunge() -> void:
	var t := create_tween()
	t.tween_property(_pivot, "position:z", -size * 0.8, 0.08)
	t.tween_property(_pivot, "position:z", 0.0, 0.2)


## Oyuncunun vuruşu: geri savrulur, boya damlası saçar. Kara Leke vurana döner.
func take_hit(amount: float, by: Node3D) -> void:
	if not alive():
		return
	hp -= amount
	_hurt = 1.0
	var away := global_position - by.global_position
	away.y = 0.0
	var push := 6.5 if kind == Kind.SMALL else 3.0
	_knock = away.normalized() * push if away.length() > 0.01 else Vector3.ZERO
	director.on_hit(self)
	if hp <= 0.0:
		_die()
		return
	if player_damage > 0 and by is Player:
		chase = by
		state = State.CHASE
	else:
		state = State.FLEE
		_flee_t = 0.5


func _die() -> void:
	state = State.DYING
	remove_from_group(GROUP)
	director.on_died(self)
	died.emit(self)
	var t := create_tween()
	t.tween_property(_pivot, "scale", Vector3(1.6, 0.15, 1.6), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_pivot, "scale", Vector3.ZERO, 0.25)
	t.tween_callback(queue_free)
