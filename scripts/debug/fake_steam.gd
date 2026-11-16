class_name FakeSteam
extends Object
## Geliştirici aracı: GodotSteam'in lobi kısmını taklit eder (test ve ekran görüntüsü).
## Aynı nesne hem ev sahibi hem katılan gibi davranabilir; lobi verisi bellekte tutulur.

signal lobby_created(result: int, lobby_id: int)
signal lobby_joined(lobby_id: int, permissions: int, locked: bool, response: int)
signal join_requested(lobby_id: int, friend_id: int)
signal lobby_data_update(success: int, lobby_id: int, member_id: int)
signal join_game_requested(user: int, connect: String)

var calls: Array = []
var data := {}
var next_id := 76561190000000001


func createLobby(_type: int, _size: int) -> void:
	calls.append("createLobby")
	var id := next_id
	next_id += 1
	data[id] = {}
	lobby_created.emit.call_deferred(1, id)

func setLobbyData(id: int, key: String, value: String) -> bool:
	calls.append("setLobbyData")
	data.get_or_add(id, {})[key] = value
	return true

func getLobbyData(id: int, key: String) -> String:
	return str(data.get(id, {}).get(key, ""))

func setLobbyJoinable(_id: int, _ok: bool) -> bool:
	return true

func joinLobby(id: int) -> void:
	calls.append("joinLobby")
	lobby_joined.emit.call_deferred(id, 0, false, 1 if data.has(id) else 2)

func leaveLobby(_id: int) -> void:
	calls.append("leaveLobby")

func activateGameOverlayInviteDialog(_id: int) -> void:
	calls.append("invite")

func setRichPresence(_k: String, _v: String) -> bool:
	return true

func clearRichPresence() -> void:
	pass
