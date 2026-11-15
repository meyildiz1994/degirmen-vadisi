extends Node
## user:// klasörüne JSON kayıt: ayarlar, oyuncu konumu, heybe, dünyadaki kaynakların
## durumu (kesilen ağaçlar, dikilen fidanlar), onarımlar, aletlerin geçmişi (heybede, alet
## başına), açılan başarımlar. 90 saniyede bir, onarım bitince, kapanışta ve mobilde arka
## plana atılınca kaydeder.

signal saved
signal loaded

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_SECONDS := 90.0
const PERSIST_GROUP := &"persist"  ## save_state(dict) / load_state(dict) uygulayan düğümler

var data: Dictionary = {}
var autosave_enabled := true
## Testler ve ekran görüntüsü aracı oyuncunun kaydını okumaz/yazmaz.
var persistent := true
var _since_save := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	data = _default_data()
	persistent = not _is_tool_run()
	load_game()
	# AudioManager henüz hazır olmayabilir; ayarları bir kare sonra uygula.
	apply_settings.call_deferred()


func _default_data() -> Dictionary:
	var lang := OS.get_locale_language()
	return {
		"version": SAVE_VERSION,
		"settings": {
			"quality": GameState.quality,
			"locale": "tr" if lang == "tr" else "en",
			"volume": {"Music": 0.8, "SFX": 0.9, "Ambience": 0.9, "UI": 0.8},
			"rhythm_hits": true,
		},
		"player": {},
		"inventory": {},
		"tutorial_step": 0,
		"world": {},
		"repaired": [],
		"achievements": [],
	}


static func _is_tool_run() -> bool:
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tests/"):
			return true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot"):
			return true
	return false


func load_game() -> bool:
	if not persistent or not FileAccess.file_exists(SAVE_PATH):
		return false
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveSystem: kayıt dosyası okunamadı, varsayılanlar kullanılıyor.")
		return false
	_merge(data, parsed)
	loaded.emit()
	return true


func _process(delta: float) -> void:
	if not autosave_enabled or get_tree().paused or get_tree().current_scene == null:
		return
	_since_save += delta
	if _since_save >= AUTOSAVE_SECONDS:
		save_game()


func save_game() -> void:
	_since_save = 0.0
	for node in get_tree().get_nodes_in_group(PERSIST_GROUP):
		if node.has_method("save_state"):
			node.save_state(data)
	data["settings"]["quality"] = GameState.quality
	data["settings"]["locale"] = GameState.current_locale()
	data["settings"]["rhythm_hits"] = GameState.rhythm_hits
	if not persistent:
		saved.emit()
		return
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSystem: yazılamadı (%s)" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(SAVE_PATH))
	PlatformServices.on_save_written(SAVE_PATH)
	saved.emit()


func restore_persisted_nodes() -> void:
	for node in get_tree().get_nodes_in_group(PERSIST_GROUP):
		if node.has_method("load_state"):
			node.load_state(data)


func apply_settings() -> void:
	var s: Dictionary = data["settings"]
	GameState.set_locale(str(s.get("locale", "tr")))
	GameState.set_quality(int(s.get("quality", GameState.quality)))
	GameState.set_rhythm_hits(bool(s.get("rhythm_hits", true)))
	var vol: Dictionary = s.get("volume", {})
	for bus in vol:
		AudioManager.set_bus_volume(bus, float(vol[bus]))


func set_volume_setting(bus: String, linear: float) -> void:
	data["settings"]["volume"][bus] = linear
	AudioManager.set_bus_volume(bus, linear)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			save_game()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if GameState.is_mobile:
				save_game()


static func _merge(into: Dictionary, from: Dictionary) -> void:
	for k in from:
		if into.has(k) and typeof(into[k]) == TYPE_DICTIONARY and typeof(from[k]) == TYPE_DICTIONARY:
			_merge(into[k], from[k])
		else:
			into[k] = from[k]
