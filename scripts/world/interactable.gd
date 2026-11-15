class_name Interactable
extends Node3D
## Oyuncunun etkileşebileceği nokta. Oyuncu en yakın olanı otomatik hedefler;
## ipucu metni ve mesaj çeviri anahtarı olarak tutulur (metin kodda değil).

signal interacted(by: Node)

@export var display_name_key := "NAME_UNKNOWN"
@export var action_key := "ACTION_INSPECT"
@export_multiline var message_key := ""
@export var radius := 3.0

const GROUP := &"interactable"


func _ready() -> void:
	add_to_group(GROUP)


func interact(by: Node) -> void:
	interacted.emit(by)
