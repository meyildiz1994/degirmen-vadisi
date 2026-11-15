extends Node
## Platforma özel her şey burada toplanır. Oyun mantığı yalnızca bu arayüzü çağırır.
## Steam (GodotSteam) yoksa (mobil, editör, eklenti kurulmamış) sessizce devre dışı kalır.
## Aşama 6'da başarımlar ve Steam Cloud tam bağlanacak.

signal achievement_unlocked(id: String)

const STEAM_APP_ID := 480  ## TODO: gerçek App ID (480 = Spacewar test uygulaması)

var steam: Object = null
var steam_ready := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_steam()


func _init_steam() -> void:
	if OS.has_feature("mobile") or not Engine.has_singleton("Steam"):
		return
	steam = Engine.get_singleton("Steam")
	if not steam.has_method("steamInitEx"):
		return
	var result = steam.call("steamInitEx", STEAM_APP_ID, true)
	steam_ready = typeof(result) == TYPE_DICTIONARY and int(result.get("status", 1)) == 0
	if not steam_ready:
		push_warning("PlatformServices: Steam başlatılamadı, devre dışı.")


func is_steam_available() -> bool:
	return steam_ready


func platform_name() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("ios"):
		return "ios"
	return "steam" if steam_ready else "desktop"


# --- Başarımlar ----------------------------------------------------------
func unlock_achievement(id: String) -> void:
	achievement_unlocked.emit(id)
	if steam_ready:
		steam.call("setAchievement", id)
		steam.call("storeStats")
	elif OS.has_feature("android"):
		play_games_unlock(id)
	elif OS.has_feature("ios"):
		game_center_report(id)


# --- Bulut kayıt -----------------------------------------------------------
func on_save_written(path: String) -> void:
	if steam_ready and steam.has_method("fileWrite"):
		var bytes := FileAccess.get_file_as_bytes(path)
		steam.call("fileWrite", path.get_file(), bytes, bytes.size())


# --- Mobil (boş arayüz; ileride eklentilerle doldurulacak) -----------------
func play_games_sign_in() -> void:
	pass

func play_games_unlock(_id: String) -> void:
	pass

func game_center_authenticate() -> void:
	pass

func game_center_report(_id: String) -> void:
	pass


# --- Dokunsal geri bildirim -------------------------------------------------
func vibrate(ms: int = 30) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func _process(_delta: float) -> void:
	if steam_ready:
		steam.call("run_callbacks")
