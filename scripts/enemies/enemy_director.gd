class_name EnemyDirector
extends Node3D
## Mürekkep lekesi dalgaları. İlk yapı onarılınca uyanır: sakin bir süreden sonra
## uyarı (gök hafifçe kararır, kart çıkar), ardından vadinin bir kenarından lekeler sızar.
## Dalga, tüm lekeler dağıtılınca biter; sakin dönemde aşınan parçalar yavaşça toparlanır.
## Dalgalar sayıca, onarılan yapı sayısıyla ve oyuncu sayısıyla büyür.

signal wave_warning(wave: int, from_dir: Vector3)
signal wave_started(wave: int, count: int)
signal wave_cleared(wave: int)
signal part_broken(site: RepairSite, slot_id: String)
signal site_attacked(site: RepairSite)
## Bir düşman türü oyunda ilk kez göründü (tanıtım kartı için).
signal enemy_introduced(kind: int)
## Bir düşman dağıtıldı (çevrimiçi: katılan tarafta da dağılsın).
signal enemy_died(b: ValleyEnemy)

enum Phase { DORMANT, CALM, WARNING, WAVE }

const FIRST_DELAY := 40.0     ## ilk onarımdan sonra ilk dalgaya kadar (sn)
const CALM_TIME := 150.0      ## dalgalar arası
const WARNING_TIME := 7.0
const SPAWN_EVERY := 1.1
const SPAWN_RING := 25.0
const MEND_PER_SEC := 2.5     ## sakin dönemde parçaların toparlanması (dayanıklılık/sn)
const SEPARATION := 0.9
const MAX_PUDDLES := 18

var sites: Array[RepairSite] = []
var fx: GatherFx
var finale: Node
var atmosphere: Node3D
var phase := Phase.DORMANT
var wave := 0                 ## başlamış son dalganın numarası
var timer := 0.0
var blots: Array[ValleyEnemy] = []
var _queue: Array = []
var _spawn_t := 0.0
var _spawn_dir := Vector3.FORWARD
var _mend_t := 0.0
var _puddles: Array[MeshInstance3D] = []
var _puddle_mesh: CylinderMesh
var _attack_note := {}
var _sun_base := -1.0
## Daha önce görülmüş düşman türleri (kayıtlı).
var seen: Array = []
## Çevrimiçi katılan tarafta: dalgaları ev sahibi yönetir, burası yalnızca kopyaları tutar.
var mirror := false
var _next_id := 1
var _by_net := {}


func setup(site_list: Array, gather_fx: GatherFx, fin: Node = null, atmo: Node3D = null) -> void:
	for s in site_list:
		sites.append(s)
	fx = gather_fx
	finale = fin
	atmosphere = atmo
	add_to_group(SaveSystem.PERSIST_GROUP)
	_puddle_mesh = CylinderMesh.new()
	_puddle_mesh.top_radius = 0.5
	_puddle_mesh.bottom_radius = 0.5
	_puddle_mesh.height = 0.02
	_puddle_mesh.radial_segments = 14
	_puddle_mesh.rings = 1


func players() -> Array:
	return get_tree().get_nodes_in_group(&"players")


func repaired_count() -> int:
	var n := 0
	for s in sites:
		if s.is_complete():
			n += 1
	return n


func active() -> bool:
	return phase == Phase.WAVE


func seconds_to_wave() -> float:
	return timer if phase in [Phase.CALM, Phase.WARNING] else 0.0


## Dalga içeriği: tür başına sayı. Yeni türler dalgalarla tanıtılır:
## 1: mürekkep lekeleri, 2: kemirgenler, 3: orman ruhu ve Kara Leke, 4: sel suyu.
static func composition(wave_no: int, repaired: int, player_count: int, river_target := true) -> Dictionary:
	var c := _ink_composition(wave_no, repaired, player_count)
	var rodent := 0
	if wave_no >= 2:
		rodent = 3 + (wave_no - 2) / 2 * 2
	var spirit := 0
	if wave_no >= 3:
		spirit = 1 + (wave_no - 3) / 3
	var flood := 0
	if river_target and wave_no >= 4 and wave_no % 2 == 0:
		flood = 1 + (1 if wave_no >= 8 else 0)
	if player_count > 1:
		rodent = ceili(rodent * 1.5)
		if spirit > 0:
			spirit += 1
	c["rodent"] = mini(rodent, 9)
	c["spirit"] = mini(spirit, 3)
	c["flood"] = flood
	return c


static func _ink_composition(wave_no: int, repaired: int, player_count: int) -> Dictionary:
	var small := 2 + wave_no + repaired
	var big := 0
	if wave_no >= 3:
		big = 1 + (wave_no - 3) / 2
	if repaired >= 3 and wave_no >= 2:
		big += 1
	if wave_no == 1:
		small = 2   # tanışma dalgası
		big = 0
	if player_count > 1:
		small = ceili(small * 1.5)
		if big > 0 or wave_no >= 2:
			big += 1
	return {"small": mini(small, 14), "big": mini(big, 4)}


func _physics_process(delta: float) -> void:
	if mirror:
		_fade_puddles(delta)
		return
	if not GameState.enemies_enabled:
		if not blots.is_empty() or phase == Phase.WAVE or phase == Phase.WARNING:
			_calm_down()
		return
	if finale != null and bool(finale.get("playing")):
		return
	match phase:
		Phase.DORMANT:
			if repaired_count() > 0:
				phase = Phase.CALM
				timer = FIRST_DELAY
		Phase.CALM:
			timer -= delta
			_mend(delta)
			if timer <= 0.0:
				_warn()
		Phase.WARNING:
			timer -= delta
			if timer <= 0.0:
				_begin_wave()
		Phase.WAVE:
			_spawn_t -= delta
			if not _queue.is_empty() and _spawn_t <= 0.0:
				_spawn_t = SPAWN_EVERY
				_spawn(_queue.pop_front())
			if _queue.is_empty() and blots.is_empty():
				_end_wave()
	_fade_puddles(delta)


func _warn() -> void:
	phase = Phase.WARNING
	timer = WARNING_TIME
	var a := randf() * TAU
	_spawn_dir = Vector3(cos(a), 0, sin(a))
	_dim(true)
	wave_warning.emit(wave + 1, _spawn_dir)


func _begin_wave() -> void:
	wave += 1
	phase = Phase.WAVE
	var c := composition(wave, repaired_count(), players().size(), _river_has_parts())
	_queue.clear()
	for i in c["small"]:
		_queue.append(ValleyEnemy.Kind.SMALL)
	for i in c["big"]:
		_queue.insert(mini(2 + i * 3, _queue.size()), ValleyEnemy.Kind.BIG)
	for i in c["spirit"]:
		_queue.insert(mini(1 + i * 4, _queue.size()), ValleyEnemy.Kind.SPIRIT)
	for i in c["rodent"]:
		_queue.insert(mini(i / 3 * 4, _queue.size()), ValleyEnemy.Kind.RODENT)
	for i in c["flood"]:
		_queue.insert(mini(3 + i * 6, _queue.size()), ValleyEnemy.Kind.FLOOD)
	_spawn_t = 0.0
	wave_started.emit(wave, _queue.size())


func _end_wave() -> void:
	phase = Phase.CALM
	timer = CALM_TIME
	_dim(false)
	for p: Player in players():
		p.heal_full()
	wave_cleared.emit(wave)
	SaveSystem.save_game.call_deferred()


## Düşmanlar ayarı kapatılınca: lekeler sessizce dağılır.
func _calm_down() -> void:
	for b in blots.duplicate():
		if is_instance_valid(b):
			b.queue_free()
	blots.clear()
	_queue.clear()
	_dim(false)
	phase = Phase.CALM if repaired_count() > 0 else Phase.DORMANT
	timer = CALM_TIME


## Köprü ya da çarkta takılı parça var mı (sel ancak o zaman gelir).
func _river_has_parts() -> bool:
	for s in sites:
		if s.site_id in ["bridge", "mill_wheel"] and not s.damageable_slots().is_empty():
			return true
	return false


const FLOOD_START_Z := -17.0


func _spawn(kind: int) -> ValleyEnemy:
	var b := ValleyEnemy.new().setup(kind, self)
	b.net_id = _next_id
	_next_id += 1
	b.name = "Enemy%d" % b.net_id
	var p: Vector3
	if kind == ValleyEnemy.Kind.FLOOD:
		p = Vector3(ValleyShape.river_x(FLOOD_START_Z), ValleyShape.water_y(FLOOD_START_Z), FLOOD_START_Z)
	else:
		var side := _spawn_dir.rotated(Vector3.UP, randf_range(-0.45, 0.45))
		p = side * SPAWN_RING
		p.x = clampf(p.x, -ValleyShape.HALF_SIZE + 2.0, ValleyShape.HALF_SIZE - 2.0)
		p.z = clampf(p.z, -ValleyShape.HALF_SIZE + 2.0, ValleyShape.HALF_SIZE - 2.0)
		p.y = maxf(ValleyShape.height(p.x, p.z), ValleyShape.water_y(p.z))
	add_child(b)
	b.global_position = p
	blots.append(b)
	fx.burst(b.fx_kind(), p + Vector3(0, 0.3, 0), Vector3.UP, 1.2)
	if kind != ValleyEnemy.Kind.FLOOD:
		retarget(b)
	AudioManager.play_sfx_3d(_sfx(kind, "spawn"), p, -4.0)
	if not seen.has(kind):
		seen.append(kind)
		enemy_introduced.emit(kind)
	return b


static func _sfx(kind: int, what: String) -> String:
	var base: String = {ValleyEnemy.Kind.RODENT: "rodent", ValleyEnemy.Kind.SPIRIT: "spirit", ValleyEnemy.Kind.FLOOD: "flood"}.get(kind, "ink")
	return "%s_%s" % [base, what]


## Leke için yapı ve yuva seç: yakın olan ve az aşınmış parçası olan yapılar önde.
func retarget(b: ValleyEnemy) -> bool:
	var best: RepairSite = null
	var best_score := INF
	for s in sites:
		var ids := s.damageable_slots()
		if ids.is_empty():
			continue
		var d := _nearest_point(s, b.global_position).distance_to(b.global_position)
		var score := d + randf() * 6.0
		if score < best_score:
			best = s
			best_score = score
	if best == null:
		b.site = null
		return false
	b.site = best
	var ids := best.damageable_slots()
	if b.kind == ValleyEnemy.Kind.RODENT:
		# Kemirgen ahşap parçayı seçer (yoksa ne bulursa).
		var wood := ids.filter(func(id): return Crafting.part_material(str(Repair.slot_state(best.state, id)["part"])) in ValleyEnemy.WOOD_MATS)
		if not wood.is_empty():
			ids = wood
	b.slot_id = ids[randi() % ids.size()]
	var off := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).limit_length(1.0)
	b.goal = _nearest_point(best, b.global_position) + off
	b.state = ValleyEnemy.State.SEEK
	return true


func _nearest_point(s: RepairSite, from: Vector3) -> Vector3:
	var best := s.global_position
	var bd := INF
	for p: Vector3 in s.attack_points():
		var d := p.distance_to(from)
		if d < bd:
			bd = d
			best = p
	return best


func nearest_player(from: Vector3, max_d: float) -> Node3D:
	var best: Player = null
	var bd := max_d
	for p: Player in players():
		if p.downed:
			continue
		var d := p.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = p
	return best


## Lekeler üst üste binmesin.
func separation(b: ValleyEnemy) -> Vector3:
	var push := Vector3.ZERO
	for o in blots:
		if o == b or not is_instance_valid(o):
			continue
		var d := b.global_position - o.global_position
		d.y = 0.0
		var l := d.length()
		var minl := SEPARATION * (b.size + o.size) / 0.72
		if l < minl and l > 0.001:
			push += d / l * (minl - l)
	return push


func on_hit(b: ValleyEnemy) -> void:
	var dir := Vector3.UP
	fx.burst(b.fx_kind(), b.global_position + Vector3(0, b.size * 0.7, 0), dir, 0.9)
	AudioManager.play_sfx_3d(_sfx(b.kind, "hit"), b.global_position)
	PlatformServices.vibrate(25)


func on_died(b: ValleyEnemy) -> void:
	blots.erase(b)
	_by_net.erase(b.net_id)
	enemy_died.emit(b)
	fx.burst(b.fx_kind(), b.global_position + Vector3(0, b.size * 0.5, 0), Vector3.UP, 2.2 if b.size > 0.5 else 1.5)
	if b.kind in [ValleyEnemy.Kind.SMALL, ValleyEnemy.Kind.BIG]:
		splat(b.global_position, b.size * 2.6)
	elif b.kind == ValleyEnemy.Kind.SPIRIT:
		fx.burst("sparkle", b.global_position + Vector3(0, b.size, 0), Vector3.UP, 1.0)
	AudioManager.play_sfx_3d(_sfx(b.kind, "pop"), b.global_position)


## Sel vadinin güneyinden çıkıp gitti (dağıtılmadan).
func on_left(b: ValleyEnemy) -> void:
	blots.erase(b)


func on_part_broken(_b: ValleyEnemy, site: RepairSite, slot_id: String) -> void:
	part_broken.emit(site, slot_id)


func drip(pos: Vector3, kind := "ink") -> void:
	fx.burst(kind, pos, Vector3.UP, 0.35)
	for s in sites:
		if pos.distance_to(_nearest_point(s, pos)) < 3.0:
			var now := Time.get_ticks_msec()
			if now - int(_attack_note.get(s.site_id, -99999)) > 8000:
				_attack_note[s.site_id] = now
				site_attacked.emit(s)


## Ölen lekenin yerde bıraktığı, yavaşça solan mürekkep izi.
func splat(pos: Vector3, radius: float) -> void:
	var mi: MeshInstance3D
	if _puddles.size() >= MAX_PUDDLES:
		mi = _puddles.pop_front()
	else:
		mi = MeshInstance3D.new()
		mi.mesh = _puddle_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(ValleyEnemy.INK, 0.55)
		mi.material_override = m
		add_child(mi)
	mi.global_position = pos + Vector3(0, 0.03, 0)
	mi.scale = Vector3(radius, 1, radius * randf_range(0.7, 1.0))
	mi.rotation.y = randf() * TAU
	mi.set_meta("life", 6.0)
	(mi.material_override as StandardMaterial3D).albedo_color.a = 0.55
	_puddles.append(mi)


func _fade_puddles(delta: float) -> void:
	for mi in _puddles:
		var life := float(mi.get_meta("life", 0.0)) - delta
		mi.set_meta("life", life)
		(mi.material_override as StandardMaterial3D).albedo_color.a = clampf(life / 6.0, 0.0, 1.0) * 0.55
		mi.visible = life > 0.0


func _mend(delta: float) -> void:
	_mend_t += delta
	if _mend_t < 1.0:
		return
	for s in sites:
		s.mend(MEND_PER_SEC * _mend_t)
	_mend_t = 0.0


## Dalga sırasında güneş biraz solar (mürekkep havası); bitince geri gelir.
func _dim(on: bool) -> void:
	if atmosphere == null or atmosphere.get("sun") == null:
		return
	var sun: DirectionalLight3D = atmosphere.get("sun")
	if _sun_base < 0.0:
		_sun_base = sun.light_energy
	var t := create_tween()
	t.tween_property(sun, "light_energy", _sun_base * (0.72 if on else 1.0), 2.5)


# --- Çevrimiçi ----------------------------------------------------------------------
## Ev sahibi: dalga durumu ve tüm düşmanların özeti.
func net_pack() -> Array:
	var list := []
	for b in blots:
		if is_instance_valid(b) and b.alive():
			list.append(b.net_pack())
	return [phase, wave, timer, list]


## Katılan: özete göre kopyaları oluştur, taşı, artık olmayanları kaldır.
func apply_net(a: Array) -> void:
	if a.size() < 4:
		return
	phase = int(a[0])
	wave = int(a[1])
	timer = float(a[2])
	var present := {}
	for e: Array in a[3]:
		var id := int(e[0])
		present[id] = true
		var b: ValleyEnemy = _by_net.get(id)
		if b == null or not is_instance_valid(b):
			b = ValleyEnemy.new().setup(int(e[1]), self)
			b.puppet = true
			b.net_id = id
			b.name = "Enemy%d" % id
			add_child(b)
			b.global_position = Vector3(e[2], e[3], e[4])
			b.rotation.y = float(e[5])
			blots.append(b)
			_by_net[id] = b
			fx.burst(b.fx_kind(), b.global_position + Vector3(0, 0.3, 0), Vector3.UP, 1.2)
		b.apply_net(e)
	for id in _by_net.keys():
		if not present.has(id):
			var b: ValleyEnemy = _by_net[id]
			_by_net.erase(id)
			if is_instance_valid(b) and b.alive():
				# Sel vadiden çıktı ya da ayar kapandı: sessizce kaybolur.
				blots.erase(b)
				b.queue_free()


func net_find(id: int) -> ValleyEnemy:
	for b in blots:
		if is_instance_valid(b) and b.net_id == id:
			return b
	return null


## Katılan: ev sahibinde dağılan düşman burada da dağılsın.
func net_died(id: int) -> void:
	var b: ValleyEnemy = _by_net.get(id)
	if b != null and is_instance_valid(b) and b.alive():
		b._die()


func net_dim(on: bool) -> void:
	_dim(on)


# --- Kayıt ---------------------------------------------------------------------------
func save_state(data: Dictionary) -> void:
	# Süren dalga kaydedilmez: yüklenince kısa bir uyarıyla yeniden başlar.
	var p := phase
	var t := timer
	if phase == Phase.WAVE or phase == Phase.WARNING:
		p = Phase.CALM
		t = 10.0
	data["enemies"] = {"phase": p, "wave": wave - (1 if phase == Phase.WAVE else 0), "timer": t, "seen": seen.duplicate()}


func load_state(data: Dictionary) -> void:
	var e: Dictionary = data.get("enemies", {})
	if e.is_empty():
		return
	phase = clampi(int(e.get("phase", 0)), Phase.DORMANT, Phase.CALM)
	wave = maxi(int(e.get("wave", 0)), 0)
	timer = float(e.get("timer", FIRST_DELAY))
	seen = []
	for k in e.get("seen", []):
		seen.append(int(k))
