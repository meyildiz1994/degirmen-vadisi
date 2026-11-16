extends Node
## Steam arkadaş daveti. Ağ trafiği yine oda kodu aracısından (relay) geçer; Steam
## yalnızca oda kodunu taşır:
##   Ev sahibi oyun açar -> oda kodu gelir -> yalnız-arkadaşlar lobisi kurulur, kod
##   lobi verisine yazılır -> "Steam'den davet et" Steam'in davet penceresini açar.
##   Arkadaş daveti kabul eder (oyun kapalıysa Steam oyunu +connect_lobby ile açar)
##   -> lobiye girer -> kodu okur -> Net.join(kod).
## GodotSteam kurulu değilse ya da Steam açık değilse (mobil, editör) hiçbir şey yapmaz.

signal changed

const LOBBY_FRIENDS_ONLY := 1
const LOBBY_SIZE := 2
const CODE_KEY := "degirmen_code"

var steam: Object = null
var lobby_id := 0
var _joining_lobby := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if PlatformServices.is_steam_available():
		bind(PlatformServices.steam)
	Net.status_changed.connect(_on_net_status)


## Steam nesnesini bağla (testlerde sahte bir nesne verilebilir).
func bind(s: Object) -> void:
	steam = s
	for pair in [["lobby_created", _on_lobby_created], ["lobby_joined", _on_lobby_joined],
			["join_requested", _on_join_requested], ["lobby_data_update", _on_lobby_data_update],
			["join_game_requested", _on_join_game_requested]]:
		if steam.has_signal(pair[0]) and not steam.is_connected(pair[0], pair[1]):
			steam.connect(pair[0], pair[1])
	_check_command_line.call_deferred()


func available() -> bool:
	return steam != null


## Menüdeki davet düğmesi görünsün mü: Steam var, oda kodlu oyun açık, arkadaş yok.
func can_invite() -> bool:
	return available() and lobby_id != 0 and Net.status == Net.Status.HOSTING \
		and Net.host_code != "" and not Net.has_partner()


func invite() -> void:
	if can_invite():
		steam.call("activateGameOverlayInviteDialog", lobby_id)


# --- Ev sahibi ---------------------------------------------------------------
func _on_net_status(_s: int) -> void:
	if not available():
		return
	if Net.status == Net.Status.HOSTING and Net.host_code != "" and lobby_id == 0:
		steam.call("createLobby", LOBBY_FRIENDS_ONLY, LOBBY_SIZE)
	elif Net.status == Net.Status.OFFLINE:
		_leave_lobby()
	changed.emit()


func _on_lobby_created(result: int, id: int) -> void:
	if result != 1 or id == 0:  # 1 = k_EResultOK
		Net._log("steam lobby create failed %d" % result)
		return
	if not (Net.status == Net.Status.HOSTING and Net.host_code != ""):
		steam.call("leaveLobby", id)  # bu arada oyun kapandıysa
		return
	lobby_id = id
	steam.call("setLobbyData", id, CODE_KEY, Net.host_code)
	steam.call("setLobbyJoinable", id, true)
	# Arkadaş listesinden "Oyuna katıl" da çalışsın.
	steam.call("setRichPresence", "connect", "+connect_lobby %d" % id)
	Net._log("steam lobby %d code %s" % [id, Net.host_code])
	changed.emit()


func _leave_lobby() -> void:
	if lobby_id != 0:
		steam.call("leaveLobby", lobby_id)
		lobby_id = 0
	_joining_lobby = 0
	if available():
		steam.call("clearRichPresence")


# --- Katılan -----------------------------------------------------------------
func _on_join_requested(id: int, _friend: int) -> void:
	join_lobby(id)


## Arkadaş listesinde "Oyuna katıl" (rich presence "connect" dizesi).
func _on_join_game_requested(_friend: int, connect: String) -> void:
	var parts := connect.split(" ", false)
	var i := parts.find("+connect_lobby")
	if i >= 0 and i + 1 < parts.size() and parts[i + 1].is_valid_int():
		join_lobby(parts[i + 1].to_int())


func join_lobby(id: int) -> void:
	if id == 0 or Net.active():
		return
	_joining_lobby = id
	steam.call("joinLobby", id)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if id != _joining_lobby:
		return
	if response != 1:  # 1 = k_EChatRoomEnterResponseSuccess
		_joining_lobby = 0
		Net.failed.emit("no_room")
		return
	_try_code(id)


func _on_lobby_data_update(_success: int, id: int, _member: int) -> void:
	if id == _joining_lobby:
		_try_code(id)


func _try_code(id: int) -> void:
	var code := str(steam.call("getLobbyData", id, CODE_KEY))
	if not Net.is_room_code(code):
		return  # veri henüz gelmedi; lobby_data_update bekleniyor
	_joining_lobby = 0
	steam.call("leaveLobby", id)  # lobi yalnız kodu taşır; bağlantı aracıdan
	Net._log("steam lobby %d -> code %s" % [id, code])
	Net.join(code)


## Oyun kapalıyken davet kabul edilirse Steam oyunu "+connect_lobby <id>" ile açar.
func _check_command_line() -> void:
	var args := OS.get_cmdline_args()
	var i := args.find("+connect_lobby")
	if i >= 0 and i + 1 < args.size() and args[i + 1].is_valid_int():
		join_lobby(args[i + 1].to_int())
