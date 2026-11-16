extends Node
## Global oyun durumu: kalite ayarı, aktif görev, heybe, oynanış ayarları.
## Oyun mantığı burayı dinler; platforma özel şeyler PlatformServices'te durur.

signal quality_changed(level: int)
signal quest_changed(quest_key: String)
signal locale_changed(locale: String)
signal rhythm_changed(enabled: bool)
signal enemies_changed(enabled: bool)

enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_KEYS := ["QUALITY_LOW", "QUALITY_MEDIUM", "QUALITY_HIGH"]
const LOCALES := ["tr", "en"]

var quality: int = Quality.HIGH
var current_quest_key := "QUEST_EXPLORE"
var is_mobile := false
var inventory := Inventory.new()
## Ritim vuruşu: açıkken küçülen halka hedefe değdiğinde basmak "tatlı vuruş" verir.
## Kapalıyken basılı tutmak yeterli.
var rhythm_hits := true
var tutorial_step := 0
## Mürekkep lekesi dalgaları. Kapatılırsa vadi tamamen sakin kalır.
var enemies_enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_mobile = OS.has_feature("mobile")
	# Mobil varsayılanı Düşük, PC varsayılanı Yüksek. Kayıtlı ayar varsa SaveSystem ezer.
	quality = Quality.LOW if is_mobile else Quality.HIGH
	WatercolorMaterials.apply_quality(quality)
	add_to_group(&"persist")  # SaveSystem.PERSIST_GROUP (o henüz yüklenmedi)


func set_rhythm_hits(enabled: bool) -> void:
	rhythm_hits = enabled
	rhythm_changed.emit(enabled)


func set_enemies_enabled(enabled: bool) -> void:
	enemies_enabled = enabled
	enemies_changed.emit(enabled)


func save_state(data: Dictionary) -> void:
	data["inventory"] = inventory.to_dict()
	data["tutorial_step"] = tutorial_step


func load_state(data: Dictionary) -> void:
	inventory.from_dict(data.get("inventory", {}))
	tutorial_step = int(data.get("tutorial_step", 0))


func set_quality(level: int) -> void:
	quality = clampi(level, Quality.LOW, Quality.HIGH)
	WatercolorMaterials.apply_quality(quality)
	quality_changed.emit(quality)


func cycle_quality() -> void:
	set_quality((quality + 1) % 3)


func quality_name_key() -> String:
	return QUALITY_KEYS[quality]


func set_quest(key: String) -> void:
	current_quest_key = key
	quest_changed.emit(key)


func set_locale(locale: String) -> void:
	if locale not in LOCALES:
		locale = "en"
	TranslationServer.set_locale(locale)
	locale_changed.emit(locale)


func toggle_locale() -> void:
	var cur := TranslationServer.get_locale().substr(0, 2)
	set_locale("en" if cur == "tr" else "tr")


func current_locale() -> String:
	return TranslationServer.get_locale().substr(0, 2)


# --- Kalite katmanları ---------------------------------------------------
func outlines_enabled() -> bool:
	return quality >= Quality.MEDIUM

func bleed_enabled() -> bool:
	return quality >= Quality.MEDIUM

func kuwahara_enabled() -> bool:
	return quality == Quality.HIGH
