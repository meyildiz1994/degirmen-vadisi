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
var volume_settings: VolumeSettings
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
var tool_belt: ToolBelt
var quest_marker: QuestMarker
var _hover_cursor := false
## Sahnedeki oyuncular (iki kişilikte 2). Paneller açılınca hepsi durur.
var players: Array[Player] = []
var combat: CombatOverlay
var coop: CoopManager
var coop_button: Button
var enemies_button: Button
var _extra_rings := {}
## Duraklatma menüsü açık mı (çevrimiçide ağaç durmadığı için ayrı tutulur).
var menu_open := false
var net_host_button: Button
var net_join_button: Button
var net_address: LineEdit
var net_join_row: HBoxContainer
var net_status: Label
var net_code: Label
var net_steam_button: Button


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
	_build_combat_ui()
	_build_settings_column()
	_on_quest_changed(GameState.current_quest_key)
	_refresh_buttons()


## Duraklatma menüsü iki sütun: solda düğmeler, sağda ses ayarları.
func _build_settings_column() -> void:
	var panel := pause_menu.get_node("Panel")
	var buttons: Control = panel.get_node("VBox")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	panel.remove_child(buttons)
	panel.add_child(cols)
	cols.add_child(buttons)
	var sep := ColorRect.new()
	sep.color = Color(Palette.EARTH, 0.3)
	sep.custom_minimum_size = Vector2(3, 0)
	cols.add_child(sep)
	volume_settings = VolumeSettings.new()
	volume_settings.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_child(volume_settings)
	_build_net_ui(volume_settings)
	_fit_pause_panel.call_deferred()


## Panel sahnede sabit boyutlu; iki sütuna göre ortalanmış hâle getir.
func _fit_pause_panel() -> void:
	var panel: Control = pause_menu.get_node("Panel")
	var ms := panel.get_combined_minimum_size()
	panel.offset_left = -ms.x * 0.5
	panel.offset_right = ms.x * 0.5
	panel.offset_top = -ms.y * 0.5
	panel.offset_bottom = ms.y * 0.5


func bind_player(p: Player) -> void:
	player = p
	players = [p]
	combat.camera = p.camera
	combat.players = players
	tool_belt.player = p
	quest_marker.player = p
	p.focus_changed.connect(_on_focus_changed)
	p.interacted_with.connect(_on_interacted)
	rhythm_ring.bind(p.gather, p.camera)
	p.gather.session_started.connect(func(_g, _t): _refresh_hint())
	p.gather.session_ended.connect(_refresh_hint)
	p.gather.hit_landed.connect(func(_g, _s): _refresh_hint.call_deferred())
	p.gather.tool_missing.connect(_on_tool_missing)
	p.gather.tool_named.connect(_on_tool_named)


## Mücadele: dünyaya bağlı işaretler + duraklatma menüsünde iki kişilik ve düşman ayarı.
func _build_combat_ui() -> void:
	combat = CombatOverlay.new()
	combat.name = "CombatOverlay"
	root.add_child(combat)
	root.move_child(combat, 0)
	var vbox: VBoxContainer = pause_menu.get_node("Panel/VBox")
	coop_button = Button.new()
	coop_button.name = "CoopButton"
	vbox.add_child(coop_button)
	vbox.move_child(coop_button, rhythm_button.get_index() + 1)
	coop_button.pressed.connect(_on_coop_pressed)
	enemies_button = Button.new()
	enemies_button.name = "EnemiesButton"
	vbox.add_child(enemies_button)
	vbox.move_child(enemies_button, coop_button.get_index() + 1)
	enemies_button.pressed.connect(func(): AudioManager.play_ui("ui_click"); GameState.set_enemies_enabled(not GameState.enemies_enabled))
	GameState.enemies_changed.connect(func(_e): _refresh_buttons())


## Çevrimiçi iki kişilik: [Oyun aç] ya da [adres][Katıl]; altında durum satırı.
func _build_net_ui(vbox: VBoxContainer) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	vbox.add_child(gap)
	var title := Label.new()
	title.name = "NetTitle"
	title.text = "NET_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)
	net_host_button = Button.new()
	net_host_button.name = "NetHostButton"
	vbox.add_child(net_host_button)
	net_host_button.pressed.connect(_on_net_host_pressed)
	net_join_row = HBoxContainer.new()
	net_join_row.add_theme_constant_override("separation", 8)
	vbox.add_child(net_join_row)
	net_address = LineEdit.new()
	net_address.name = "NetAddress"
	net_address.custom_minimum_size = Vector2(230, 0)
	net_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	net_address.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	net_address.text_changed.connect(func(t: String):
		# Oda kodu büyük harfle görünsün
		if Net.is_room_code(t) and t != t.to_upper():
			var c := net_address.caret_column
			net_address.text = t.to_upper()
			net_address.caret_column = c)
	net_address.add_theme_font_size_override("font_size", 22)
	for st in ["normal", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.PAPER.lightened(0.3)
		sb.border_color = Palette.SUNSET if st == "focus" else Color(Palette.EARTH, 0.55)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		net_address.add_theme_stylebox_override(st, sb)
	net_address.add_theme_color_override("font_color", Palette.EARTH.darkened(0.45))
	net_address.add_theme_color_override("font_placeholder_color", Color(Palette.EARTH, 0.6))
	net_address.add_theme_color_override("caret_color", Palette.SUNSET)
	net_address.text = str(SaveSystem.data.get("settings", {}).get("net_address", ""))
	net_address.text_submitted.connect(func(_t): _on_net_join_pressed())
	net_join_row.add_child(net_address)
	net_join_button = Button.new()
	net_join_button.name = "NetJoinButton"
	net_join_row.add_child(net_join_button)
	net_join_button.pressed.connect(_on_net_join_pressed)
	net_status = Label.new()
	net_status.name = "NetStatus"
	net_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	net_status.custom_minimum_size = Vector2(300, 0)
	net_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	net_status.add_theme_font_size_override("font_size", 17)
	net_status.add_theme_color_override("font_color", Palette.EARTH.darkened(0.2))
	vbox.add_child(net_status)
	# Oda kodu büyük harflerle: arkadaşa okunacak ya da yazılacak.
	net_code = Label.new()
	net_code.name = "NetCode"
	net_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	net_code.add_theme_font_size_override("font_size", 46)
	net_code.add_theme_color_override("font_color", Palette.SUNSET.darkened(0.25))
	net_code.visible = false
	vbox.add_child(net_code)
	net_steam_button = Button.new()
	net_steam_button.name = "NetSteamButton"
	net_steam_button.visible = false
	vbox.add_child(net_steam_button)
	net_steam_button.pressed.connect(func():
		AudioManager.play_ui("ui_click")
		SteamLobby.invite())
	SteamLobby.changed.connect(_refresh_net)
	Net.status_changed.connect(func(_s): _refresh_net())
	Net.partner_joined.connect(_refresh_net)
	Net.partner_left.connect(_refresh_net)
	Net.failed.connect(_on_net_failed)


func _on_net_host_pressed() -> void:
	AudioManager.play_ui("ui_click")
	if Net.active():
		Net.leave()
	else:
		if coop != null and coop.is_active():
			coop.leave()
		Net.host()
	_refresh_net()


func _on_net_join_pressed() -> void:
	AudioManager.play_ui("ui_click")
	if Net.active():
		return
	if coop != null and coop.is_active():
		coop.leave()
	SaveSystem.data["settings"]["net_address"] = net_address.text.strip_edges()
	Net.join(net_address.text)
	_refresh_net()


func _on_net_failed(reason: String) -> void:
	var key: String = {"port": "MSG_NET_PORT", "lost": "MSG_NET_LOST", "version": "MSG_NET_VERSION", "address": "MSG_NET_ADDRESS", "relay": "MSG_NET_RELAY", "no_room": "MSG_NET_NO_ROOM", "full": "MSG_NET_FULL"}.get(reason, "MSG_NET_FAILED")
	show_toast(key, 5.0)
	_refresh_net()
	if net_status != null:
		net_status.text = tr(key)


func _refresh_net() -> void:
	if net_host_button == null:
		return
	net_host_button.text = tr("NET_LEAVE") if Net.active() else tr("NET_HOST")
	net_join_button.text = tr("NET_JOIN")
	net_address.placeholder_text = tr("NET_ADDRESS_HINT")
	net_join_row.visible = not Net.active()
	match Net.status:
		Net.Status.HOSTING:
			if Net.has_partner():
				net_status.text = tr("NET_ONLINE")
			elif Net.host_code != "":
				net_status.text = tr("NET_WAITING_CODE_SHORT")
			else:
				net_status.text = tr("NET_WAITING") % Net.host_address
		Net.Status.CONNECTING, Net.Status.LOADING:
			net_status.text = tr("NET_CONNECTING")
		Net.Status.ONLINE:
			net_status.text = tr("NET_ONLINE")
		_:
			net_status.text = tr("NET_HELP")
	net_code.visible = Net.status == Net.Status.HOSTING and Net.host_code != "" and not Net.has_partner()
	var spaced := ""
	for ch in Net.host_code:
		spaced += ch + " "
	net_code.text = spaced.strip_edges() if net_code.visible else ""
	net_steam_button.text = tr("NET_STEAM_INVITE")
	net_steam_button.visible = SteamLobby.can_invite()
	if coop_button != null:
		coop_button.disabled = Net.active()
	_fit_pause_panel.call_deferred()


func bind_coop(c: CoopManager) -> void:
	coop = c
	c.waiting_changed.connect(_on_coop_waiting)
	c.joined.connect(func(_p): _refresh_buttons(); hint_card.flash(["two_players", "check"], 2.5))
	c.left.connect(_refresh_buttons)


func _on_coop_pressed() -> void:
	AudioManager.play_ui("ui_click")
	if coop == null:
		return
	if coop.is_active():
		coop.leave()
		_refresh_buttons()
		return
	set_paused(false)
	coop.start_waiting()


## Katılma beklenirken metinsiz kart: [iki oyuncu] [gamepad A].
func _on_coop_waiting(waiting: bool) -> void:
	if waiting:
		hint_card.flash(["two_players", "arrow", "pad_a"], CoopManager.WAIT_SECONDS)
	else:
		hint_card.flash([], 0.01)
	_refresh_buttons()


func add_player(p: Player) -> void:
	players.append(p)
	combat.players = players
	var ring := RhythmRing.new()
	ring.name = "RhythmRing%d" % p.index
	add_child(ring)
	move_child(ring, 1)
	ring.bind(p.gather, player.camera)
	_extra_rings[p] = ring
	p.gather.tool_missing.connect(_on_tool_missing)
	p.gather.tool_named.connect(_on_tool_named)
	p.interacted_with.connect(_on_interacted)


func remove_player(p: Player) -> void:
	players.erase(p)
	combat.players = players
	var ring: Node = _extra_rings.get(p)
	if ring != null:
		ring.queue_free()
	_extra_rings.erase(p)


func _set_players_input(enabled: bool) -> void:
	for p in players:
		if is_instance_valid(p):
			p.input_enabled = enabled
			if not enabled:
				p.gather.stop()


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
	quest_marker = QuestMarker.new()
	quest_marker.name = "QuestMarker"
	root.add_child(quest_marker)
	root.move_child(quest_marker, 0)
	tool_belt = ToolBelt.new()
	tool_belt.name = "ToolBelt"
	root.add_child(tool_belt)
	tool_belt.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tool_belt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tool_belt.alignment = BoxContainer.ALIGNMENT_END
	tool_belt.offset_right = -6.0
	tool_belt.offset_left = -6.0
	tool_belt.offset_top = 80.0
	root.move_child(tool_belt, quest_panel.get_index())
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
	_set_players_input(false)
	hint_panel.visible = false
	return true


func modal_open() -> bool:
	return workshop_panel.is_open or repair_panel.is_open


## Başarım kartı, onarım mesajının ardından gelsin diye biraz bekler.
func _on_achievement(id: String) -> void:
	var text := "%s: %s" % [tr("ACHIEVEMENT_UNLOCKED"), tr(id)]
	get_tree().create_timer(4.2).timeout.connect(show_toast.bind(text, 3.5))


## Eşya hafızası: alet 50 kullanımda isim kazanır.
func _on_tool_named(t: ToolItem) -> void:
	AudioManager.play_sfx("tool_named")
	show_toast(tr("MSG_TOOL_NAMED") % t.display_name(), 4.5)
	hint_card.flash([t.kind, "arrow", "check"], 2.5)


func _on_tool_missing(kind: String, _g: Gatherable) -> void:
	hint_card.flash([kind, "arrow", "workshop"], 3.2)
	AudioManager.play_ui("ui_click")


func toggle_inventory() -> void:
	if inventory_panel.is_open:
		inventory_panel.close_panel()
		return
	AudioManager.play_ui("inventory_open")
	InputManager.release_mouse()
	_set_players_input(false)
	inventory_panel.open_panel()


func _on_inventory_closed() -> void:
	AudioManager.play_ui("panel_close")
	_set_players_input(true)
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
	hint_panel.visible = _focus != null and not menu_open
	if _focus:
		hint_label.text = _focus.hint_text()
	hint_glyph.refresh()


func _refresh_texts() -> void:
	_refresh_hint()
	_refresh_buttons()


func _refresh_buttons() -> void:
	_refresh_net()
	quality_button.text = "%s: %s" % [tr("QUALITY"), tr(GameState.quality_name_key())]
	language_button.text = "%s: %s" % [tr("LANGUAGE"), "Türkçe" if GameState.current_locale() == "tr" else "English"]
	touch_button.text = tr("TOUCH_PREVIEW_ON") if InputManager.touch_preview else tr("TOUCH_PREVIEW_OFF")
	rhythm_button.text = "%s: %s" % [tr("RHYTHM_HITS"), tr("ON") if GameState.rhythm_hits else tr("OFF")]
	if enemies_button != null:
		enemies_button.text = "%s: %s" % [tr("ENEMIES"), tr("ON") if GameState.enemies_enabled else tr("OFF")]
	if coop_button != null:
		if coop != null and coop.is_active():
			coop_button.text = tr("COOP_LEAVE")
		elif coop != null and coop.waiting:
			coop_button.text = tr("COOP_WAITING")
		else:
			coop_button.text = tr("COOP_JOIN")


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
	menu_open = paused
	# Çevrimiçi oyunda dünya durmaz (arkadaş oynamaya devam eder); yalnızca karakter durur.
	get_tree().paused = paused and not Net.active()
	if Net.active():
		_set_players_input(not paused)
	pause_menu.visible = paused
	AudioManager.play_ui("panel_open" if paused else "panel_close")
	if paused:
		_fit_pause_panel()
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
		set_paused(not menu_open)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quest_log") and not menu_open:
		toggle_quest_log()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and not menu_open:
		toggle_inventory()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var free := not menu_open and not modal_open() and not inventory_panel.is_open
	look_hint.visible = InputManager.is_pointer_mode() and not InputManager.mouse_looked and free
	# İmleç bir hedefin üstündeyse "etkileşilebilir" imlecine geç.
	var hover := free and player != null and player.hovered != null
	if hover != _hover_cursor:
		_hover_cursor = hover
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hover else Input.CURSOR_ARROW)
	if debug_label.visible:
		debug_label.text = "FPS %d  |  draw %d  |  %s  |  %s" % [
			Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			tr(GameState.quality_name_key()),
			["KB/M", "Gamepad", "Touch"][InputManager.device],
		]
