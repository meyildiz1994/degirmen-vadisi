class_name CombatOverlay
extends Control
## Mücadele arayüzü, tamamen metinsiz ve dünyaya bağlı:
##  - aşınan/saldırı altındaki yapının üstünde parça başına dayanıklılık damlaları,
##    yapı ekran dışındaysa kenarda mürekkep damlalı bir ok,
##  - oyuncunun başının üstünde can damlaları (yalnızca eksikken ya da dalgada),
##    sersemleyen oyuncunun üstünde dönen yıldızlar ve kaldırma halkası,
##  - iki kişilikte oyuncu rozetleri (1/2) ve 2. oyuncunun hedefinde "A" balonu,
##  - dalga uyarısında lekelerin geleceği yönü gösteren ok, dalgada kalan leke sayacı.

const INK := Color(0.10, 0.14, 0.18)
const PAPER := Color(0.96, 0.92, 0.84)
const HEART := Color(0.90, 0.30, 0.22)
const EDGE := 46.0

var camera: Camera3D
var players: Array[Player] = []
var director: EnemyDirector
var sites: Array[RepairSite] = []
var _attacked := {}       ## site -> kalan vurgu süresi
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func bind_director(d: EnemyDirector, site_list: Array) -> void:
	director = d
	for s in site_list:
		sites.append(s)
	d.site_attacked.connect(func(s): _attacked[s] = 4.0)
	d.part_broken.connect(func(s, _id): _attacked[s] = 5.0)


func _process(delta: float) -> void:
	_t += delta
	for s in _attacked.keys():
		_attacked[s] = float(_attacked[s]) - delta
		if _attacked[s] <= 0.0:
			_attacked.erase(s)
	queue_redraw()


func _cam() -> Camera3D:
	return camera if camera != null and camera.is_inside_tree() else get_viewport().get_camera_3d()


func _draw() -> void:
	var cam := _cam()
	if cam == null or get_tree().paused:
		return
	var in_wave := director != null and director.active()
	for s in sites:
		_draw_site(cam, s, in_wave)
	var coop := players.size() > 1
	for p in players:
		if is_instance_valid(p):
			_draw_player(cam, p, coop, in_wave)
	if coop and players.size() > 1 and is_instance_valid(players[1]):
		_draw_p2_focus(cam, players[1])
	if director != null:
		if director.phase == EnemyDirector.Phase.WARNING:
			_draw_warning(cam)
		elif in_wave:
			_draw_counter()


# --- Yapılar ---------------------------------------------------------------------------
func _draw_site(cam: Camera3D, s: RepairSite, in_wave: bool) -> void:
	var ids: Array = s.state["slots"].keys()
	var any_part := not s.damageable_slots().is_empty()
	var attacked := _attacked.has(s)
	if not any_part and not attacked:
		return
	if not attacked and not s.is_worn() and not in_wave:
		return
	var wp: Vector3 = s.attack_points()[0] + Vector3(0, 2.4, 0)
	var vr := get_viewport_rect()
	var on := not cam.is_position_behind(wp)
	var sp := cam.unproject_position(wp) if on else Vector2.ZERO
	if on and vr.grow(-EDGE * 0.5).has_point(sp):
		_draw_pips(sp, s, ids, attacked)
	elif attacked:
		_draw_edge_arrow(cam, wp, Color(HEART, 0.95))


func _draw_pips(c: Vector2, s: RepairSite, ids: Array, attacked: bool) -> void:
	var n := ids.size()
	var w := 22.0
	var start := c - Vector2((n - 1) * w * 0.5, 0)
	var pulse := 1.0 + (0.12 * sin(_t * 10.0) if attacked else 0.0)
	_blob(c, (n * w * 0.5 + 10.0) * pulse, 18.0 * pulse, Color(PAPER, 0.82))
	for i in n:
		var id: String = ids[i]
		var p := start + Vector2(i * w, 0)
		var h := s.slot_health(id)
		if Repair.is_cracked(s.state, id) or not Repair.is_filled(s.state, id):
			_crack(p, Color(HEART.darkened(0.15), 0.9))
			continue
		var col := Palette.MOSS.lerp(Palette.SUNSET, 1.0 - h) if h > 0.35 else HEART
		draw_circle(p, 8.5, Color(INK, 0.25))
		# Damla soldan sağa dolar: kalan dayanıklılık.
		draw_circle(p, 7.5 * (0.35 + 0.65 * h), col)
		draw_arc(p, 8.5, 0, TAU, 18, Color(INK, 0.6), 1.5, true)


func _crack(p: Vector2, col: Color) -> void:
	var z := PackedVector2Array([p + Vector2(-3, -8), p + Vector2(2, -3), p + Vector2(-3, 2), p + Vector2(3, 8)])
	draw_polyline(z, col, 3.0, true)


func _draw_edge_arrow(cam: Camera3D, wp: Vector3, col: Color) -> void:
	var vr := get_viewport_rect()
	var center := vr.size * 0.5
	var local := cam.global_transform.affine_inverse() * wp
	var dir := Vector2(local.x, -local.y)
	if local.z > 0.0:
		dir = -dir if dir.length() > 0.01 else Vector2(0, 1)
		if dir.length() < 0.01:
			dir = Vector2(0, 1)
	dir = dir.normalized()
	var half := center - Vector2(EDGE, EDGE)
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var p := center + dir * k
	var s := 1.0 + 0.1 * sin(_t * 8.0)
	_blob(p, 26.0 * s, 26.0 * s, Color(PAPER, 0.9))
	_ink_drop(p - dir * 3.0, 11.0 * s, INK)
	var tip := p + dir * 30.0 * s
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, p + dir * 18.0 + side * 9.0, p + dir * 18.0 - side * 9.0]), col)


# --- Oyuncular -------------------------------------------------------------------------
func _draw_player(cam: Camera3D, p: Player, coop: bool, in_wave: bool) -> void:
	var wp := p.global_position + Vector3(0, 2.25, 0)
	if cam.is_position_behind(wp):
		return
	var c := cam.unproject_position(wp)
	if p.downed:
		_draw_downed(c + Vector2(0, 18), p)
	elif p.health < Player.MAX_HEALTH or in_wave:
		var n := Player.MAX_HEALTH
		var w := 15.0
		var start := c - Vector2((n - 1) * w * 0.5, 0)
		for i in n:
			var full := i < p.health
			var q := start + Vector2(i * w, 0)
			_ink_drop(q, 6.5, Color(HEART, 0.95) if full else Color(INK, 0.25))
	if coop:
		var badge := c + Vector2(0, -22)
		var col := Palette.TUNIC if p.index == 0 else CoopManager.P2_TUNIC
		draw_circle(badge, 11.0, Color(PAPER, 0.92))
		draw_circle(badge, 9.0, col)
		var f := get_theme_default_font()
		var txt := str(p.index + 1)
		var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
		draw_string(f, badge + Vector2(-ts.x * 0.5, 5.5), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 15, PAPER)


func _draw_downed(c: Vector2, p: Player) -> void:
	# Dönen yıldızlar: sersemledi.
	for i in 3:
		var a := _t * 3.0 + TAU * i / 3.0
		_star(c + Vector2(cos(a) * 20.0, sin(a) * 6.0 - 6.0), 5.5, Palette.SUNSET_LIGHT)
	if p.revive > 0.0:
		draw_arc(c + Vector2(0, 26), 15.0, -PI * 0.5, -PI * 0.5 + TAU * p.revive, 28, Palette.MOSS, 5.0, true)
		draw_arc(c + Vector2(0, 26), 15.0, 0, TAU, 28, Color(INK, 0.3), 1.5, true)


func _draw_p2_focus(cam: Camera3D, p: Player) -> void:
	if p.focus == null or not is_instance_valid(p.focus) or p.downed:
		return
	var wp := p.focus.global_position + Vector3(0, 1.4, 0)
	if cam.is_position_behind(wp):
		return
	var c := cam.unproject_position(wp)
	draw_circle(c, 15.0, Color(PAPER, 0.92))
	draw_circle(c, 12.5, CoopManager.P2_TUNIC)
	var f := get_theme_default_font()
	var ts := f.get_string_size("A", HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	draw_string(f, c + Vector2(-ts.x * 0.5, 6.5), "A", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, PAPER)


# --- Dalga -----------------------------------------------------------------------------
func _draw_warning(cam: Camera3D) -> void:
	var focus := players[0].global_position if not players.is_empty() and is_instance_valid(players[0]) else Vector3.ZERO
	var from := focus + director._spawn_dir * 14.0 + Vector3(0, 1.0, 0)
	var vr := get_viewport_rect()
	var sp := cam.unproject_position(from)
	if not cam.is_position_behind(from) and vr.grow(-EDGE).has_point(sp):
		var s := 1.0 + 0.15 * sin(_t * 9.0)
		_blob(sp, 30.0 * s, 30.0 * s, Color(PAPER, 0.88))
		_ink_drop(sp, 15.0 * s, INK)
	else:
		_draw_edge_arrow(cam, from, Color(INK, 0.9))


func _draw_counter() -> void:
	var left := director.blots.size() + director._queue.size()
	var c := Vector2(get_viewport_rect().size.x * 0.5, 104.0)
	_blob(c, 52.0, 24.0, Color(PAPER, 0.85))
	_ink_drop(c + Vector2(-20, 0), 11.0, INK)
	var f := get_theme_default_font()
	var txt := "× %d" % left
	draw_string(f, c + Vector2(-4, 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)


# --- Çizim yardımcıları --------------------------------------------------------------
func _blob(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 22:
		var a := TAU * i / 22.0
		var k := 1.0 + 0.06 * sin(a * 3.0 + 1.1) + 0.04 * sin(a * 5.0)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry) * k)
	draw_colored_polygon(pts, col)


## Damla: yukarı sivrilen yuvarlak (mürekkep ya da can).
func _ink_drop(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(0, r * 0.25), r, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.86, r * -0.2), c + Vector2(0, -r * 1.45), c + Vector2(r * 0.86, r * -0.2)]), col)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.05), r * 0.25, Color(1, 1, 1, 0.35 * col.a))


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * i / 10.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
