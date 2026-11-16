## Визуальная 3D-модель призрака, собранная из реальной игровой сцены машины.
##
## Сохраняет кузов, колёса (поворот, вращение и ход подвески), стоп-сигналы,
## опциональные фары и двойной световой след за кормой — без физики,
## коллизий, звука и интерьера кабины.
@tool
class_name RallyGhostCarRig
extends Node3D

const GhostShader = preload("res://shaders/ghost_car.gdshader")
const FeelConfigType = preload("res://scripts/data/rally_car_feel_config.gd")
const CarModels = preload("res://scripts/car_models.gd")
const CarVisuals = preload("res://scripts/car_visual_customization.gd")

const SKIP_NODES := [
	"RallyCockpit",
	"Cameras",
	"BodyCollider",
	"GravelParticles",
	"EngineAudio",
	"WindshieldWipers",
]
const WHEEL_NAMES := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]
const TRAIL_MAX_POINTS: int = 48
const TRAIL_POINT_MIN_STEP_M: float = 0.35
const TRAIL_TELEPORT_RESET_M: float = 14.0

enum RenderMode {
	HOLOGRAM_SHADER = 0,
	TRANSPARENT_LIVERY = 1,
}

var _body_root: Node3D = null
var _body_meshes: Array[MeshInstance3D] = []
var _wheel_meshes: Array[MeshInstance3D] = []
var _steer_pivots: Array[Node3D] = []
var _wheel_spins: Array[Node3D] = []
var _wheel_base_ys: Array[float] = []
var _wheel_radii: Array[float] = []

var _body_shader_mats: Array[ShaderMaterial] = []
var _wheel_shader_mats: Array[ShaderMaterial] = []
var _std_body_entries: Array[Dictionary] = []
var _std_wheel_entries: Array[Dictionary] = []

var _brake_mats: Array[StandardMaterial3D] = []
var _taillight_spots: Array[SpotLight3D] = []
var _headlight_spots: Array[SpotLight3D] = []
var _headlight_base_colors: Array[Color] = []

var _trail_holder: MeshInstance3D = null
var _trail_mesh: ImmediateMesh = null
var _trail_mat: StandardMaterial3D = null
var _trail_history: Array[Dictionary] = []
var _has_prev_world_pos: bool = false
var _prev_world_pos: Vector3 = Vector3.ZERO
var _tail_local_l: Vector3 = Vector3(-0.68, 0.55, -2.05)
var _tail_local_r: Vector3 = Vector3(0.68, 0.55, -2.05)

var _built_scene_path: String = ""
var _built_livery: int = -1
var _built_paint: Color = Color(1.0, 1.0, 1.0, 1.0)
var _near_fade_alpha: float = 1.0
var _render_mode: int = RenderMode.HOLOGRAM_SHADER
var _last_params: Dictionary = {}


func build_for_vehicle(
	veh_id: String,
	fallback_scene_path: String,
	livery_index: int = 0,
	paint_col: Color = Color(1.0, 1.0, 1.0, 1.0)
) -> bool:
	var scene_path: String = CarModels.race_scene_path(veh_id)
	if scene_path.is_empty():
		scene_path = fallback_scene_path
	if scene_path.is_empty():
		scene_path = "res://scenes/rally_car.tscn"
	return build_from_scene_path(scene_path, livery_index, paint_col)


func build_from_scene_path(
	scene_path: String,
	livery_index: int = 0,
	paint_col: Color = Color(1.0, 1.0, 1.0, 1.0)
) -> bool:
	clear_rig()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return false
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return false
	var src := packed.instantiate() as Node3D
	if src == null:
		return false

	_built_scene_path = scene_path
	_built_livery = livery_index
	_built_paint = paint_col

	var front_r: float = float(src.get("front_tire_radius")) if src.get("front_tire_radius") != null else 0.34
	var rear_r: float = float(src.get("rear_tire_radius")) if src.get("rear_tire_radius") != null else 0.34
	var front_w: float = float(src.get("front_tire_width")) if src.get("front_tire_width") != null else 0.245
	var rear_w: float = float(src.get("rear_tire_width")) if src.get("rear_tire_width") != null else 0.245
	var visual_r: float = float(src.get("wheel_visual_radius")) if src.get("wheel_visual_radius") != null else 0.393
	var align_wheels: bool = bool(src.get("align_model_to_wheels")) if src.get("align_model_to_wheels") != null else true
	var feel_cfg: FeelConfigType = src.get("feel_config") as FeelConfigType
	if feel_cfg == null:
		feel_cfg = FeelConfigType.load_default() as FeelConfigType

	var body_path_var: Variant = src.get("body_model_path")
	var src_body: Node3D = null
	if body_path_var is NodePath and not (body_path_var as NodePath).is_empty():
		src_body = src.get_node_or_null(body_path_var as NodePath) as Node3D
	if src_body != null:
		if align_wheels and feel_cfg != null:
			src_body.position.y = (
				front_r
				- feel_cfg.model_body_ground_clearance
				- feel_cfg.model_wheel_center_y
				+ feel_cfg.model_height_offset
			)
		var liveries_var: Variant = src.get("livery_textures")
		if liveries_var is Array and not (liveries_var as Array).is_empty():
			var tex_arr: Array = liveries_var as Array
			var body_mesh := CarVisuals.body_mesh(src_body)
			if body_mesh != null:
				var body_mat := CarVisuals.ensure_body_material(src_body)
				if body_mat != null:
					var safe_liv: int = clampi(livery_index, 0, tex_arr.size() - 1)
					var tex := tex_arr[safe_liv] as Texture2D
					if tex != null:
						body_mat.albedo_texture = tex
					if paint_col != Color(1.0, 1.0, 1.0, 1.0):
						body_mat.albedo_color = paint_col
		_body_root = Node3D.new()
		_body_root.name = "GhostBody"
		_body_root.transform = src_body.transform
		add_child(_body_root)
		_clone_exterior_children(src_body, _body_root)

	_extract_wheels(src, front_r, rear_r, front_w, rear_w, visual_r)
	_extract_lights(src)
	_setup_trail_node()

	src.free()
	if not _last_params.is_empty():
		apply_look_params(_last_params)
	return true


func clear_rig() -> void:
	_body_meshes.clear()
	_wheel_meshes.clear()
	_steer_pivots.clear()
	_wheel_spins.clear()
	_wheel_base_ys.clear()
	_wheel_radii.clear()
	_body_shader_mats.clear()
	_wheel_shader_mats.clear()
	_std_body_entries.clear()
	_std_wheel_entries.clear()
	_brake_mats.clear()
	_taillight_spots.clear()
	_headlight_spots.clear()
	_headlight_base_colors.clear()
	_trail_history.clear()
	_has_prev_world_pos = false
	_body_root = null
	_trail_holder = null
	_trail_mesh = null
	_trail_mat = null
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _clone_exterior_children(src_parent: Node, dest_parent: Node3D) -> void:
	for child in src_parent.get_children():
		var c_name: String = String(child.name)
		if SKIP_NODES.has(c_name):
			continue
		if child is CollisionShape3D or child is Camera3D or child is GPUParticles3D:
			continue
		if child is Light3D or child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			continue
		if child is MeshInstance3D:
			var src_mesh := child as MeshInstance3D
			if not src_mesh.visible or src_mesh.mesh == null:
				continue
			var copy := MeshInstance3D.new()
			copy.name = c_name
			copy.transform = src_mesh.transform
			copy.mesh = src_mesh.mesh
			copy.material_override = src_mesh.material_override
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dest_parent.add_child(copy)
			if c_name in ["CenterBrakeLight", "TaillightLensL", "TaillightLensR"]:
				_register_brake_lens(copy)
			else:
				_body_meshes.append(copy)
			if src_mesh.get_child_count() > 0:
				_clone_exterior_children(src_mesh, copy)
		elif child is Node3D:
			var src_n3d := child as Node3D
			if not src_n3d.visible:
				continue
			var branch := Node3D.new()
			branch.name = c_name
			branch.transform = src_n3d.transform
			dest_parent.add_child(branch)
			_clone_exterior_children(src_n3d, branch)


func _extract_wheels(
	src: Node3D,
	front_r: float,
	rear_r: float,
	front_w: float,
	rear_w: float,
	visual_r: float
) -> void:
	for i in range(WHEEL_NAMES.size()):
		var w_name: String = WHEEL_NAMES[i]
		var src_wheel := src.get_node_or_null(w_name) as Node3D
		if src_wheel == null:
			continue
		var is_front: bool = i < 2
		var radius: float = front_r if is_front else rear_r
		var tire_w: float = front_w if is_front else rear_w

		var pivot := Node3D.new()
		pivot.name = "Ghost_%s" % w_name
		pivot.transform = src_wheel.transform
		add_child(pivot)
		if is_front:
			_steer_pivots.append(pivot)

		# Неподвижные тормозные детали прямо под Wheel_* поворачиваются с рулём.
		for direct in src_wheel.get_children():
			if direct is MeshInstance3D and String(direct.name) != "WheelVisual":
				var dm := direct as MeshInstance3D
				if dm.visible and dm.mesh != null:
					var d_copy := MeshInstance3D.new()
					d_copy.name = String(dm.name)
					d_copy.transform = dm.transform
					d_copy.mesh = dm.mesh
					d_copy.material_override = dm.material_override
					d_copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					pivot.add_child(d_copy)
					_wheel_meshes.append(d_copy)

		var spin_node := Node3D.new()
		spin_node.name = "WheelSpin"
		spin_node.rotation_order = EULER_ORDER_ZXY
		spin_node.scale = CarVisuals.wheel_scale(radius, tire_w, visual_r)
		pivot.add_child(spin_node)

		var src_visual := src_wheel.get_node_or_null("WheelVisual") as Node3D
		if src_visual != null:
			spin_node.position = src_visual.position
			for w_child in src_visual.get_children():
				if w_child is MeshInstance3D:
					var wm := w_child as MeshInstance3D
					if not wm.visible or wm.mesh == null:
						continue
					var w_copy := MeshInstance3D.new()
					w_copy.name = String(wm.name)
					w_copy.transform = wm.transform
					w_copy.mesh = wm.mesh
					w_copy.material_override = wm.material_override
					w_copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					spin_node.add_child(w_copy)
					_wheel_meshes.append(w_copy)

		_wheel_spins.append(spin_node)
		_wheel_base_ys.append(spin_node.position.y)
		_wheel_radii.append(maxf(0.18, radius))


func _extract_lights(src: Node3D) -> void:
	var found_tl := false
	var found_tr := false
	var tail_l_pos := Vector3(0.68, 0.55, -2.05)
	var tail_r_pos := Vector3(-0.68, 0.55, -2.05)

	for light_name in ["TaillightL", "TaillightR", "HeadlightL", "HeadlightR"]:
		var node := src.find_child(light_name, true, false) as SpotLight3D
		if node == null:
			continue
		var rel_xform: Transform3D = _relative_transform(node, src)
		var spot := SpotLight3D.new()
		spot.name = "Ghost_%s" % light_name
		spot.transform = rel_xform
		spot.light_color = node.light_color
		spot.light_energy = 0.0
		spot.spot_range = node.spot_range * 0.75
		spot.spot_angle = node.spot_angle
		spot.spot_attenuation = node.spot_attenuation
		spot.spot_angle_attenuation = node.spot_angle_attenuation
		spot.shadow_enabled = false
		add_child(spot)
		if light_name.begins_with("Taillight"):
			_taillight_spots.append(spot)
			if light_name == "TaillightL":
				tail_l_pos = rel_xform.origin
				found_tl = true
			else:
				tail_r_pos = rel_xform.origin
				found_tr = true
		else:
			_headlight_spots.append(spot)
			_headlight_base_colors.append(node.light_color)

	if found_tl and found_tr:
		_tail_local_l = tail_l_pos
		_tail_local_r = tail_r_pos

	# Если у модели нет отдельных мешей-линз (например, Evo), добавим аккуратные
	# светящиеся габариты в местах задних фонарей — стоп-сигнал призрака виден днём.
	if _brake_mats.size() <= 1 and found_tl and found_tr:
		for pos_idx in range(2):
			var marker := MeshInstance3D.new()
			marker.name = "GhostBrakeLamp_%d" % pos_idx
			var pill := SphereMesh.new()
			pill.radius = 0.055
			pill.height = 0.075
			pill.radial_segments = 10
			pill.rings = 5
			marker.mesh = pill
			marker.position = tail_l_pos if pos_idx == 0 else tail_r_pos
			marker.scale = Vector3(1.5, 0.75, 0.5)
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var lamp_mat := StandardMaterial3D.new()
			lamp_mat.albedo_color = Color(1.0, 0.16, 0.08, 0.85)
			lamp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			lamp_mat.emission_enabled = true
			lamp_mat.emission = Color(1.0, 0.16, 0.08, 1.0)
			lamp_mat.emission_energy_multiplier = 0.4
			marker.material_override = lamp_mat
			add_child(marker)
			_brake_mats.append(lamp_mat)


func _register_brake_lens(mesh_node: MeshInstance3D) -> void:
	var src_mat: Material = mesh_node.material_override
	if src_mat == null and mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
		src_mat = mesh_node.mesh.surface_get_material(0)
	var brake_mat := StandardMaterial3D.new()
	if src_mat is StandardMaterial3D:
		brake_mat = (src_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
	brake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	brake_mat.emission_enabled = true
	mesh_node.material_override = brake_mat
	_brake_mats.append(brake_mat)


func _setup_trail_node() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.cull_mode = BaseMaterial3D.CULL_MODE_DISABLED
	_trail_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.no_depth_test = false

	_trail_holder = MeshInstance3D.new()
	_trail_holder.name = "GhostTrail"
	_trail_holder.top_level = true
	_trail_holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_holder.mesh = _trail_mesh
	_trail_holder.material_override = _trail_mat
	add_child(_trail_holder)


## Применить параметры внешности (используется и при сборке, и в реальном времени из инспектора/паузы).
func apply_look_params(params: Dictionary) -> void:
	_last_params = params.duplicate()
	var mode: int = int(params.get("render_mode", RenderMode.HOLOGRAM_SHADER))
	if mode != _render_mode or (_body_shader_mats.is_empty() and _std_body_entries.is_empty()):
		_render_mode = mode
		_rebuild_materials(params)
	else:
		_sync_materials(params)

	var wheels_on: bool = bool(params.get("show_wheels", true))
	for pivot in _steer_pivots:
		pivot.visible = wheels_on
	for spin_node in _wheel_spins:
		var parent_pivot := spin_node.get_parent() as Node3D
		if parent_pivot != null:
			parent_pivot.visible = wheels_on


func _rebuild_materials(params: Dictionary) -> void:
	_body_shader_mats.clear()
	_wheel_shader_mats.clear()
	_std_body_entries.clear()
	_std_wheel_entries.clear()

	for m_node in _body_meshes:
		_apply_mode_to_mesh(m_node, false)
	for m_node in _wheel_meshes:
		_apply_mode_to_mesh(m_node, true)

	_sync_materials(params)


func _apply_mode_to_mesh(mesh_node: MeshInstance3D, is_wheel: bool) -> void:
	var src_mat: Material = _source_material_of(mesh_node)
	var src_std := src_mat as StandardMaterial3D
	if _render_mode == RenderMode.HOLOGRAM_SHADER:
		var smat := ShaderMaterial.new()
		smat.shader = GhostShader
		if src_std != null and src_std.albedo_texture != null:
			smat.set_shader_parameter("albedo_tex", src_std.albedo_texture)
			smat.set_shader_parameter("use_texture", true)
		else:
			smat.set_shader_parameter("use_texture", false)
		mesh_node.material_override = smat
		if is_wheel:
			_wheel_shader_mats.append(smat)
		else:
			_body_shader_mats.append(smat)
	else:
		var std := (src_std.duplicate() as StandardMaterial3D) if src_std != null else StandardMaterial3D.new()
		std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		std.emission_enabled = true
		mesh_node.material_override = std
		var entry := {
			"mat": std,
			"base_color": std.albedo_color,
			"base_tex": src_std.albedo_texture if src_std != null else null,
		}
		if is_wheel:
			_std_wheel_entries.append(entry)
		else:
			_std_body_entries.append(entry)


func _sync_materials(params: Dictionary) -> void:
	var g_col: Color = params.get("ghost_color", Color(0.22, 0.86, 1.0, 1.0)) as Color
	var r_col: Color = params.get("rim_color", Color(0.70, 0.97, 1.0, 1.0)) as Color
	var base_op: float = float(params.get("opacity", 0.42))
	var wheel_scale: float = float(params.get("wheel_opacity_scale", 0.85))
	var fresnel_pow: float = float(params.get("fresnel_power", 2.6))
	var rim_int: float = float(params.get("rim_intensity", 1.65))
	var em_str: float = float(params.get("emission_strength", 1.15))
	var scan_str: float = float(params.get("scanline_strength", 0.18))
	var scan_den: float = float(params.get("scanline_density", 42.0))
	var scan_spd: float = float(params.get("scanline_speed", 2.5))
	var pls_spd: float = float(params.get("pulse_speed", 2.0))
	var pls_amt: float = float(params.get("pulse_amount", 0.08))
	var sh_con: float = float(params.get("shading_contrast", 0.45))
	var liv_mix: float = float(params.get("livery_tint_strength", 0.45))
	var keep_tex: bool = bool(params.get("preserve_livery_texture", true))

	if _render_mode == RenderMode.HOLOGRAM_SHADER:
		for mat_list_idx in range(2):
			var mats: Array[ShaderMaterial] = _body_shader_mats if mat_list_idx == 0 else _wheel_shader_mats
			var op_val: float = base_op if mat_list_idx == 0 else clampf(base_op * wheel_scale, 0.02, 1.0)
			for smat in mats:
				smat.set_shader_parameter("ghost_color", g_col)
				smat.set_shader_parameter("rim_color", r_col)
				smat.set_shader_parameter("opacity", op_val)
				smat.set_shader_parameter("near_fade_alpha", _near_fade_alpha)
				smat.set_shader_parameter("fresnel_power", fresnel_pow)
				smat.set_shader_parameter("rim_intensity", rim_int)
				smat.set_shader_parameter("emission_strength", em_str)
				smat.set_shader_parameter("shading_contrast", sh_con)
				smat.set_shader_parameter("scanline_strength", scan_str)
				smat.set_shader_parameter("scanline_density", scan_den)
				smat.set_shader_parameter("scanline_speed", scan_spd)
				smat.set_shader_parameter("pulse_speed", pls_spd)
				smat.set_shader_parameter("pulse_amount", pls_amt)
				smat.set_shader_parameter("texture_mix", liv_mix if keep_tex else 0.0)
	else:
		for entry_list_idx in range(2):
			var entries: Array[Dictionary] = _std_body_entries if entry_list_idx == 0 else _std_wheel_entries
			var op_val: float = base_op if entry_list_idx == 0 else clampf(base_op * wheel_scale, 0.02, 1.0)
			for entry in entries:
				var std := entry["mat"] as StandardMaterial3D
				var base_tex: Texture2D = entry.get("base_tex") as Texture2D
				std.albedo_texture = base_tex if keep_tex else null
				var base_c: Color = entry["base_color"] as Color
				var tinted: Color = base_c.lerp(g_col, liv_mix)
				tinted.a = clampf(op_val * _near_fade_alpha, 0.0, 1.0)
				std.albedo_color = tinted
				std.emission_enabled = em_str > 0.01
				std.emission = g_col
				std.emission_energy_multiplier = em_str * 0.4 * _near_fade_alpha


func set_near_fade(alpha_factor: float) -> void:
	var clamped: float = clampf(alpha_factor, 0.0, 1.0)
	if is_equal_approx(clamped, _near_fade_alpha):
		return
	_near_fade_alpha = clamped
	if _render_mode == RenderMode.HOLOGRAM_SHADER:
		for smat in _body_shader_mats:
			smat.set_shader_parameter("near_fade_alpha", _near_fade_alpha)
		for smat in _wheel_shader_mats:
			smat.set_shader_parameter("near_fade_alpha", _near_fade_alpha)
	elif not _last_params.is_empty():
		_sync_materials(_last_params)


func update_pose_and_fx(
	delta: float,
	sample: Dictionary,
	stage_root: Node3D,
	params: Dictionary,
	night_active: bool
) -> void:
	if not bool(sample.get("valid", false)):
		return
	var local_pos: Vector3 = sample["pos"] as Vector3
	var local_quat: Quaternion = sample["quat"] as Quaternion
	var local_xform := Transform3D(Basis(local_quat), local_pos)
	global_transform = stage_root.global_transform * local_xform

	# Передние колёса поворачиваются, все четыре крутятся и сжимаются по подвеске.
	var animate_w: bool = bool(params.get("animate_wheels", true))
	var steer_rad: float = float(sample.get("steer", 0.0))
	var speed_mps: float = float(sample.get("speed_mps", 0.0))
	var wy_list: Array[float] = [
		float(sample.get("wy_fl", 0.0)),
		float(sample.get("wy_fr", 0.0)),
		float(sample.get("wy_rl", 0.0)),
		float(sample.get("wy_rr", 0.0)),
	]
	if animate_w:
		for s_idx in range(_steer_pivots.size()):
			_steer_pivots[s_idx].rotation.y = steer_rad
		for w_idx in range(_wheel_spins.size()):
			var spin_node: Node3D = _wheel_spins[w_idx]
			var wy_off: float = wy_list[mini(w_idx, wy_list.size() - 1)]
			spin_node.position.y = _wheel_base_ys[w_idx] + wy_off
			var rad: float = _wheel_radii[w_idx]
			spin_node.rotation.x = wrapf(spin_node.rotation.x + (speed_mps / rad) * delta, -PI, PI)

	# Стоп-сигналы и фары.
	var brakes_on: bool = bool(params.get("show_brake_lights", true))
	var brake_lvl: float = clampf(float(sample.get("brake", 0.0)), 0.0, 1.0)
	var b_col: Color = params.get("brake_light_color", Color(1.0, 0.14, 0.08, 1.0)) as Color
	var b_idle: float = float(params.get("brake_light_idle_energy", 0.35))
	var b_active: float = float(params.get("brake_light_active_energy", 2.8))
	var b_energy: float = lerpf(b_idle, b_active, brake_lvl) * _near_fade_alpha if brakes_on else 0.0
	for b_mat in _brake_mats:
		b_mat.emission = b_col
		b_mat.emission_energy_multiplier = b_energy * 2.0
		var al := b_col
		al.a = clampf(lerpf(0.35, 0.95, brake_lvl) * _near_fade_alpha, 0.0, 1.0) if brakes_on else 0.0
		b_mat.albedo_color = al
	for spot in _taillight_spots:
		spot.light_color = b_col
		spot.light_energy = b_energy

	var hl_enabled: bool = bool(params.get("show_headlights", true))
	var hl_night_only: bool = bool(params.get("headlights_night_only", true))
	var hl_active: bool = hl_enabled and (night_active or not hl_night_only)
	var hl_col: Color = params.get("headlight_color", Color(0.70, 0.92, 1.0, 1.0)) as Color
	var hl_energy: float = float(params.get("headlight_energy", 2.6)) * _near_fade_alpha if hl_active else 0.0
	for spot_idx in range(_headlight_spots.size()):
		var spot: SpotLight3D = _headlight_spots[spot_idx]
		spot.light_color = hl_col
		spot.light_energy = hl_energy

	_update_trail(speed_mps * 3.6, params)


func reset_trail() -> void:
	_trail_history.clear()
	_has_prev_world_pos = false
	if _trail_mesh != null:
		_trail_mesh.clear_surfaces()


func _update_trail(speed_kmh: float, params: Dictionary) -> void:
	if _trail_mesh == null or _trail_holder == null:
		return
	var enabled_trail: bool = bool(params.get("trail_enabled", true))
	if not enabled_trail or not visible:
		if not _trail_history.is_empty():
			reset_trail()
		return

	var cur_pos: Vector3 = global_position
	if _has_prev_world_pos and cur_pos.distance_to(_prev_world_pos) > TRAIL_TELEPORT_RESET_M:
		reset_trail()
	_prev_world_pos = cur_pos
	_has_prev_world_pos = true

	var min_spd: float = float(params.get("trail_min_speed_kmh", 20.0))
	var dual: bool = bool(params.get("trail_dual_ribbons", true))
	var offset_x: float = float(params.get("trail_dual_offset_x", 0.72))
	var height_off: float = float(params.get("trail_height_offset", 0.48))
	var trail_len: float = maxf(1.0, float(params.get("trail_length_m", 18.0)))
	var rib_w: float = maxf(0.02, float(params.get("trail_ribbon_width", 0.14)))
	var t_col: Color = params.get("trail_color", Color(0.24, 0.88, 1.0, 1.0)) as Color
	var t_op: float = clampf(float(params.get("trail_opacity", 0.55)), 0.0, 1.0) * _near_fade_alpha

	if speed_kmh >= min_spd:
		var z_back: float = minf(_tail_local_l.z, _tail_local_r.z)
		var pt_l: Vector3 = global_transform * Vector3(offset_x, height_off, z_back)
		var pt_r: Vector3 = global_transform * Vector3(-offset_x, height_off, z_back)
		var pt_c: Vector3 = global_transform * Vector3(0.0, height_off, z_back)
		var side_vec: Vector3 = global_transform.basis.x.normalized()
		if _trail_history.is_empty():
			_trail_history.append({"l": pt_l, "r": pt_r, "c": pt_c, "side": side_vec})
		else:
			var prev_c: Vector3 = _trail_history[_trail_history.size() - 1]["c"] as Vector3
			if pt_c.distance_to(prev_c) >= TRAIL_POINT_MIN_STEP_M:
				_trail_history.append({"l": pt_l, "r": pt_r, "c": pt_c, "side": side_vec})
			else:
				_trail_history[_trail_history.size() - 1] = {"l": pt_l, "r": pt_r, "c": pt_c, "side": side_vec}
	elif not _trail_history.is_empty():
		_trail_history.pop_front()

	# Обрезаем хвост по реальной длине пути в метрах.
	var total_arc: float = 0.0
	var keep_from: int = 0
	for idx in range(_trail_history.size() - 1, 0, -1):
		var a: Vector3 = _trail_history[idx]["c"] as Vector3
		var b: Vector3 = _trail_history[idx - 1]["c"] as Vector3
		total_arc += a.distance_to(b)
		if total_arc > trail_len:
			keep_from = idx - 1
			break
	if keep_from > 0:
		_trail_history = _trail_history.slice(keep_from)
	while _trail_history.size() > TRAIL_MAX_POINTS:
		_trail_history.pop_front()

	_trail_mesh.clear_surfaces()
	if _trail_history.size() < 2 or t_op <= 0.004:
		return

	if dual:
		_emit_ribbon("l", rib_w * 0.5, t_col, t_op)
		_emit_ribbon("r", rib_w * 0.5, t_col, t_op)
	else:
		_emit_ribbon("c", rib_w, t_col, t_op)


func _emit_ribbon(key: String, half_w: float, base_col: Color, max_alpha: float) -> void:
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_mat)
	var count: int = _trail_history.size()
	for i in range(count):
		var frac: float = float(i) / float(maxi(1, count - 1))
		var alpha_val: float = frac * frac * max_alpha
		var w_scale: float = lerpf(0.2, 1.0, frac)
		var pt: Vector3 = _trail_history[i][key] as Vector3
		var side_vec: Vector3 = _trail_history[i]["side"] as Vector3
		var c := Color(base_col.r, base_col.g, base_col.b, alpha_val)
		_trail_mesh.surface_set_color(c)
		_trail_mesh.surface_add_vertex(pt - side_vec * (half_w * w_scale))
		_trail_mesh.surface_set_color(c)
		_trail_mesh.surface_add_vertex(pt + side_vec * (half_w * w_scale))
	_trail_mesh.surface_end()


static func _source_material_of(mesh_node: MeshInstance3D) -> Material:
	if mesh_node.material_override != null:
		return mesh_node.material_override
	if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
		return mesh_node.mesh.surface_get_material(0)
	return null


static func _relative_transform(node: Node, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
