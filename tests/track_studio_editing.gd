# godot --headless --path . --script res://tests/track_studio_editing.gd
extends SceneTree

const Studio = preload("res://addons/rally_track_studio/studio.gd")
const Settings = preload("res://scripts/data/rally_track_studio_settings.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")
const Section = preload("res://scripts/data/rally_route_section.gd")
const Prop = preload("res://scripts/data/rally_prop.gd")
const Library = preload("res://scripts/data/rally_prop_library.gd")

class TestStage extends Node3D:
	func editor_cached_ground_height(_x: float, _z: float) -> Dictionary:
		return {"height": 12.0}

func _initialize() -> void:
	call_deferred("_test")

func _test() -> void:
	var studio = Studio.new()
	studio.settings = Settings.new()
	studio.track = Track.new()
	studio.track.road_half_width = 4.0
	var first = Section.new()
	first.start_distance = 0.0
	first.half_width = 8.0
	first.transition_length = 100.0
	studio.track.route_sections.append(first)
	# Переходы могут пересекаться: новый не должен игнорироваться старым.
	var before: float = studio.track.half_width_at(0.0)
	var added = studio._width_section_for_edit(80.0)
	assert(added != first)
	added.half_width = 3.0
	assert(is_equal_approx(studio.track.half_width_at(0.0), before))
	assert(absf(studio.track.half_width_at(80.0) - 3.0) < 0.001)
	assert(studio._width_section_for_edit(80.0) == added)
	var zero = Section.new()
	zero.start_distance = 150.0
	zero.transition_length = 0.0
	zero.half_width = 6.0
	studio.track.route_sections.append(zero)
	assert(is_equal_approx(studio.track.half_width_at(150.0), 6.0))

	# Пространственный индекс не запрещает точки далеко за концом трассы.
	studio.curve = Curve3D.new()
	studio.curve.add_point(Vector3.ZERO)
	studio.curve.add_point(Vector3(100.0, 0.0, 0.0))
	studio._refresh_analysis()
	assert(studio._too_close_to_road(Vector3(50.0, 0.0, 1.0)))
	assert(not studio._too_close_to_road(Vector3(400.0, 0.0, 0.0)))
	studio.route_ready = false

	# Лимит и минимальный интервал распространяются на весь мазок, а не
	# на каждую его точку; каждый пропс получает высоту именно под собой.
	var scene := Node3D.new()
	root.add_child(scene)
	var stage := TestStage.new()
	scene.add_child(stage)
	stage.owner = scene
	studio.stage = stage
	studio.scene_root = scene
	studio.settings.brush_avoid_road = false
	studio.settings.brush_chance = 1.0
	studio.settings.brush_radius = 10.0
	studio.settings.brush_spacing = 2.0
	studio.settings.brush_max_per_stroke = 8
	var packed := PackedScene.new()
	var model := Node3D.new()
	assert(packed.pack(model) == OK)
	model.free()
	var prop = Prop.new()
	prop.scene = packed
	var library = Library.new()
	library.props.append(prop)
	studio.prop_library = library
	seed(42)
	for _i in range(10):
		studio._place_brush(Vector3.ZERO)
	assert(studio._stroke_nodes.size() == 8)
	for a in studio._stroke_nodes:
		assert(absf(a.global_position.y - 12.0) < 0.001)
		assert(a.get_parent() == stage.get_node("StudioProps"))
		for b in studio._stroke_nodes:
			if a != b:
				assert(Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length() >= 1.999)
	scene.free()
	print("Track studio editing: OK")
	quit(0)
