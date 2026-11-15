class_name Interactable
extends Node3D
## Oyuncunun etkileşebileceği nokta. Oyuncu en yakın olanı otomatik hedefler;
## ipucu metni ve mesaj çeviri anahtarı olarak tutulur (metin kodda değil).

signal interacted(by: Node)

@export var display_name_key := "NAME_UNKNOWN"
@export var action_key := "ACTION_INSPECT"
@export_multiline var message_key := ""
@export var radius := 3.0
## Odak seçiminde mesafeye eklenen pay: büyük değer = başka hedef yoksa seçilir.
@export var focus_bias := 0.0

const GROUP := &"interactable"


func _ready() -> void:
	add_to_group(GROUP)


func interact(by: Node) -> void:
	interacted.emit(by)


## Şu an hedeflenebilir mi? (Örn. kesilmiş ağaç ya da tohumsuz dikim noktası: hayır.)
func can_focus() -> bool:
	return visible


## İpucunda gösterilecek metin. Alt sınıflar ek bilgi verebilir (gereken vuruş vb.).
func hint_text() -> String:
	return "%s: %s" % [tr(action_key), tr(display_name_key)]
