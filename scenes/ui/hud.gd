extends CanvasLayer
## Oyun içi arayüz: aktif görev (sağ üst), etkileşim ipucu (alt orta), kısa mesajlar,
## duraklatma menüsü ve geliştirici bilgisi (FPS / draw call / kalite).

@onready var quest_text: Label = %QuestText
@onready var hint_panel: Control = %HintPanel
@onready var hint_label: Label = %HintLabel
@onready var hint_glyph: GlyphBadge = %HintGlyph
@onready var toast_panel: Control = %ToastPanel
@onready var toast_label: Label = %ToastLabel
@onready var debug_label: Label = %DebugLabel
@onready var look_hint: Label = %LookHint
@onready var pause_menu: Control = %PauseMenu
@onready var resume_button: Button = %ResumeButton
@onready var quality_button: Button = %QualityButton
@onready var language_button: Button = %LanguageButton
@onready var touch_button: Button = %TouchPreviewButton

var player: Player
var _toast_tween: Tween
var _focus: Interactable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hint_panel.visible = false
	toast_panel.modulate.a = 0.0
	pause_menu.visible = false
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
	_on_quest_changed(GameState.current_quest_key)
	_refresh_buttons()


func bind_player(p: Player) -> void:
	player = p
	p.focus_changed.connect(_on_focus_changed)
	p.interacted_with.connect(_on_interacted)


func _on_quest_changed(key: String) -> void:
	quest_text.text = key


func _on_focus_changed(target: Interactable) -> void:
	_focus = target
	_refresh_hint()


func _refresh_hint() -> void:
	hint_panel.visible = _focus != null and not get_tree().paused
	if _focus:
		hint_label.text = "%s: %s" % [tr(_focus.action_key), tr(_focus.display_name_key)]
	hint_glyph.refresh()


func _refresh_texts() -> void:
	_refresh_hint()
	_refresh_buttons()


func _refresh_buttons() -> void:
	quality_button.text = "%s: %s" % [tr("QUALITY"), tr(GameState.quality_name_key())]
	language_button.text = "%s: %s" % [tr("LANGUAGE"), "Türkçe" if GameState.current_locale() == "tr" else "English"]
	touch_button.text = tr("TOUCH_PREVIEW_ON") if InputManager.touch_preview else tr("TOUCH_PREVIEW_OFF")


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
	if event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and not get_tree().paused:
		AudioManager.play_ui("inventory_open")
		show_toast("MSG_INVENTORY_SOON", 2.0)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	look_hint.visible = InputManager.device == InputManager.Device.KEYBOARD_MOUSE \
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused
	if debug_label.visible:
		debug_label.text = "FPS %d  |  draw %d  |  %s  |  %s" % [
			Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			tr(GameState.quality_name_key()),
			["KB/M", "Gamepad", "Touch"][InputManager.device],
		]
