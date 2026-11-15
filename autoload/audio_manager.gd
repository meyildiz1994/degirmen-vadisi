extends Node
## Tek ses yöneticisi. Sesler GELİŞTİRME sırasında ElevenLabs ile üretilip
## res://audio altına dosya olarak eklenir; oyun çalışırken hiçbir ağ çağrısı yapılmaz.
##
## Dosya adlandırma: res://audio/<kategori>/<id>.<wav|ogg> veya varyasyonlar için
## <id>_1.wav, <id>_2.wav ... Dosya yoksa oyun çökmez, sessizce devam eder.

const BUSES := ["Music", "SFX", "Ambience", "UI"]
const CATEGORY_DIRS := {"sfx": "res://audio/sfx", "ambience": "res://audio/ambience", "music": "res://audio/music"}
const EXTENSIONS := ["wav", "ogg"]
const MAX_VARIATIONS := 9
const SFX_POOL_SIZE := 10
const PITCH_JITTER := 0.05  ## ±%5

var _variation_cache := {}  ## "kategori/id" -> Array[AudioStream]
var _missing_reported := {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _ui_player: AudioStreamPlayer
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _music_id := ""
var _music_tween: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_buses()
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = &"UI"
	add_child(_ui_player)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_music_active = _music_a


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	p.volume_db = -80.0
	add_child(p)
	return p


## default_bus_layout.tres yüklenmemişse bile bus'lar var olsun.
func _ensure_buses() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")


# --- Ses seviyeleri ----------------------------------------------------------
func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func get_bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	return db_to_linear(AudioServer.get_bus_volume_db(idx)) if idx != -1 else 0.0


# --- Dosya çözümleme -----------------------------------------------------------
func get_variations(category: String, id: String) -> Array:
	var key := category + "/" + id
	if _variation_cache.has(key):
		return _variation_cache[key]
	var found: Array = []
	var dir: String = CATEGORY_DIRS.get(category, "res://audio/" + category)
	for ext in EXTENSIONS:
		var single := "%s/%s.%s" % [dir, id, ext]
		if ResourceLoader.exists(single):
			found.append(load(single))
		for i in range(1, MAX_VARIATIONS + 1):
			var path := "%s/%s_%d.%s" % [dir, id, i, ext]
			if ResourceLoader.exists(path):
				found.append(load(path))
	if found.is_empty() and not _missing_reported.has(key):
		_missing_reported[key] = true
		print_verbose("AudioManager: '%s' için ses dosyası yok, sessiz devam." % key)
	_variation_cache[key] = found
	return found


func _pick(category: String, id: String) -> AudioStream:
	var list := get_variations(category, id)
	if list.is_empty():
		return null
	return list[_rng.randi() % list.size()]


func _jitter() -> float:
	return 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)


# --- Efektler --------------------------------------------------------------------
## Konumsuz efekt (2D). Varyasyonlardan rastgele seçer, pitch ±%5.
func play_sfx(id: String, volume_db := 0.0) -> void:
	var stream := _pick("sfx", id)
	if stream == null:
		return
	var player := _free_sfx_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = _jitter()
	player.play()


## 3D konumlu efekt (vuruş, ayak sesi). Kendini bitince siler.
func play_sfx_3d(id: String, position: Vector3, volume_db := 0.0) -> void:
	var stream := _pick("sfx", id)
	if stream == null or get_tree().current_scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.bus = &"SFX"
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = _jitter()
	p.unit_size = 6.0
	p.max_distance = 30.0
	get_tree().current_scene.add_child(p)
	p.global_position = position
	p.finished.connect(p.queue_free)
	p.play()


func play_ui(id: String) -> void:
	var stream := _pick("sfx", id)
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.pitch_scale = _jitter()
	_ui_player.play()


func _free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	return _sfx_pool[_rng.randi() % _sfx_pool.size()]


# --- Ambiyans (3D konumlu, döngülü) -------------------------------------------------
## Dereye yaklaştıkça su sesi artsın diye ambiyanslar dünyaya yerleştirilir.
## Dosya yoksa yine de (sessiz) bir oynatıcı döner; sonradan dosya eklenince çalışır.
func create_ambience(id: String, parent: Node3D, position: Vector3, unit_size := 8.0, max_distance := 35.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "Ambience_" + id
	p.bus = &"Ambience"
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	parent.add_child(p)
	p.position = position
	var stream := _pick("ambience", id)
	if stream != null:
		stream = stream.duplicate()
		_set_loop(stream)
		p.stream = stream
		p.play(_rng.randf() * maxf(stream.get_length() - 0.1, 0.0))
	return p


func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		if stream.loop_end <= 0:
			stream.loop_end = int(stream.get_length() * stream.mix_rate)


# --- Müzik (crossfade) ------------------------------------------------------------
func play_music(id: String, fade_time := 2.5) -> void:
	if id == _music_id:
		return
	var stream := _pick("music", id)
	_music_id = id
	var incoming := _music_b if _music_active == _music_a else _music_a
	var outgoing := _music_active
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(outgoing, "volume_db", -80.0, fade_time)
	if stream != null:
		stream = stream.duplicate()
		_set_loop(stream)
		incoming.stream = stream
		incoming.volume_db = -80.0
		incoming.play()
		_music_tween.tween_property(incoming, "volume_db", 0.0, fade_time).set_trans(Tween.TRANS_SINE)
		_music_active = incoming
	_music_tween.chain().tween_callback(outgoing.stop)


func stop_music(fade_time := 2.0) -> void:
	_music_id = ""
	var t := create_tween()
	t.tween_property(_music_active, "volume_db", -80.0, fade_time)
	t.tween_callback(_music_active.stop)
