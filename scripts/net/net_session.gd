extends Node
## Çevrimiçi iki kişilik oyun (ENet, UDP). Ev sahibi vadinin sahibidir: düşman dalgaları
## ve kalıcı kayıt onda yürür. Katılan oyuncu bağlanınca ev sahibinin kaydını alır, vadiyi
## o kayıtla yeniden kurar ve kendi karakterini oynar (kendi kaydına dokunulmaz; ayrılınca
## kendi vadisine döner). Sonra iki taraf birbirine şunları yollar:
##   - karakter özeti (konum, yön, elindeki alet, can, baygınlık): saniyede 15 kez
##   - ortak heybe: değiştikçe
##   - toplanan kaynaklar, vuruşlar, dikilen fidanlar, yapıların durumu: olay olarak
## Düşmanları yalnızca ev sahibi yönetir; katılana saniyede 10 kez özet yollar,
## katılanın vuruşları ev sahibine iletilir, ev sahibindeki düşmanın katılanın karakterine
## verdiği hasar katılana iletilir.
## Bağlantı: aynı ağda (Wi-Fi) ev sahibinin yerel adresiyle; farklı ağlarda ev sahibinin
## modeminde UDP 24680 açık olmalı (ileride Steam davetiyle bu gerekmeyecek).

signal status_changed(status: int)
signal partner_joined
signal partner_left
signal failed(reason: String)

enum Status { OFFLINE, HOSTING, CONNECTING, LOADING, ONLINE }
enum Role { NONE, HOST, GUEST }

const PORT := 24680
const PROTOCOL := 1
const PLAYER_RATE := 1.0 / 15.0
const ENEMY_RATE := 0.1
const SITE_RATE := 0.25
const INV_RATE := 0.15
const CONNECT_TIMEOUT := 10.0
## Ücretsiz barındırmada uyuyan aracı sunucu ilk bağlantıda uyanana kadar bekle.
const RELAY_TIMEOUT := 90.0  # Render ücretsiz sunucu uykudan ~1 dk.da uyanır
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var status := Status.OFFLINE
var role := Role.NONE
var peer_id := 0
var host_address := ""
## Oda kodu (aracı üzerinden açılınca), arkadaş bunu yazar.
var host_code := ""
var world: Node3D
var local_player: Player
var remote: Player
var _own_data: Dictionary = {}
var _applying := false
var _player_t := 0.0
var _enemy_t := 0.0
var _site_t := 0.0
var _inv_t := 0.0
var _inv_dirty := false
var _sites_dirty := {}
var _connect_t := 0.0
## Geliştirici aracı / test: bir kez otomatik katılım (sahne yeniden kurulunca tekrarlamaz).
var auto_join_done := false
## Vadi yeniden kurulunca gösterilecek mesaj (ör. bağlantı koptu).
var _pending_toast := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return role == Role.HOST


func is_guest() -> bool:
	return role == Role.GUEST


func active() -> bool:
	return role != Role.NONE


func has_partner() -> bool:
	return remote != null and is_instance_valid(remote)


func _log(msg: String) -> void:
	if OS.is_debug_build():
		print("[Net] ", msg)


func _set_status(s: int) -> void:
	_log("status %s -> %s" % [Status.keys()[status], Status.keys()[s]])
	status = s
	status_changed.emit(s)


# --- Bağlantı ------------------------------------------------------------------------
## Oyun aç: oda kodu aracısı ayarlıysa oradan (port açmadan, her yerden), değilse ya da
## aracıya ulaşılamazsa aynı ağ için doğrudan (ENet).
func host() -> bool:
	if active():
		return false
	host_code = ""
	host_address = local_address()
	var url := relay_url()
	if url != "":
		var rp := RelayPeer.new()
		if rp.start_host(url) == OK:
			rp.room_ready.connect(_on_room_ready)
			rp.relay_error.connect(_on_relay_error)
			multiplayer.multiplayer_peer = rp
			role = Role.HOST
			_connect_t = RELAY_TIMEOUT
			_set_status(Status.CONNECTING)
			if world != null:
				attach(world)
			return true
	return _host_lan()


func _host_lan() -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 1)
	if err != OK:
		failed.emit("port")
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	host_code = ""
	_set_status(Status.HOSTING)
	if world != null:
		attach(world)
	return true


func _on_room_ready(code: String) -> void:
	host_code = code
	_log("room %s" % code)
	_set_status(Status.HOSTING)


func _on_relay_error(reason: String) -> void:
	_log("relay error %s" % reason)
	if is_host() and status == Status.CONNECTING:
		# Aracıya ulaşılamadı: aynı ağ için doğrudan açmayı dene.
		_close()
		failed.emit("relay")
		_host_lan()
	elif is_guest() and status in [Status.CONNECTING, Status.LOADING]:
		_close()
		failed.emit("no_room" if reason == "no_room" else ("full" if reason == "full" else "connect"))


## Katıl: 6 harfli oda kodu ya da aynı ağdaki adres (ör. 192.168.1.24).
func join(address: String) -> bool:
	if active():
		return false
	address = address.strip_edges()
	if address == "":
		failed.emit("address")
		return false
	if is_room_code(address):
		var url := relay_url()
		if url == "":
			failed.emit("relay")
			return false
		var rp := RelayPeer.new()
		if rp.start_join(url, address) != OK:
			failed.emit("connect")
			return false
		rp.relay_error.connect(_on_relay_error)
		multiplayer.multiplayer_peer = rp
		_connect_t = RELAY_TIMEOUT
	else:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_client(address, PORT)
		if err != OK:
			failed.emit("connect")
			return false
		multiplayer.multiplayer_peer = peer
	role = Role.GUEST
	if not is_room_code(address):
		_connect_t = CONNECT_TIMEOUT
	_set_status(Status.CONNECTING)
	return true


static func is_room_code(text: String) -> bool:
	var t := text.strip_edges().to_upper()
	if t.length() != 6:
		return false
	for ch in t:
		if ch < "A" or ch > "Z":
			return false
	return true


## Aracının adresi: komut satırı (--relay=...) ya da proje ayarı degirmen/net/relay_url.
static func relay_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--relay="):
			return a.substr(8)
	return str(ProjectSettings.get_setting("degirmen/net/relay_url", ""))


func leave() -> void:
	if not active():
		return
	var was_guest := is_guest() and status == Status.ONLINE
	_close()
	if was_guest:
		_return_home()


func _close() -> void:
	_drop_remote()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.NONE
	peer_id = 0
	host_code = ""
	_set_status(Status.OFFLINE)


## Katılan: kendi kaydına ve vadisine geri dön.
func _return_home() -> void:
	if not _own_data.is_empty():
		SaveSystem.data = _own_data
		_own_data = {}
	SaveSystem.persistent = not SaveSystem._is_tool_run()
	get_tree().paused = false
	get_tree().reload_current_scene()


## Aynı ağdaki arkadaşın yazacağı adres (ör. 192.168.1.24).
static func local_address() -> String:
	var best := ""
	for a: String in IP.get_local_addresses():
		if not a.contains(".") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
		if best == "":
			best = a
	return best


func _process(delta: float) -> void:
	if status == Status.CONNECTING:
		_connect_t -= delta
		if _connect_t <= 0.0:
			if is_host():
				_close()
				failed.emit("relay")
				_host_lan()
			else:
				_close()
				failed.emit("connect")
		return
	if not has_partner() or local_player == null or not is_instance_valid(local_player):
		return
	_player_t -= delta
	if _player_t <= 0.0:
		_player_t = PLAYER_RATE
		_rpc_player.rpc_id(peer_id, local_player.net_state())
	_inv_t -= delta
	if _inv_dirty and _inv_t <= 0.0:
		_inv_t = INV_RATE
		_inv_dirty = false
		_rpc_inventory.rpc_id(peer_id, GameState.inventory.to_dict())
	_site_t -= delta
	if not _sites_dirty.is_empty() and _site_t <= 0.0:
		_site_t = SITE_RATE
		for id in _sites_dirty:
			var site: RepairSite = _sites_dirty[id]
			_rpc_site.rpc_id(peer_id, id, site.state)
		_sites_dirty.clear()
	if is_host() and world.director != null:
		_enemy_t -= delta
		if _enemy_t <= 0.0:
			_enemy_t = ENEMY_RATE
			_rpc_enemies.rpc_id(peer_id, world.director.net_pack())


func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	if peer_id != 0:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	peer_id = id
	SaveSystem.save_game()
	_rpc_welcome.rpc_id(id, PROTOCOL, JSON.stringify(SaveSystem.data))


func _on_peer_disconnected(id: int) -> void:
	if is_host() and id == peer_id:
		peer_id = 0
		_drop_remote()
		_set_status(Status.HOSTING)


func _on_connected() -> void:
	peer_id = 1
	_set_status(Status.LOADING)


func _on_connection_failed() -> void:
	_close()
	failed.emit("connect")


func _on_server_disconnected() -> void:
	var was_online := status == Status.ONLINE
	_close()
	failed.emit("lost")
	if was_online:
		_pending_toast = "MSG_NET_LOST"
		_return_home()


# --- Dünyaya bağlanma ------------------------------------------------------------------
## Vadi sahnesi kurulunca çağrılır (her iki tarafta).
func attach(w: Node3D) -> void:
	world = w
	if _pending_toast != "":
		w.hud.show_toast.call_deferred(_pending_toast, 5.0)
		_pending_toast = ""
	if not active():
		return
	_log("attach %s as %s" % [w, Role.keys()[role]])
	local_player = w.player
	if not GameState.inventory.changed.is_connected(_on_inventory_changed):
		GameState.inventory.changed.connect(_on_inventory_changed)
	w.gather_world.resource_depleted.connect(func(g: Gatherable):
		if has_partner():
			send_event("res", [g.save_id, g.to_save(), local_player.global_position]))
	w.gather_world.sapling_planted.connect(func(kind: String, pos: Vector3):
		if has_partner():
			send_event("plant", [kind, pos]))
	local_player.gather.hit_landed.connect(func(g: Gatherable, sweet: bool):
		if has_partner():
			send_event("ghit", [g.save_id, sweet, local_player.global_position]))
	local_player.swung.connect(func(sweet: bool):
		if has_partner():
			send_event("swing", [sweet]))
	for site: RepairSite in w.director.sites:
		site.state_changed.connect(func():
			if not _applying and has_partner():
				_sites_dirty[site.site_id] = site)
	var d: EnemyDirector = w.director
	if is_guest():
		d.mirror = true
		local_player.model.recolor(CoopManager.P2_TUNIC, CoopManager.P2_SCARF)
		local_player.global_position += Basis(Vector3.UP, local_player.yaw) * Vector3(1.4, 0, 0.4)
		_rpc_guest_ready.rpc_id(1)
	else:
		d.wave_warning.connect(func(n: int, dir: Vector3): if has_partner(): send_event("warn", [n, dir]))
		d.wave_cleared.connect(func(n: int): if has_partner(): send_event("clear", [n]))
		d.enemy_introduced.connect(func(k: int): if has_partner(): send_event("intro", [k]))
		d.part_broken.connect(func(s: RepairSite, slot: String): if has_partner(): send_event("broke", [s.site_id, slot]))
		d.enemy_died.connect(func(b: ValleyEnemy): if has_partner(): send_event("edie", [b.net_id]))


func _spawn_remote() -> void:
	_log("spawn remote (world=%s partner=%s)" % [world, has_partner()])
	if world == null or has_partner():
		return
	remote = PLAYER_SCENE.instantiate() as Player
	remote.name = "RemotePlayer"
	remote.index = 1
	remote.net_remote = true
	remote.input_enabled = false
	remote.respawn_point = local_player.respawn_point
	var model := remote.get_node("Model")
	if is_host():
		model.tunic = CoopManager.P2_TUNIC
		model.scarf = CoopManager.P2_SCARF
	remote.position = local_player.global_position + Vector3(1.5, 0.3, 0)
	world.add_child(remote)
	remote.camera.current = false
	local_player.camera.make_current()
	local_player.partner = remote
	local_player.partner_online = true
	remote.partner = local_player
	remote.partner_online = true
	world.gather_world.add_player(remote)
	world.hud.add_player(remote)
	_inv_dirty = is_host()
	AudioManager.play_sfx("coop_join")
	world.hud.show_toast("MSG_NET_JOINED", 3.5)
	world.hud.hint_card.flash(["two_players", "check"], 2.5)
	if is_host():
		# Yapıların güncel hâli (kayıttan beri aşınma olmuş olabilir).
		for site: RepairSite in world.director.sites:
			_sites_dirty[site.site_id] = site
	partner_joined.emit()


func _drop_remote() -> void:
	if not has_partner():
		remote = null
		return
	if world != null and is_instance_valid(world):
		world.hud.remove_player(remote)
		world.gather_world.remove_player(remote)
		world.hud.show_toast("MSG_NET_LEFT", 3.5)
	if local_player != null and is_instance_valid(local_player):
		local_player.partner = null
		local_player.partner_online = false
	remote.queue_free()
	remote = null
	partner_left.emit()


# --- Gönderme kısayolları ----------------------------------------------------------------
func send_event(kind: String, args: Array) -> void:
	if peer_id != 0:
		_rpc_event.rpc_id(peer_id, kind, args)


func send_hurt(amount: int, from: Vector3) -> void:
	if peer_id != 0:
		_rpc_hurt.rpc_id(peer_id, amount, from)


func send_enemy_hit(id: int, amount: float) -> void:
	if is_guest() and peer_id != 0:
		_rpc_enemy_hit.rpc_id(1, id, amount)


func _on_inventory_changed() -> void:
	if not _applying:
		_inv_dirty = true


# --- Gelenler ----------------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(protocol: int, json: String) -> void:
	if protocol != PROTOCOL:
		_close()
		failed.emit("version")
		return
	var parsed = JSON.parse_string(json)
	if typeof(parsed) != TYPE_DICTIONARY:
		_close()
		failed.emit("connect")
		return
	_own_data = SaveSystem.data.duplicate(true)
	var d: Dictionary = parsed
	d["settings"] = _own_data.get("settings", {}).duplicate(true)  # ayarlar oyuncunun kendisinin
	SaveSystem.data = d
	SaveSystem.persistent = false
	_set_status(Status.ONLINE)
	get_tree().paused = false
	get_tree().reload_current_scene()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_guest_ready() -> void:
	if is_host() and multiplayer.get_remote_sender_id() == peer_id:
		_spawn_remote()
		_rpc_host_ready.rpc_id(peer_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_host_ready() -> void:
	_spawn_remote()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_player(state: Array) -> void:
	if has_partner():
		remote.apply_net(state)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_inventory(d: Dictionary) -> void:
	_applying = true
	GameState.inventory.from_dict(d)
	_applying = false


@rpc("any_peer", "call_remote", "reliable")
func _rpc_site(site_id: String, st: Dictionary) -> void:
	if world == null:
		return
	for site: RepairSite in world.director.sites:
		if site.site_id == site_id:
			_applying = true
			site.net_apply(st)
			_applying = false


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_enemies(pack: Array) -> void:
	if is_guest() and world != null and is_instance_valid(world):
		world.director.apply_net(pack)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_enemy_hit(id: int, amount: float) -> void:
	if not is_host() or world == null:
		return
	var b := world.director.net_find(id) as ValleyEnemy
	_log("enemy hit %d %.2f -> %s" % [id, amount, b])
	if b != null and b.alive() and has_partner():
		b.take_hit(amount, remote)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hurt(amount: int, from: Vector3) -> void:
	if local_player != null and is_instance_valid(local_player):
		local_player.take_damage(amount, from)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_event(kind: String, a: Array) -> void:
	if world == null or not is_instance_valid(world):
		return
	var gw: GatherWorld = world.gather_world
	var d: EnemyDirector = world.director
	match kind:
		"res":
			gw.net_depleted(str(a[0]), a[1], a[2])
		"ghit":
			gw.net_hit(str(a[0]), bool(a[1]), a[2])
		"plant":
			gw.net_plant(str(a[0]), a[1])
		"swing":
			if has_partner():
				remote.play_swing(bool(a[0]))
		"heal":
			local_player.heal_full()
		"warn":
			d.net_dim(true)
			d.wave_warning.emit(int(a[0]), a[1])
		"clear":
			d.net_dim(false)
			d.wave_cleared.emit(int(a[0]))
		"intro":
			if not d.seen.has(int(a[0])):
				d.seen.append(int(a[0]))
			d.enemy_introduced.emit(int(a[0]))
		"broke":
			for s: RepairSite in d.sites:
				if s.site_id == str(a[0]):
					d.part_broken.emit(s, str(a[1]))
		"edie":
			d.net_died(int(a[0]))
