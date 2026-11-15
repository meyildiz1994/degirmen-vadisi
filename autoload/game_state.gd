extends Node
## Global oyun durumu: kalite ayarı, aktif görev, platform bilgisi.
## Oyun mantığı burayı dinler; platforma özel şeyler PlatformServices'te durur.

signal quality_changed(level: int)
signal quest_changed(quest_key: String)
signal locale_changed(locale: String)

enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_KEYS := ["QUALITY_LOW", "QUALITY_MEDIUM", "QUALITY_HIGH"]
const LOCALES := ["tr", "en"]

var quality: int = Quality.HIGH
var current_quest_key := "QUEST_EXPLORE"
var is_mobile := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_mobile = OS.has_feature("mobile")
	# Mobil varsayılanı Düşük, PC varsayılanı Yüksek. Kayıtlı ayar varsa SaveSystem ezer.
	quality = Quality.LOW if is_mobile else Quality.HIGH
	WatercolorMaterials.apply_quality(quality)


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
