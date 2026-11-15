class_name Gatherable
extends Interactable
## Toplanabilir kaynak: ağaç, kaya, damar ya da elle alınan küçük şey.
## Durum makinesi: READY → (vuruşlar) → DEPLETED → (süre) → GROWING → READY.
## Kaynak asla kalıcı olarak tükenmez. Görseller alt sınıflarda.

signal was_hit(sweet: bool)
signal depleted(drops: Dictionary)
signal restored

enum State { READY, DEPLETED, GROWING }

@export var resource_id := "boulder"
@export var save_id := ""

var state: int = State.READY
var progress := 0.0      ## 0..1
var timer := 0.0         ## mevcut durumda kalan süre
var growth := 1.0        ## GROWING sırasında 0..1
var _def: Dictionary
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	_def = Materials.resource(resource_id)
	display_name_key = str(_def.get("name", "NAME_UNKNOWN"))
	action_key = {"axe": "ACTION_CHOP", "pickaxe": "ACTION_MINE"}.get(tool_kind(), "ACTION_GATHER")
	radius = 2.3 if is_hand() else 2.7
	_rng.randomize()
	set_process(false)


func tool_kind() -> String:
	return str(_def.get("tool", "hand"))


func is_hand() -> bool:
	return tool_kind() == "hand"


func hardness() -> float:
	return float(_def.get("hardness", 1.0))


func fx_kind() -> String:
	return str(_def.get("fx", "dust"))


func sfx_hit() -> String:
	return str(_def.get("sfx_hit", "gather_pickup"))


func sfx_done() -> String:
	return str(_def.get("sfx_done", "gather_pickup"))


func can_focus() -> bool:
	return state == State.READY and is_visible_in_tree()


func hint_text() -> String:
	var base := super.hint_text()
	if is_hand():
		return base
	var t := GameState.inventory.best_tool(tool_kind(), resource_id)
	if t == null:
		return base
	var left := int(ceil((1.0 - progress) * t.hits_for(resource_id) - 0.001))
	return "%s  ·  %d %s" % [base, left, tr("HITS")]


## Bir vuruş: progress_amount normalde 1/gereken_vuruş, tatlı vuruşta iki katı.
## Kaynak tamamlanırsa true döner.
func apply_hit(progress_amount: float, sweet: bool) -> bool:
	if state != State.READY:
		return false
	progress = minf(progress + progress_amount, 1.0)
	_on_hit(sweet)
	was_hit.emit(sweet)
	if progress >= 0.999:
		complete()
		return true
	return false


func complete() -> void:
	var drops := roll_drops()
	progress = 0.0
	_enter_depleted()
	depleted.emit(drops)


func roll_drops() -> Dictionary:
	var out := {}
	for d: Dictionary in _def.get("drops", []):
		if _rng.randf() > float(d.get("chance", 1.0)):
			continue
		var n := _rng.randi_range(int(d.get("min", 1)), int(d.get("max", 1)))
		if n > 0:
			out[str(d["id"])] = int(out.get(str(d["id"]), 0)) + n
	return out


## Kaynak tükenince ne kadar sonra geri gelir. Ağaçlarda kütük + fidan süresi ayrı.
func depleted_time() -> float:
	return float(_def.get("respawn", _def.get("stump_time", 60.0)))


func growing_time() -> float:
	return float(_def.get("sapling_time", 2.0))


func _enter_depleted() -> void:
	state = State.DEPLETED
	timer = depleted_time()
	growth = 0.0
	set_process(true)
	_apply_state()


func _enter_growing(start_growth := 0.0) -> void:
	state = State.GROWING
	growth = start_growth
	timer = growing_time() * (1.0 - start_growth)
	set_process(true)
	_apply_state()


func _enter_ready() -> void:
	state = State.READY
	growth = 1.0
	timer = 0.0
	set_process(false)
	_apply_state()
	restored.emit()


func _process(delta: float) -> void:
	timer -= delta
	if state == State.GROWING:
		growth = clampf(1.0 - timer / maxf(growing_time(), 0.01), 0.0, 1.0)
		_update_growth()
	if timer > 0.0:
		return
	if state == State.DEPLETED:
		_enter_growing()
	elif state == State.GROWING:
		_enter_ready()


# --- Kayıt (GatherWorld toplar) --------------------------------------------------
func to_save() -> Array:
	return [state, snappedf(timer, 0.1), snappedf(progress, 0.01)]


func from_save(a: Array) -> void:
	if a.size() < 3:
		return
	progress = float(a[2])
	match int(a[0]):
		State.DEPLETED:
			_enter_depleted()
			timer = float(a[1])
		State.GROWING:
			_enter_growing(clampf(1.0 - float(a[1]) / maxf(growing_time(), 0.01), 0.0, 1.0))
		_:
			_enter_ready()


# --- Alt sınıfların dolduracağı görsel kancalar ----------------------------------
func _apply_state() -> void:
	pass


func _update_growth() -> void:
	pass


func _on_hit(_sweet: bool) -> void:
	pass


## Parçacık ve ganimetin çıktığı nokta (dünya koordinatı).
func fx_point() -> Vector3:
	return global_position + Vector3(0, 0.5, 0)


## Odak parlaması için [Mesh, global Transform3D] çiftleri.
func highlight_parts() -> Array:
	return []
