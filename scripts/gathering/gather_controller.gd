class_name GatherController
extends Node
## Oyuncunun toplama oturumu. Elle alınanlar tek dokunuş; alet gerekenlerde
## ritim vuruşu: küçülen halka hedefe değdiğinde basmak "tatlı vuruş" (2x ilerleme).
## Iskalamak ceza değil, normal vuruş sayılır. Ritim kapalıysa basılı tutmak yeter.
## Tek buton (interact) ile çalışır: klavye E, gamepad A, dokunmatik buton.

signal session_started(target: Gatherable, tool: ToolItem)
signal session_ended
signal hit_landed(target: Gatherable, sweet: bool)
signal tool_missing(kind: String, target: Gatherable)
signal tool_named(tool: ToolItem)

const SWEET_EARLY := 0.13    ## halka hedefe değmeden önceki tolerans (sn)
const SWEET_LATE := 0.11     ## değdikten sonraki tolerans (sn)
const CANCEL_MOVE := 0.35

var player: Player
var target: Gatherable = null
var tool: ToolItem = null
var cycle := 0.0             ## mevcut salınım zamanı (sn)
var swing := 0.6             ## halkanın hedefe ulaşma süresi = aletin sallanma süresi
var _was_holding := false


func _ready() -> void:
	player = get_parent() as Player


func active() -> bool:
	return target != null


## 0: halka en büyük, 1: hedefte. Hedefte bekler.
func ring_phase() -> float:
	return clampf(cycle / maxf(swing, 0.01), 0.0, 1.0)


func in_sweet_window() -> bool:
	return cycle >= swing - SWEET_EARLY and cycle <= swing + SWEET_LATE


func on_interact_pressed(g: Gatherable) -> void:
	if target != null:
		_press_during_session()
		return
	if g.is_hand():
		_pick_by_hand(g)
		return
	var t := GameState.inventory.best_tool(g.tool_kind(), g.resource_id)
	if t == null:
		tool_missing.emit(g.tool_kind(), g)
		return
	_start(g, t)


func _pick_by_hand(g: Gatherable) -> void:
	player.play_pickup()
	if g is TreeGatherable:
		(g as TreeGatherable).set_hitter(player.global_position)
	g.apply_hit(1.0, false)


func _start(g: Gatherable, t: ToolItem) -> void:
	target = g
	tool = t
	swing = t.swing_time()
	cycle = 0.0
	_was_holding = true
	if not target.depleted.is_connected(_on_target_depleted):
		target.depleted.connect(_on_target_depleted)
	player.set_held_tool(t.kind)
	session_started.emit(g, t)


func stop() -> void:
	if target == null:
		return
	if target.depleted.is_connected(_on_target_depleted):
		target.depleted.disconnect(_on_target_depleted)
	target = null
	tool = null
	player.set_held_tool("")
	session_ended.emit()


func _press_during_session() -> void:
	if not GameState.rhythm_hits:
		return
	if cycle < swing * Materials.tune("early_lock", 0.4):
		return  # alet hâlâ havada
	_hit(in_sweet_window())


func _physics_process(delta: float) -> void:
	if target == null:
		return
	if not _still_valid():
		stop()
		return
	player.face_towards(target.global_position)
	cycle += delta
	var holding := player.pinput.interact_held()
	if GameState.rhythm_hits:
		# Basılı tutan oyuncu da ilerler (normal vuruş), sadece tatlı vuruşu kaçırır.
		if holding and _was_holding and cycle >= swing + SWEET_LATE:
			_hit(false)
	elif holding and cycle >= swing:
		_hit(false)
	_was_holding = holding


func _still_valid() -> bool:
	if target.state != Gatherable.State.READY or get_tree().paused:
		return false
	if player.pinput.move_vector().length() > CANCEL_MOVE:
		return false
	return target.global_position.distance_to(player.global_position) < target.radius + 0.6


func _hit(sweet: bool) -> void:
	if target == null or tool == null:
		return
	cycle = 0.0
	_was_holding = player.pinput.interact_held()
	var amount := 1.0 / float(tool.hits_for(target.resource_id))
	if sweet:
		amount *= Materials.tune("sweet_progress", 2.0)
	tool.wear(1)
	if ItemMemory.maybe_name(tool):
		tool_named.emit(tool)
	GameState.inventory.notify_tool_changed()
	player.play_swing(sweet)
	if target is TreeGatherable:
		(target as TreeGatherable).set_hitter(player.global_position)
	var g := target
	hit_landed.emit(g, sweet)  # önce geri bildirim, sonra (olası) tamamlanma
	g.apply_hit(amount, sweet)


func _on_target_depleted(_drops: Dictionary) -> void:
	if tool != null and target != null:
		ItemMemory.record_gather(tool, target.resource_id)
	stop()
