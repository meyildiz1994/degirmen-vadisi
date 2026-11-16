extends Node3D
## Vadi sahnesinin kurucusu: arazi, dere, bitki örtüsü, yapılar, ambiyans ve oyuncu.
## Her sistem kendi sahnesinde/script'inde; burası onları yerleştirip birbirine bağlar.

const BRIDGE_Z := ValleyShape.BRIDGE_Z
const MILL_Z := -8.0
const WORKSHOP_POS := Vector2(-13.0, 4.0)
const PLAYER_SPAWN := Vector2(-9.5, 9.5)

@onready var vegetation: Node3D = $Vegetation
@onready var props: Node3D = $ResourceProps
@onready var mill: Mill = $Mill
@onready var bridge: RepairSite = $Bridge
@onready var workshop: Node3D = $Workshop
@onready var player: Player = $Player
@onready var hud: CanvasLayer = $HUD
@onready var touch: Control = $TouchLayer/TouchControls
@onready var ambience_root: Node3D = $Ambience

var gather_world: GatherWorld
var tutorial: Tutorial
var finale: Finale
var director: EnemyDirector
var coop: CoopManager
var _broke_note := -99999


func _ready() -> void:
	_place_structures()
	vegetation.keep_clear.assign([
		Vector3(mill.position.x, mill.position.z, 5.0),
		Vector3(WORKSHOP_POS.x, WORKSHOP_POS.y, 4.6),
		Vector3(ValleyShape.river_x(BRIDGE_Z), BRIDGE_Z, 4.5),
		Vector3(PLAYER_SPAWN.x, PLAYER_SPAWN.y, 2.0),
		Vector3(props.COPPER_SPOT.x, props.COPPER_SPOT.y, 2.5),
		Vector3(props.IRON_SPOT.x, props.IRON_SPOT.y, 2.5),
	])
	vegetation.build()
	props.build(vegetation.oak_positions)
	_place_player()
	_build_ambience()
	hud.bind_player(player)
	_build_gathering()
	player.focus_changed.connect(func(t): touch.set_interact_available(t != null))
	finale = Finale.new()
	finale.name = "Finale"
	add_child(finale)
	finale.setup(mill, player, hud, $Atmosphere)
	_build_combat()
	SaveSystem.restore_persisted_nodes()
	bridge.player = player
	bridge.open_requested.connect(hud.open_repair)
	for site: RepairSite in [bridge, mill.wall, mill.wheel]:
		site.completed.connect(func(): ItemMemory.record_deed(GameState.inventory.tools, site.site_id); SaveSystem.save_game.call_deferred())
	mill.wall.open_requested.connect(hud.open_repair)
	mill.wheel.open_requested.connect(hud.open_repair)
	var iron := Vector3(props.IRON_SPOT.x, 0, props.IRON_SPOT.y)
	iron.y = ValleyShape.height(iron.x, iron.z) + 0.8
	tutorial.setup(hud, gather_world, workshop.interactable, player, bridge, mill.interactable, iron, mill)
	hud.quest_marker.tutorial = tutorial
	AudioManager.play_music("music_explore")
	if ScreenshotCapture.requested():
		add_child(ScreenshotCapture.new())


## Mürekkep lekeleri (dalga yöneticisi) ve iki kişilik oyun.
func _build_combat() -> void:
	player.respawn_point = _ground(WORKSHOP_POS.x + 2.4, WORKSHOP_POS.y + 2.2) + Vector3(0, 0.3, 0)
	var sites: Array = [bridge, mill.wall, mill.wheel]
	director = EnemyDirector.new()
	director.name = "Enemies"
	add_child(director)
	director.setup(sites, gather_world.fx, finale, $Atmosphere)
	hud.combat.bind_director(director, sites)
	director.wave_warning.connect(_on_wave_warning)
	director.wave_cleared.connect(func(_w): hud.show_toast("MSG_WAVE_CLEARED", 3.5); AudioManager.play_sfx("wave_cleared"))
	director.part_broken.connect(_on_part_broken)
	director.enemy_introduced.connect(_on_enemy_introduced)
	coop = CoopManager.new()
	coop.name = "Coop"
	add_child(coop)
	coop.setup(self, player, hud, gather_world)
	hud.bind_coop(coop)
	coop.joined.connect(func(p2: Player): hud.show_toast("MSG_COOP_JOINED", 3.0); _watch_player(p2))
	_watch_player(player)


func _watch_player(p: Player) -> void:
	p.downed_changed.connect(func(d: bool):
		if d:
			AudioManager.play_sfx("player_downed")
			hud.show_toast("MSG_DOWNED" if coop.is_active() else "MSG_DOWNED_SOLO", 4.0)
		else:
			AudioManager.play_sfx("player_revived"))


func _on_wave_warning(wave_no: int, _dir: Vector3) -> void:
	AudioManager.play_sfx("wave_warning")
	if wave_no == 1:
		# İlk karşılaşma: metinsiz kart (leke → yapı, alet → leke) ve kısa açıklama.
		hud.show_toast("MSG_FIRST_WAVE", 7.0)
		hud.hint_card.flash(["ink_blot", "arrow", "bridge", "axe", "arrow", "ink_blot"], 9.0)
	else:
		hud.show_toast("MSG_WAVE_WARNING", 3.0)
		hud.hint_card.flash(["ink_blot", "arrow", "bridge"], 4.0)


## Yeni düşman türü ilk kez göründü: kısa tanıtım (ikon kartı + metin).
func _on_enemy_introduced(kind: int) -> void:
	var msg: String = {ValleyEnemy.Kind.RODENT: "MSG_INTRO_RODENT", ValleyEnemy.Kind.SPIRIT: "MSG_INTRO_SPIRIT", ValleyEnemy.Kind.FLOOD: "MSG_INTRO_FLOOD"}.get(kind, "")
	if msg == "":
		return
	var target := "mill" if kind == ValleyEnemy.Kind.SPIRIT else "bridge"
	hud.show_toast(msg, 6.0)
	hud.hint_card.flash([ValleyEnemy.ICONS[kind], "arrow", target, "axe", "arrow", ValleyEnemy.ICONS[kind]], 7.0)


func _on_part_broken(_site: RepairSite, _slot_id: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _broke_note > 6000:
		_broke_note = now
		hud.show_toast("MSG_INK_BROKE", 4.0)
		hud.hint_card.flash(["ink_blot", "arrow", "crack", "arrow", "workshop"], 4.0)


## Toplama: kaynaklar + geri bildirim + kayıt (GatherWorld), heybe bildirimleri, eğitim.
func _build_gathering() -> void:
	gather_world = GatherWorld.new()
	gather_world.name = "Gathering"
	add_child(gather_world)
	gather_world.setup(player, vegetation, props.gatherables)
	gather_world.item_arrived.connect(hud.pickup_feed.add_item)
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	add_child(tutorial)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, ValleyShape.height(x, z), z)


func _place_structures() -> void:
	var mx := ValleyShape.river_x(MILL_Z) - ValleyShape.river_half_width(MILL_Z) - 4.0
	mill.position = _ground(mx, MILL_Z) + Vector3(0, 0.05, 0)
	mill.on_placed()
	bridge.position = Vector3(ValleyShape.river_x(BRIDGE_Z), ValleyShape.water_y(BRIDGE_Z), BRIDGE_Z)
	workshop.position = _ground(WORKSHOP_POS.x, WORKSHOP_POS.y) + Vector3(0, 0.1, 0)
	workshop.rotation.y = 0.25


func _place_player() -> void:
	player.position = _ground(PLAYER_SPAWN.x, PLAYER_SPAWN.y) + Vector3(0, 0.3, 0)
	# Başlangıçta değirmene ve dereye doğru bak
	var to_mill := mill.position - player.position
	player.rotation.y = atan2(-to_mill.x, -to_mill.z) * 0.6


## Ambiyans 3D konumlu: dere boyunca su sesi, şelalede gürültü, vadide rüzgâr.
func _build_ambience() -> void:
	for z: float in [-14.0, -2.0, 10.0, 22.0]:
		AudioManager.create_ambience("amb_stream", ambience_root, Vector3(ValleyShape.river_x(z), ValleyShape.water_y(z), z), 5.0, 22.0)
	AudioManager.create_ambience("amb_waterfall", ambience_root, Vector3(ValleyShape.river_x(-21.5), 2.0, -21.5), 10.0, 45.0)
	AudioManager.create_ambience("amb_wind_leaves", ambience_root, Vector3(0, 6, 0), 40.0, 200.0)
	AudioManager.create_ambience("amb_evening_birds", ambience_root, Vector3(-15, 5, -5), 25.0, 120.0)
