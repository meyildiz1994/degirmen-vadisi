extends CanvasLayer
## Oyun içi arayüz: aktif görev (sağ üst), etkileşim ipucu (alt orta), kısa mesajlar,
## duraklatma menüsü ve geliştirici bilgisi (FPS / draw call / kalite).

@onready var quest_text: Label = %QuestText
@onready var quest_panel: Control = %QuestPanel
@onready var quest_button: Button = %QuestButton
@onready var new_quest_bubble: Control = %NewQuestBubble
@onready var hint_panel: Control = %HintPanel
@onready var hint_label: Label = %HintLabel
@onready var hint_glyph: GlyphBadge = %HintGlyph
@onready var toast_panel: Control = %ToastPanel
@onready var toast_label: Label = %ToastLabel
@onready var debug_label: Label = %DebugLabel
@onready var look_hint: Control = %LookHintCard
@onready var pause_menu: Control = %PauseMenu
@onready var resume_button: Button = %ResumeButton
@onready var quality_button: Button = %QualityButton
@onready var language_button: Button = %LanguageButton
@onready var touch_button: Button = %TouchPreviewButton
@onready var rhythm_button: Button = %RhythmButton
@onready var root: Control = $SafeArea/Root

var player: Player
var _toast_tween: Tween
var _focus: Interactable
var _quest_open := false
var _quest_tween: Tween
var _bubble_tween: Tween
var rhythm_ring: RhythmRing
var pickup_feed: PickupFeed
var hint_card: IconHintCard
var inventory_panel: InventoryPanel
var workshop_panel: WorkshopPanel
var repair_panel: RepairPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hint_panel.visible = false
	toast_panel.modulate.a = 0.0
	pause_menu.visible = false
	quest_panel.visible = false
	new_quest_bubble.modulate.a = 0.0
	quest_button.pressed.connect(toggle_quest_log)
	debug_label.visible = OS.is_debug_build()
	touch_button.visible = not GameState.is_mobile
	GameState.quest_changed.connect(_on_quest_changed)
	GameState.quality_changed.connect(func(_l): _refresh_buttons())
	GameState.locale_changed.connect(func(_l): _refresh_texts())
	InputManager.device_changed.connect(func(_d): _refresh_hint())
	InputManager.touch_preview_changed.connect(func(_e): _refresh_buttons())
	resume_button.pressed.connect(set_paused.bind(false))
	quality_button.pressed.connect(func(): AudioManager.play_ui("ui_click"); GameState.cycle_quality())
	language_button.pressed.connect(func(): AudioManager.play_ui("ui_click"); GameState.toggle_locale())
	touch_button.pressed.connect(func(): InputManager.set_touch_preview(not InputManager.touch_preview))
	rhythm_button.pressed.connect(func(): AudioManager.play_ui("ui_click"); GameState.set_rhythm_hits(not GameState.rhythm_hits))
	GameState.rhythm_changed.connect(func(_e): _refresh_buttons())
	_build_gather_ui()
	_on_quest_changed(GameState.current_quest_key)
	_refresh_buttons()


func bind_player(p: Player) -> void:
	player = p
	p.focus_changed.connect(_on_focus_changed)
	p.interacted_with.connect(_on_interacted)
	rhythm_ring.bind(p.gather, p.camera)
	p.gather.session_started.connect(func(_g, _t): _refresh_hint())
	p.gather.session_ended.connect(_refresh_hint)
	p.gather.hit_landed.connect(func(_g, _s): _refresh_hint.call_deferred())
	p.gather.tool_missing.connect(_on_tool_missing)


## Toplama arayüzü kodla kurulur: vuruş halkası, toplama kartları, metinsiz ipucu, heybe.
func _build_gather_ui() -> void:
	rhythm_ring = RhythmRing.new()
	rhythm_ring.name = "RhythmRing"
	add_child(rhythm_ring)
	move_child(rhythm_ring, 0)
	pickup_feed = PickupFeed.new()
	pickup_feed.name = "PickupFeed"
	root.add_child(pickup_feed)
	pickup_feed.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	pickup_feed.offset_left = 8.0
	pickup_feed.offset_top = -40.0
	pickup_feed.offset_right = 300.0
	pickup_feed.offset_bottom = 200.0
	hint_card = IconHintCard.new()
	hint_card.name = "IconHintCard"
	root.add_child(hint_card)
	hint_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hint_card.offset_left = 12.0
	hint_card.offset_top = 12.0
	inventory_panel = InventoryPanel.new()
	inventory_panel.name = "InventoryPanel"
	add_child(inventory_panel)
	move_child(inventory_panel, pause_menu.get_index())
	inventory_panel.closed.connect(_on_inventory_closed)
	workshop_panel = WorkshopPanel.new()
	workshop_panel.name = "WorkshopPanel"
	add_child(workshop_panel)
	move_child(workshop_panel, pause_menu.get_index())
	workshop_panel.closed.connect(_on_inventory_closed)
	repair_panel = RepairPanel.new()
	repair_panel.name = "RepairPanel"
	add_child(repair_panel)
	move_child(repair_panel, pause_menu.get_index())
	repair_panel.closed.connect(_on_inventory_closed)
	PlatformServices.achievement_unlocked.connect(_on_achievement)


func open_workshop() -> void:
	if _begin_modal():
		workshop_panel.open_panel()


func open_repair(site: RepairSite) -> void:
	if _begin_modal():
		repair_panel.open_for(site)


## Atölye ve onarım paneli ortak hazırlığı: heybeyi kapat, oyuncuyu durdur, fareyi bırak.
func _begin_modal() -> bool:
	if modal_open():
		return false
	if inventory_panel.is_open:
		inventory_panel.close_panel()
	AudioManager.play_ui("panel_open")
	InputManager.release_mouse()
	if player:
		player.input_enabled = false
		player.gather.stop()
	hint_panel.visible = false
	return true


func modal_open() -> bool:
	return workshop_panel.is_open or repair_panel.is_open


## Başarım kartı, onarım mesajının ardından gelsin diye biraz bekler.
func _on_achievement(id: String) -> void:
	var text := "%s: %s" % [tr("ACHIEVEMENT_UNLOCKED"), tr(id)]
	get_tree().create_timer(4.2).timeout.connect(show_toast.bind(text, 3.5))


func _on_tool_missing(kind: String, _g: Gatherable) -> void:
	hint_card.flash([kind, "arrow", "workshop"], 3.2)
	AudioManager.play_ui("ui_click")


func toggle_inventory() -> void:
	if inventory_panel.is_open:
		inventory_panel.close_panel()
		return
	AudioManager.play_ui("inventory_open")
	InputManager.release_mouse()
	if player:
		player.input_enabled = false
		player.gather.stop()
	inventory_panel.open_panel()


func _on_inventory_closed() -> void:
	AudioManager.play_ui("panel_close")
	if player:
		player.input_enabled = true
	_refresh_hint()


## Yeni görev: metni güncelle, ikonda bildirim rozeti ve kısa "Yeni görev!" balonu göster.
func _on_quest_changed(key: String) -> void:
	quest_text.text = key
	if _quest_open:
		return
	quest_button.has_new = true
	if _bubble_tween and _bubble_tween.is_valid():
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	_bubble_tween.tween_interval(1.0)
	_bubble_tween.tween_property(new_quest_bubble, "modulate:a", 1.0, 0.35)
	_bubble_tween.tween_interval(4.0)
	_bubble_tween.tween_property(new_quest_bubble, "modulate:a", 0.0, 0.6)


func toggle_quest_log() -> void:
	set_quest_log_open(not _quest_open)


func set_quest_log_open(open: bool) -> void:
	_quest_open = open
	AudioManager.play_ui("panel_open" if open else "panel_close")
	if open:
		quest_button.has_new = false
		new_quest_bubble.modulate.a = 0.0
		if _bubble_tween and _bubble_tween.is_valid():
			_bubble_tween.kill()
	if _quest_tween and _quest_tween.is_valid():
		_quest_tween.kill()
	_quest_tween = create_tween().set_parallel(true)
	quest_panel.pivot_offset = Vector2(quest_panel.size.x - 30.0, 0.0)
	if open:
		quest_panel.visible = true
		quest_panel.modulate.a = 0.0
		quest_panel.scale = Vector2(0.9, 0.9)
		_quest_tween.tween_property(quest_panel, "modulate:a", 1.0, 0.22)
		_quest_tween.tween_property(quest_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_quest_tween.tween_property(quest_panel, "modulate:a", 0.0, 0.18)
		_quest_tween.chain().tween_callback(quest_panel.hide)


func _on_focus_changed(target: Interactable) -> void:
	_focus = target
	_refresh_hint()


func _refresh_hint() -> void:
	hint_panel.visible = _focus != null and not get_tree().paused
	if _focus:
		hint_label.text = _focus.hint_text()
	hint_glyph.refresh()


func _refresh_texts() -> void:
	_refresh_hint()
	_refresh_buttons()


func _refresh_buttons() -> void:
	quality_button.text = "%s: %s" % [tr("QUALITY"), tr(GameState.quality_name_key())]
	language_button.text = "%s: %s" % [tr("LANGUAGE"), "Türkçe" if GameState.current_locale() == "tr" else "English"]
	touch_button.text = tr("TOUCH_PREVIEW_ON") if InputManager.touch_preview else tr("TOUCH_PREVIEW_OFF")
	rhythm_button.text = "%s: %s" % [tr("RHYTHM_HITS"), tr("ON") if GameState.rhythm_hits else tr("OFF")]


func _on_interacted(target: Interactable) -> void:
	if target.message_key != "":
		show_toast(target.message_key)


func show_toast(key: String, duration := 3.5) -> void:
	toast_label.text = key
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.25)
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.6)


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_menu.visible = paused
	AudioManager.play_ui("panel_open" if paused else "panel_close")
	if paused:
		InputManager.release_mouse()
		InputManager.release_all_virtual()
		resume_button.grab_focus()
	_refresh_hint()


func _unhandled_input(event: InputEvent) -> void:
	if modal_open():
		return  # atölye / onarım paneli kendi girişini yönetir
	if event.is_action_pressed("pause") and inventory_panel.is_open:
		inventory_panel.close_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quest_log") and not get_tree().paused:
		toggle_quest_log()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and not get_tree().paused:
		toggle_inventory()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	look_hint.visible = InputManager.device == InputManager.Device.KEYBOARD_MOUSE \
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused \
		and not modal_open() and not inventory_panel.is_open
	if debug_label.visible:
		debug_label.text = "FPS %d  |  draw %d  |  %s  |  %s" % [
			Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			tr(GameState.quality_name_key()),
			["KB/M", "Gamepad", "Touch"][InputManager.device],
		]
