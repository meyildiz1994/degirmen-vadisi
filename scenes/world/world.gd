extends Node3D
## Vadi sahnesinin kurucusu: arazi, dere, bitki örtüsü, yapılar, ambiyans ve oyuncu.
## Her sistem kendi sahnesinde/script'inde; burası onları yerleştirip birbirine bağlar.

const BRIDGE_Z := 8.0
const MILL_Z := -8.0
const WORKSHOP_POS := Vector2(-13.0, 4.0)
const PLAYER_SPAWN := Vector2(-9.5, 9.5)

@onready var vegetation: Node3D = $Vegetation
@onready var props: Node3D = $ResourceProps
@onready var mill: Node3D = $Mill
@onready var bridge: Node3D = $Bridge
@onready var workshop: Node3D = $Workshop
@onready var player: Player = $Player
@onready var hud: CanvasLayer = $HUD
@onready var touch: Control = $TouchLayer/TouchControls
@onready var ambience_root: Node3D = $Ambience

var gather_world: GatherWorld
var tutorial: Tutorial


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
	SaveSystem.restore_persisted_nodes()
	tutorial.setup(hud, gather_world, workshop.interactable)
	AudioManager.play_music("music_explore")
	if ScreenshotCapture.requested():
		add_child(ScreenshotCapture.new())


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
