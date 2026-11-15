class_name ToolBelt
extends HBoxContainer
## Ekranda alet kemeri (sağ üst, görev ikonunun solunda): sahip olunan aletler ikon ve
## dayanıklılık çubuğuyla. Yeni alet gelince zıplar; elde tutulan alet parlak çerçeveli.
## Oyuncu "baltam var mı, elimde mi?" sorusunun cevabını her an görür.

var player: Player
var _held := ""
var _tween: Tween


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.inventory.changed.connect(_rebuild)
	GameState.inventory.tool_added.connect(_on_tool_added)
	_rebuild()


func _process(_delta: float) -> void:
	var held := ""
	if player != null:
		held = player.model.held_tool_kind()
	if held != _held:
		_held = held
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var shown := {}
	for t: ToolItem in GameState.inventory.tools:
		if shown.has(t.kind):
			continue  # türün en iyisi yeter; tamamı heybede
		var best := GameState.inventory.best_tool(t.kind, "oak_tree" if t.kind == "axe" else "boulder")
		shown[t.kind] = true
		add_child(_slot(best if best != null else t))


func _slot(t: ToolItem) -> Control:
	var panel := WatercolorPanel.new()
	panel.padding = Vector2(6, 4)
	panel.blob_seed = 2.0 + t.kind.length()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	var ic := ItemIcon.new()
	ic.icon = t.kind
	ic.custom_minimum_size = Vector2(52, 52)
	ic.tint = (Materials.color(t.head).lightened(0.25) if t.head != "stone" else Color.WHITE).darkened(ItemMemory.darkness(t))
	vb.add_child(ic)
	var bar := StatBar.new()
	bar.value = t.durability_ratio() * 10.0
	bar.custom_minimum_size = Vector2(52, 8)
	vb.add_child(bar)
	if t.kind == _held:
		panel.modulate = Color(1.15, 1.08, 0.85)
		panel.scale = Vector2(1.08, 1.08)
	return panel


func _on_tool_added(_t: ToolItem) -> void:
	_rebuild.call_deferred()
	if _tween and _tween.is_valid():
		_tween.kill()
	pivot_offset = size * 0.5
	_tween = create_tween()
	AudioManager.play_ui("ui_click")
	_tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.15).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
