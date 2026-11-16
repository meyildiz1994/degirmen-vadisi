class_name RelayPeer
extends MultiplayerPeerExtension
## Oda kodu aracısı üzerinden iki oyunculu bağlantı (WebSocket). Port açmak gerekmez;
## PC ve mobilde aynı çalışır. Ev sahibi "host" der ve kod alır (kimliği 1), arkadaşı
## kodla "join" der (kimliği 2). Oyun paketleri aracıdan olduğu gibi geçer:
##   [aktarım biçimi (1 bayt)][kanal (1 bayt)][veri]
## WebSocket zaten sıralı ve güvenilir olduğundan tüm biçimler güvenilir taşınır.

signal room_ready(code: String)
signal relay_error(reason: String)

const PROTOCOL := 1

var ws := WebSocketPeer.new()
var code := ""
var hosting := false
var _id := 0
var _other := 0
var _status := CONNECTION_DISCONNECTED
var _target := 0
var _channel := 0
var _mode := TRANSFER_MODE_RELIABLE
var _incoming: Array = []          # [veri, kimden, kanal, biçim]
var _handshake_sent := false
var _join_code := ""


func _init() -> void:
	ws.inbound_buffer_size = 4 * 1024 * 1024
	ws.outbound_buffer_size = 4 * 1024 * 1024
	ws.max_queued_packets = 4096


func start_host(url: String) -> Error:
	hosting = true
	return _open(url)


func start_join(url: String, room_code: String) -> Error:
	hosting = false
	_join_code = room_code.strip_edges().to_upper()
	return _open(url)


func _open(url: String) -> Error:
	var err := ws.connect_to_url(url)
	if err == OK:
		_status = CONNECTION_CONNECTING
	return err


# --- MultiplayerPeerExtension ---------------------------------------------------------
func _poll() -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _handshake_sent:
			_handshake_sent = true
			var hello := {"op": "host", "v": PROTOCOL} if hosting else {"op": "join", "code": _join_code, "v": PROTOCOL}
			ws.send_text(JSON.stringify(hello))
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if ws.was_string_packet():
				_on_control(pkt.get_string_from_utf8())
			elif pkt.size() >= 2 and _other != 0:
				_incoming.append([pkt.slice(2), _other, pkt[1], pkt[0]])
	elif st == WebSocketPeer.STATE_CLOSED:
		if _status != CONNECTION_DISCONNECTED:
			var was := _status
			_status = CONNECTION_DISCONNECTED
			if _other != 0:
				var o := _other
				_other = 0
				peer_disconnected.emit(o)
			elif was == CONNECTION_CONNECTING:
				relay_error.emit("connect")


func _on_control(text: String) -> void:
	var m = JSON.parse_string(text)
	if typeof(m) != TYPE_DICTIONARY:
		return
	match str(m.get("op", "")):
		"room":
			code = str(m.get("code", ""))
			_id = 1
			_status = CONNECTION_CONNECTED
			room_ready.emit(code)
		"peer":
			_other = int(m.get("id", 2))
			peer_connected.emit(_other)
		"left":
			var o := _other
			_other = 0
			if o != 0:
				peer_disconnected.emit(o)
		"joined":
			_id = int(m.get("id", 2))
			_other = 1
			_status = CONNECTION_CONNECTED
			peer_connected.emit(1)
		"closed":
			ws.close()
		"error":
			relay_error.emit(str(m.get("reason", "error")))
			ws.close()


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return 1 << 22


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front()[0]


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN or _other == 0:
		return ERR_UNCONFIGURED
	var out := PackedByteArray([_mode, _channel])
	out.append_array(buffer)
	return ws.send(out, WebSocketPeer.WRITE_MODE_BINARY)


func _get_packet_channel() -> int:
	return int(_incoming[0][2]) if not _incoming.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return int(_incoming[0][3]) if not _incoming.is_empty() else TRANSFER_MODE_RELIABLE


func _get_packet_peer() -> int:
	return int(_incoming[0][1]) if not _incoming.is_empty() else 0


func _set_transfer_channel(p_channel: int) -> void:
	_channel = p_channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(p_mode: TransferMode) -> void:
	_mode = p_mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_target_peer(p_peer: int) -> void:
	_target = p_peer


func _get_unique_id() -> int:
	return 1 if hosting else 2


func _get_connection_status() -> ConnectionStatus:
	return _status


func _is_server() -> bool:
	return hosting


func _is_server_relay_supported() -> bool:
	return false


func _close() -> void:
	ws.close()
	_status = CONNECTION_DISCONNECTED
	_other = 0


func _disconnect_peer(_p_peer: int, _p_force: bool) -> void:
	pass  # tek arkadaş: aracı ikinciyi zaten reddeder


func _set_refuse_new_connections(_p_enable: bool) -> void:
	pass


func _is_refusing_new_connections() -> bool:
	return false
