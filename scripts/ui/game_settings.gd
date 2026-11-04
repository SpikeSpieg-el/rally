## Общие параметры игры, сохраняемые независимо от сцены и пресетов.
class_name RallyGameSettings
extends VBoxContainer

const SETTINGS_PATH := "user://rally_game.cfg"

signal ps1_enabled_changed(enabled: bool)

var ps1_toggle: CheckButton


static func ps1_enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return bool(cfg.get_value("video", "ps1_retro_enabled", true))


static func set_ps1_enabled(enabled: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("video", "ps1_retro_enabled", enabled)
	cfg.save(SETTINGS_PATH)


func _ready() -> void:
	var note := Label.new()
	note.text = "Параметры изображения применяются ко всем трассам и сохраняются автоматически."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	ps1_toggle = CheckButton.new()
	ps1_toggle.name = "Ps1RetroToggle"
	ps1_toggle.text = "Ретро-экран PS1"
	ps1_toggle.tooltip_text = "Включает пикселизацию, ограниченную палитру и PS1-дрожание изображения."
	ps1_toggle.button_pressed = ps1_enabled()
	ps1_toggle.toggled.connect(_on_ps1_toggled)
	add_child(ps1_toggle)


func _on_ps1_toggled(enabled: bool) -> void:
	set_ps1_enabled(enabled)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("apply_ps1_setting"):
		scene.call("apply_ps1_setting", enabled)
	ps1_enabled_changed.emit(enabled)
