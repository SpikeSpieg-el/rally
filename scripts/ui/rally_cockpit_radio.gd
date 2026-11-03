## Магнитола в кабине: настоящий 3D-блок на центральной консоли, а не ещё
## один 2D-оверлей. Экран светится, обложка и имя трека обновляются от
## RallyRadio, полоска показывает позицию в композиции.
##
## Узел виден только в режиме камеры «Кабина»; в виде сзади/с капота он
## скрывается, чтобы не мешать обзору. Все элементы строятся кодом, поэтому
## сцена машины не зарастает десятками вложенных узлов в инспекторе.
extends Node3D

var _radio: Node = null
var _car: Node = null
var _station_base: String = "RALLY FM"
var _cover: Sprite3D = null
var _station_label: Label3D = null
var _title_label: Label3D = null
var _artist_label: Label3D = null
var _progress_fill: MeshInstance3D = null
var _screen_material: StandardMaterial3D = null
var _fill_material: StandardMaterial3D = null
var _stripe_material: StandardMaterial3D = null
var _cover_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_car = _find_car()
	_build_head_unit()
	call_deferred("_connect_radio")


func _find_car() -> Node:
	var parent := get_parent()
	while parent != null:
		if "camera_mode" in parent:
			return parent
		parent = parent.get_parent()
	return null


func _build_head_unit() -> void:
	var body_material := _material(Color(0.045, 0.05, 0.058, 1.0), Color(0.01, 0.01, 0.012, 1.0))
	var bezel_material := _material(Color(0.10, 0.11, 0.13, 1.0), Color(0.02, 0.02, 0.025, 1.0))
	_screen_material = _material(Color(0.018, 0.045, 0.065, 1.0), Color(0.06, 0.16, 0.20, 1.0))
	_fill_material = _material(Color(1.0, 0.48, 0.08, 1.0), Color(1.0, 0.35, 0.04, 1.0))
	_stripe_material = _material(Color(1.0, 0.48, 0.08, 1.0), Color(1.0, 0.35, 0.04, 1.0))
	var bar_material := _material(Color(1.0, 1.0, 1.0, 0.16), Color(0.01, 0.01, 0.01, 1.0))
	var knob_material := _material(Color(0.28, 0.30, 0.34, 1.0), Color(0.9, 0.14, 0.08, 1.0))

	_add_box("Bezel", Vector3(0.262, 0.116, 0.012), Vector3(0.0, 0.0, 0.006), bezel_material)
	_add_box("Body", Vector3(0.250, 0.105, 0.018), Vector3.ZERO, body_material)
	_add_quad("Screen", Vector2(0.218, 0.078), Vector3(0.0, 0.0, -0.011), _screen_material)
	_add_quad("TopStripe", Vector2(0.218, 0.003), Vector3(0.0, 0.040, -0.013), _stripe_material)
	_add_quad("ProgressBg", Vector2(0.130, 0.004), Vector3(0.035, -0.030, -0.013), bar_material)
	_progress_fill = _add_quad("ProgressFill", Vector2(0.130, 0.004),
		Vector3(0.035, -0.030, -0.014), _fill_material)
	_progress_fill.scale.x = 0.001

	_cover = Sprite3D.new()
	_cover.name = "Cover"
	_cover.centered = true
	_cover.pixel_size = 0.00009
	_cover.position = Vector3(-0.076, -0.002, -0.014)
	_cover.rotation.y = PI
	_cover.double_sided = true
	_cover.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_cover)

	_station_label = _add_label("Station", "RALLY FM  •  01", 12, 0.00055,
		Color(1.0, 0.62, 0.16, 1.0), Vector3(0.035, 0.026, -0.014))
	_title_label = _add_label("Title", "ЗАГРУЗКА ЭФИРА…", 18, 0.00068,
		Color(0.96, 0.98, 1.0, 1.0), Vector3(0.035, 0.004, -0.014))
	_artist_label = _add_label("Artist", "НОН-СТОП МИКС", 14, 0.00055,
		Color(0.62, 0.76, 0.86, 1.0), Vector3(0.035, -0.015, -0.014))

	_add_knob("KnobL", Vector3(-0.118, -0.030, -0.012), knob_material)
	_add_knob("KnobR", Vector3(0.118, -0.030, -0.012), knob_material)


func _material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.metallic = 0.25
	material.roughness = 0.55
	material.emission_enabled = true
	material.emission = emission
	return material


func _add_box(node_name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	add_child(mesh)
	return mesh


func _add_quad(node_name: String, size: Vector2, at: Vector3,
		material: Material) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = quad
	mesh.material_override = material
	mesh.position = at
	# Передняя сторона QuadMesh/Label3D смотрит к водителю (локальная −Z).
	mesh.rotation.y = PI
	add_child(mesh)
	return mesh


func _add_label(node_name: String, text: String, font_size: int, pixel_size: float,
		color: Color, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.position = at
	label.rotation.y = PI
	add_child(label)
	return label


func _add_knob(node_name: String, at: Vector3, material: Material) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.009
	cylinder.bottom_radius = 0.009
	cylinder.height = 0.008
	cylinder.radial_segments = 12
	var knob := MeshInstance3D.new()
	knob.name = node_name
	knob.mesh = cylinder
	knob.material_override = material
	knob.position = at
	knob.rotation.x = PI * 0.5
	add_child(knob)


func _connect_radio() -> void:
	_radio = get_node_or_null("/root/RallyRadio")
	if _radio == null:
		return
	if _radio.has_method("station_name"):
		_station_base = String(_radio.call("station_name"))
	_station_label.text = _station_base + "  •  01"
	if _radio.has_signal("track_changed"):
		var on_track := Callable(self, "_on_track_changed")
		if not _radio.is_connected("track_changed", on_track):
			_radio.connect("track_changed", on_track)
	if _radio.has_signal("state_changed"):
		var on_state := Callable(self, "_on_state_changed")
		if not _radio.is_connected("state_changed", on_state):
			_radio.connect("state_changed", on_state)
	var track = _radio.get("current_track")
	if track is Dictionary:
		_apply_track(track, false)


func _on_track_changed(track: Dictionary) -> void:
	_apply_track(track, true)


func _apply_track(track: Dictionary, animated: bool) -> void:
	var accent = track.get("accent", Color(1.0, 0.48, 0.08, 1.0))
	if accent is Color:
		_set_accent(accent)
	_title_label.text = _short(String(track.get("title", "БЕЗ НАЗВАНИЯ")), 18)
	_artist_label.text = _short(String(track.get("artist", "RALLY FM")), 22)
	_cover.texture = _load_cover(String(track.get("cover_path", "")))
	if not animated:
		_cover.modulate.a = 1.0
		return
	if _cover_tween != null and _cover_tween.is_running():
		_cover_tween.kill()
	_cover.modulate.a = 0.0
	_cover_tween = create_tween()
	_cover_tween.tween_property(_cover, "modulate:a", 1.0, 0.55)


func _load_cover(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


func _set_accent(color: Color) -> void:
	_fill_material.albedo_color = color
	_fill_material.emission = color
	_stripe_material.albedo_color = color
	_stripe_material.emission = color
	_screen_material.emission = Color(color.r * 0.12, color.g * 0.20, color.b * 0.24, 1.0)
	_station_label.modulate = color


func _on_state_changed(_playing: bool, muted: bool) -> void:
	_station_label.text = _station_base + ("  •  MUTE" if muted else "  •  01")


func _process(_delta: float) -> void:
	if _car != null and "camera_mode" in _car:
		visible = int(_car.get("camera_mode")) == 2
	if _radio == null:
		return
	var length := float(_radio.call("current_length"))
	var played := float(_radio.call("current_position"))
	if length > 0.0:
		_progress_fill.scale.x = clampf(played / length, 0.001, 1.0)
	else:
		_progress_fill.scale.x = 0.001


func _short(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, maxi(1, limit - 1)) + "…"
