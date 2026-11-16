## Процедурная обстановка аркадного мира: лес, кусты, валуны, отбойники,
## столбики обочины, знаки, ЛЭП, живые деревни с фонарями и настоящие мосты
## через речные ущелья.
##
## Все пропсы запекаются из сцен `res://scenes/props/*.tscn` один раз и
## рендерятся через MultiMeshInstance3D — минимум draw-calls и стабильный FPS
## на любой дистанции. Детерминизм по (километраж, сид).
class_name RallyArcadeScenery
extends RefCounted

const RoadType = preload("res://scripts/arcade/arcade_road.gd")
const LegType = preload("res://scripts/data/rally_arcade_leg.gd")
const DressingType = preload("res://scripts/track/stage_dressing.gd")

const PROP_PATHS := {
	"pine": "res://scenes/props/pine_tree.tscn",
	"fir": "res://scenes/props/fir_tree.tscn",
	"birch": "res://scenes/props/birch_tree.tscn",
	"dead_tree": "res://scenes/props/dead_tree.tscn",
	"bush": "res://scenes/props/bush.tscn",
	"juniper": "res://scenes/props/juniper.tscn",
	"fern": "res://scenes/props/fern.tscn",
	"grass": "res://scenes/props/grass.tscn",
	"grass2": "res://scenes/props/grass2.tscn",
	"wildflowers": "res://scenes/props/wildflowers.tscn",
	"boulder": "res://scenes/props/boulder.tscn",
	"moss_rock": "res://scenes/props/moss_rock.tscn",
	"rock_cluster": "res://scenes/props/rock_cluster.tscn",
	"river_rock": "res://scenes/props/river_bank_rock.tscn",
	"guardrail": "res://scenes/props/metal_guardrail.tscn",
	"road_sign": "res://scenes/props/road_sign.tscn",
	"power_pole": "res://scenes/props/power_pole.tscn",
	"fence": "res://scenes/props/wooden_fence.tscn",
	"hay_bale": "res://scenes/props/hay_bale.tscn",
	"log": "res://scenes/props/log.tscn",
	"stump": "res://scenes/props/stump.tscn",
	"parked_car": "res://scenes/props/parked_car.tscn",
}

const BRIDGE_SMALL_PATH := "res://scenes/props/bridge_small.tscn"
const FORESTER_HOUSE_PATH := "res://scenes/props/forester_house.tscn"
const LIGHT_TOWER_PATH := "res://scenes/props/light_tower.tscn"

const WALL_TEX_PATH := "res://textures/environment/wall.jpg"
const PLANK_TEX_PATH := "res://textures/environment/plank.png"
const SLATE_TEX_PATH := "res://textures/environment/wet_slate.png"

const TREE_RANGE: float = 360.0
const SMALL_RANGE: float = 185.0
const GUARDRAIL_BAKED_WIDTH: float = 4.275
const FENCE_BAKED_WIDTH: float = 2.6

var ps1_filter: bool = true
var is_night: bool = false

var _mesh_cache: Dictionary = {}
var _scene_cache: Dictionary = {}
var _edge_post_mesh: Mesh = null
var _edge_cap_mesh: Mesh = null
var _water_material: StandardMaterial3D = null
var _wall_material: StandardMaterial3D = null
var _plank_material: StandardMaterial3D = null
var _roof_slate_material: StandardMaterial3D = null
var _window_lit_material: StandardMaterial3D = null
var _window_day_material: StandardMaterial3D = null
var _door_material: StandardMaterial3D = null


func configure(p_ps1_filter: bool, p_is_night: bool) -> void:
	if ps1_filter != p_ps1_filter:
		_mesh_cache.clear()
	ps1_filter = p_ps1_filter
	is_night = p_is_night


func warm_up() -> void:
	for key in PROP_PATHS.keys():
		_baked_mesh(String(key))
	_load_scene(BRIDGE_SMALL_PATH)
	_load_scene(FORESTER_HOUSE_PATH)
	_load_scene(LIGHT_TOWER_PATH)
	_ensure_shared_materials()


func decorate_chunk(
	chunk_root: Node3D,
	start_along: float,
	end_along: float,
	seed_value: int,
	terrain,
	edge_post_color: Color
) -> void:
	var scenery_root := Node3D.new()
	scenery_root.name = "Scenery"
	chunk_root.add_child(scenery_root)

	_place_forest_and_undergrowth(scenery_root, start_along, end_along, seed_value, terrain)
	_place_guardrails(scenery_root, start_along, end_along, seed_value, terrain)
	_place_edge_posts(scenery_root, start_along, end_along, seed_value, terrain, edge_post_color)
	_place_roadside_infra(scenery_root, start_along, end_along, seed_value, terrain)
	_place_bridges_and_rivers(scenery_root, start_along, end_along, seed_value, terrain)
	_place_villages(scenery_root, start_along, end_along, seed_value, terrain)


# --------------------------------------------------------- лес и подлесок


func _place_forest_and_undergrowth(
	root: Node3D, start_along: float, end_along: float, seed_value: int, terrain
) -> void:
	var buckets := {}
	for key in [
		"pine", "fir", "birch", "dead_tree",
		"bush", "juniper", "fern", "grass", "grass2", "wildflowers",
		"boulder", "moss_rock", "rock_cluster", "stump", "log",
	]:
		buckets[key] = {"xforms": [] as Array[Transform3D], "colors": [] as Array[Color]}

	var collider_body := StaticBody3D.new()
	collider_body.name = "PropColliders"
	collider_body.collision_layer = 2
	var collider_count: int = 0

	var leg_index: int = RoadType.leg_index_at(start_along)
	var built: RoadType.Leg = RoadType.leg(leg_index, seed_value)

	# 1. Деревья и кусты вдоль полотна и на склонах (шаг 6.5 м).
	var step: float = 6.5
	var along: float = start_along + 2.5
	var row_idx: int = int(floor(start_along / step))
	while along < end_along:
		row_idx += 1
		var domain: int = built.domain_at(along) if built != null else LegType.Kind.COUNTRY
		if domain == LegType.Kind.BRIDGE or (terrain != null and terrain.bridge_deck_factor(along) > 0.15):
			along += step
			continue

		var center: Vector3 = built.point_at(along) if built != null else Vector3.ZERO
		var dir: Vector3 = built.direction_at(along) if built != null else Vector3.FORWARD
		var side := Vector3(dir.z, 0.0, -dir.x)
		var half: float = built.half_width_at(along) if built != null else 5.0
		var cluster: float = DressingType.cluster_factor(along, seed_value)

		var tree_density: float = 1.0
		if domain == LegType.Kind.VILLAGE:
			tree_density = 0.25
		elif domain == LegType.Kind.SERPENTINE:
			tree_density = 0.72
		elif domain == LegType.Kind.FAST:
			tree_density = 0.85

		for side_sign in [-1.0, 1.0]:
			var slot_seed: int = row_idx * 7 + (0 if side_sign < 0.0 else 3)
			# Ближний и дальний ряд деревьев.
			var layers: int = 3 if domain != LegType.Kind.VILLAGE else 1
			for layer in range(layers):
				var l_seed: int = slot_seed * 13 + layer
				var prob: float = (0.38 + 0.42 * clampf(cluster, 0.0, 1.4)) * tree_density
				if layer > 0:
					prob *= 0.82
				if RoadType.roll(l_seed, seed_value, 601) > prob:
					continue
				var lat_min: float = half + 5.2 if layer == 0 else (18.0 if layer == 1 else 36.0)
				var lat_max: float = 17.5 if layer == 0 else (35.0 if layer == 1 else 74.0)
				var lateral: float = RoadType.roll_range(l_seed, seed_value, 602, lat_min, lat_max)
				var jitter_along: float = RoadType.roll_range(l_seed, seed_value, 603, -2.5, 2.5)
				var world_pt: Vector3 = center + dir * jitter_along + side * (lateral * float(side_sign))
				var clearance: float = half + 4.4
				if terrain != null and terrain.distance_to_road(world_pt.x, world_pt.z) < clearance:
					continue

				var ground_y: float = terrain.height_at(world_pt.x, world_pt.z) if terrain != null else center.y
				var species_roll: float = RoadType.roll(l_seed, seed_value, 604)
				var tree_kind: String = "pine"
				if domain == LegType.Kind.SERPENTINE:
					tree_kind = "fir" if species_roll < 0.55 else ("pine" if species_roll < 0.9 else "dead_tree")
				else:
					if species_roll < 0.42:
						tree_kind = "pine"
					elif species_roll < 0.74:
						tree_kind = "fir"
					elif species_roll < 0.94:
						tree_kind = "birch"
					else:
						tree_kind = "dead_tree"

				var s: float = RoadType.roll_range(l_seed, seed_value, 605, 0.72, 1.32)
				var yaw: float = RoadType.roll_range(l_seed, seed_value, 606, 0.0, TAU)
				var xform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * RoadType.roll_range(l_seed, seed_value, 607, 0.9, 1.15), s)), Vector3(world_pt.x, ground_y - 0.14, world_pt.z))
				var shade: float = RoadType.roll_range(l_seed, seed_value, 608, 0.78, 1.05)
				(buckets[tree_kind]["xforms"] as Array[Transform3D]).append(xform)
				(buckets[tree_kind]["colors"] as Array[Color]).append(Color(shade, shade, shade, 1.0))

				if layer == 0 and lateral < 17.5 and collider_count < 64:
					var trunk_shape := CylinderShape3D.new()
					trunk_shape.radius = 0.45 * s
					trunk_shape.height = 3.5 * s
					var col := CollisionShape3D.new()
					col.shape = trunk_shape
					col.position = Vector3(world_pt.x, ground_y + 1.6 * s, world_pt.z)
					collider_body.add_child(col)
					collider_count += 1

			# Валуны и камни (особенно на серпантине и крутых склонах).
			var rock_chance: float = 0.34 if domain == LegType.Kind.SERPENTINE else 0.14
			if RoadType.roll(slot_seed, seed_value, 621) < rock_chance:
				var r_lat: float = RoadType.roll_range(slot_seed, seed_value, 622, half + 3.4, 24.0)
				var r_pt: Vector3 = center + side * (r_lat * float(side_sign))
				if terrain == null or terrain.distance_to_road(r_pt.x, r_pt.z) >= half + 2.8:
					var ry: float = terrain.height_at(r_pt.x, r_pt.z) if terrain != null else center.y
					var r_pick: float = RoadType.roll(slot_seed, seed_value, 623)
					var r_kind: String = "boulder" if r_pick < 0.45 else ("moss_rock" if r_pick < 0.8 else "rock_cluster")
					var rs: float = RoadType.roll_range(slot_seed, seed_value, 624, 0.65, 1.45)
					var ryaw: float = RoadType.roll_range(slot_seed, seed_value, 625, 0.0, TAU)
					var rxform := Transform3D(Basis(Vector3.UP, ryaw).scaled(Vector3(rs, rs * 0.85, rs)), Vector3(r_pt.x, ry - 0.15, r_pt.z))
					var rshade: float = RoadType.roll_range(slot_seed, seed_value, 626, 0.80, 1.05)
					(buckets[r_kind]["xforms"] as Array[Transform3D]).append(rxform)
					(buckets[r_kind]["colors"] as Array[Color]).append(Color(rshade, rshade, rshade, 1.0))
					if r_lat < 14.0 and collider_count < 64:
						var rock_shape := SphereShape3D.new()
						rock_shape.radius = 1.05 * rs
						var rcol := CollisionShape3D.new()
						rcol.shape = rock_shape
						rcol.position = Vector3(r_pt.x, ry + 0.55 * rs, r_pt.z)
						collider_body.add_child(rcol)
						collider_count += 1

			# Подлесок, кусты и трава вдоль обочины.
			for u_i in range(2):
				var u_seed: int = slot_seed * 19 + u_i
				if RoadType.roll(u_seed, seed_value, 641) > 0.72:
					continue
				var u_lat: float = RoadType.roll_range(u_seed, seed_value, 642, half + 2.6, 18.0)
				var u_jitter: float = RoadType.roll_range(u_seed, seed_value, 643, -2.5, 2.5)
				var u_pt: Vector3 = center + dir * u_jitter + side * (u_lat * float(side_sign))
				if terrain != null and terrain.distance_to_road(u_pt.x, u_pt.z) < half + 2.2:
					continue
				var uy: float = terrain.height_at(u_pt.x, u_pt.z) if terrain != null else center.y
				var u_pick: float = RoadType.roll(u_seed, seed_value, 644)
				var u_kind: String = "grass"
				if u_pick < 0.20:
					u_kind = "bush"
				elif u_pick < 0.34:
					u_kind = "juniper"
				elif u_pick < 0.50:
					u_kind = "fern"
				elif u_pick < 0.72:
					u_kind = "grass"
				elif u_pick < 0.90:
					u_kind = "grass2"
				else:
					u_kind = "wildflowers"
				var us: float = RoadType.roll_range(u_seed, seed_value, 645, 0.75, 1.35)
				var uyaw: float = RoadType.roll_range(u_seed, seed_value, 646, 0.0, TAU)
				var uxform := Transform3D(Basis(Vector3.UP, uyaw).scaled(Vector3.ONE * us), Vector3(u_pt.x, uy - 0.05, u_pt.z))
				var ushade: float = RoadType.roll_range(u_seed, seed_value, 647, 0.80, 1.05)
				(buckets[u_kind]["xforms"] as Array[Transform3D]).append(uxform)
				(buckets[u_kind]["colors"] as Array[Color]).append(Color(ushade, ushade, ushade, 1.0))

		along += step

	if collider_count > 0:
		root.add_child(collider_body)
	else:
		collider_body.free()

	for key in buckets.keys():
		var xforms: Array[Transform3D] = buckets[key]["xforms"] as Array[Transform3D]
		var colors: Array[Color] = buckets[key]["colors"] as Array[Color]
		if xforms.is_empty():
			continue
		var is_small: bool = key in ["bush", "juniper", "fern", "grass", "grass2", "wildflowers", "stump", "log"]
		var vis_range: float = SMALL_RANGE if is_small else TREE_RANGE
		_emit_multimesh(root, "MM_" + String(key), _baked_mesh(String(key)), xforms, colors, vis_range)


# ------------------------------------------------------------ отбойники


func _place_guardrails(
	root: Node3D, start_along: float, end_along: float, seed_value: int, terrain
) -> void:
	var rail_mesh: Mesh = _baked_mesh("guardrail")
	if rail_mesh == null:
		return
	var leg_index: int = RoadType.leg_index_at(start_along)
	var built: RoadType.Leg = RoadType.leg(leg_index, seed_value)
	if built == null:
		return

	var xforms: Array[Transform3D] = []
	var rail_body := StaticBody3D.new()
	rail_body.name = "GuardrailCollision"
	rail_body.collision_layer = 2
	var seg_step: float = 4.2
	var lookahead: float = 24.0
	var turn_threshold: float = deg_to_rad(13.5)

	var along: float = start_along
	while along < end_along - 0.5:
		var seg_end: float = minf(along + seg_step, end_along)
		var mid: float = (along + seg_end) * 0.5
		var domain: int = built.domain_at(mid)
		if domain != LegType.Kind.BRIDGE and domain != LegType.Kind.VILLAGE:
			if terrain == null or terrain.bridge_deck_factor(mid) < 0.05:
				var d0: Vector3 = RoadType.leg(RoadType.leg_index_at(maxf(0.0, mid - lookahead * 0.5)), seed_value).direction_at(maxf(0.0, mid - lookahead * 0.5))
				var d1: Vector3 = RoadType.leg(RoadType.leg_index_at(mid + lookahead * 0.5), seed_value).direction_at(mid + lookahead * 0.5)
				var h0: float = atan2(d0.z, d0.x)
				var h1: float = atan2(d1.z, d1.x)
				var turn: float = wrapf(h1 - h0, -PI, PI)
				if absf(turn) >= turn_threshold:
					# При росте heading (+turn) поворот идёт к -side, значит
					# внешний край кривой находится на +side (outer_sign = +1).
					var outer_sign: float = 1.0 if turn > 0.0 else -1.0
					var p_a: Vector3 = built.point_at(along)
					var dir_a: Vector3 = built.direction_at(along)
					var side_a := Vector3(dir_a.z, 0.0, -dir_a.x)
					var lat_a: float = built.half_width_at(along) + 0.95

					var p_b: Vector3 = built.point_at(seg_end)
					var dir_b: Vector3 = built.direction_at(seg_end)
					var side_b := Vector3(dir_b.z, 0.0, -dir_b.x)
					var lat_b: float = built.half_width_at(seg_end) + 0.95

					var wa: Vector3 = p_a + side_a * (lat_a * outer_sign)
					var wb: Vector3 = p_b + side_b * (lat_b * outer_sign)
					var mid_w: Vector3 = (wa + wb) * 0.5
					var clear_ok: bool = true
					if terrain != null and terrain.distance_to_road(mid_w.x, mid_w.z) < built.half_width_at(mid) + 0.55:
						clear_ok = false
					if clear_ok:
						wa.y = terrain.height_at(wa.x, wa.z) if terrain != null else p_a.y - 0.15
						wb.y = terrain.height_at(wb.x, wb.z) if terrain != null else p_b.y - 0.15
						var chord: Vector3 = wb - wa
						var span_len: float = Vector2(chord.x, chord.z).length()
						if span_len > 0.4:
							var inward: Vector3 = (-side_a * outer_sign).normalized()
							var x_axis: Vector3 = Vector3.UP.cross(inward).normalized()
							var scale_x: float = span_len / GUARDRAIL_BAKED_WIDTH
							var xform_basis := Basis(x_axis * scale_x, Vector3.UP, inward)
							var center_pt: Vector3 = (wa + wb) * 0.5
							xforms.append(Transform3D(xform_basis, center_pt))

							var box := BoxShape3D.new()
							box.size = Vector3(span_len + 0.25, 1.4, 0.35)
							var col := CollisionShape3D.new()
							col.shape = box
							col.transform = Transform3D(Basis(x_axis, Vector3.UP, inward), center_pt + Vector3(0.0, 0.65, 0.0))
							rail_body.add_child(col)
		along = seg_end

	if xforms.is_empty():
		rail_body.free()
		return
	root.add_child(rail_body)
	_emit_multimesh(root, "Guardrails", rail_mesh, xforms, [], 260.0)


# --------------------------------------------------------- столбики обочины


func _place_edge_posts(
	root: Node3D, start_along: float, end_along: float, seed_value: int, terrain, post_color: Color
) -> void:
	if _edge_post_mesh == null or _edge_cap_mesh == null:
		var red_mat := StandardMaterial3D.new()
		red_mat.albedo_color = post_color
		red_mat.roughness = 0.82
		var p_mesh := BoxMesh.new()
		p_mesh.size = Vector3(0.11, 0.78, 0.11)
		p_mesh.surface_set_material(0, red_mat)
		_edge_post_mesh = p_mesh

		var white_mat := StandardMaterial3D.new()
		white_mat.albedo_color = Color(0.92, 0.92, 0.90, 1.0)
		white_mat.roughness = 0.72
		var c_mesh := BoxMesh.new()
		c_mesh.size = Vector3(0.13, 0.16, 0.13)
		c_mesh.surface_set_material(0, white_mat)
		_edge_cap_mesh = c_mesh

	var leg_index: int = RoadType.leg_index_at(start_along)
	var built: RoadType.Leg = RoadType.leg(leg_index, seed_value)
	if built == null:
		return

	var post_xforms: Array[Transform3D] = []
	var cap_xforms: Array[Transform3D] = []
	var spacing: float = 22.0
	var d: float = ceilf(start_along / spacing) * spacing
	while d < end_along:
		var domain: int = built.domain_at(d)
		if domain != LegType.Kind.BRIDGE and domain != LegType.Kind.VILLAGE:
			if terrain == null or terrain.bridge_deck_factor(d) < 0.05:
				var center: Vector3 = built.point_at(d)
				var dir: Vector3 = built.direction_at(d)
				var side := Vector3(dir.z, 0.0, -dir.x)
				var lat: float = built.half_width_at(d) + 1.35
				var yaw: float = atan2(dir.x, dir.z)
				for side_sign in [-1.0, 1.0]:
					var pt: Vector3 = center + side * (lat * float(side_sign))
					if terrain != null and terrain.distance_to_road(pt.x, pt.z) < built.half_width_at(d) + 0.9:
						continue
					var py: float = terrain.height_at(pt.x, pt.z) if terrain != null else center.y - 0.35
					post_xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pt.x, py + 0.36, pt.z)))
					cap_xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pt.x, py + 0.76, pt.z)))
		d += spacing

	if not post_xforms.is_empty():
		_emit_multimesh(root, "EdgePosts", _edge_post_mesh, post_xforms, [], 220.0)
		_emit_multimesh(root, "EdgePostCaps", _edge_cap_mesh, cap_xforms, [], 220.0)


# --------------------------------------------------------- ЛЭП и знаки


func _place_roadside_infra(
	root: Node3D, start_along: float, end_along: float, seed_value: int, terrain
) -> void:
	var leg_index: int = RoadType.leg_index_at(start_along)
	var built: RoadType.Leg = RoadType.leg(leg_index, seed_value)
	if built == null:
		return

	var pole_xforms: Array[Transform3D] = []
	var sign_xforms: Array[Transform3D] = []
	var fence_xforms: Array[Transform3D] = []

	var pole_side: float = 1.0 if RoadType.roll(leg_index, seed_value, 701) < 0.5 else -1.0
	var pole_spacing: float = 42.0
	var pd: float = ceilf(start_along / pole_spacing) * pole_spacing
	while pd < end_along:
		var domain: int = built.domain_at(pd)
		if domain == LegType.Kind.COUNTRY or domain == LegType.Kind.VILLAGE:
			if terrain == null or terrain.bridge_deck_factor(pd) < 0.1:
				var center: Vector3 = built.point_at(pd)
				var dir: Vector3 = built.direction_at(pd)
				var side := Vector3(dir.z, 0.0, -dir.x)
				var lat: float = built.half_width_at(pd) + 3.1
				var pt: Vector3 = center + side * (lat * pole_side)
				if terrain == null or terrain.distance_to_road(pt.x, pt.z) >= built.half_width_at(pd) + 2.2:
					var py: float = terrain.height_at(pt.x, pt.z) if terrain != null else center.y - 0.4
					pole_xforms.append(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(pt.x, py - 0.1, pt.z)))
		pd += pole_spacing

	# Предупреждающие знаки на входе в серпантины и перед мостами/деревнями.
	for slot in range(built.domains.size()):
		var d_start: float = built.domain_starts[slot]
		if d_start < start_along or d_start >= end_along:
			continue
		var dom: int = int(built.domains[slot])
		if dom == LegType.Kind.SERPENTINE or dom == LegType.Kind.VILLAGE or dom == LegType.Kind.BRIDGE:
			var sign_along: float = maxf(start_along + 2.0, d_start + 6.0)
			var center: Vector3 = built.point_at(sign_along)
			var dir: Vector3 = built.direction_at(sign_along)
			var side := Vector3(dir.z, 0.0, -dir.x)
			var pt: Vector3 = center + side * (built.half_width_at(sign_along) + 2.0)
			if terrain == null or terrain.distance_to_road(pt.x, pt.z) >= built.half_width_at(sign_along) + 1.5:
				var sy: float = terrain.height_at(pt.x, pt.z) if terrain != null else center.y - 0.3
				var yaw: float = atan2(-dir.x, -dir.z) + 0.18
				sign_xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pt.x, sy, pt.z)))

	# Деревянные изгороди у обочины на просёлке.
	var fd: float = start_along + 18.0
	var f_idx: int = int(floor(start_along / 45.0))
	while fd < end_along - 12.0:
		f_idx += 1
		if built.domain_at(fd) == LegType.Kind.COUNTRY and RoadType.roll(f_idx, seed_value, 731) < 0.38:
			var f_side: float = 1.0 if RoadType.roll(f_idx, seed_value, 732) < 0.5 else -1.0
			for seg in range(3):
				var sa: float = fd + float(seg) * FENCE_BAKED_WIDTH
				if sa >= end_along:
					break
				var center: Vector3 = built.point_at(sa)
				var dir: Vector3 = built.direction_at(sa)
				var side := Vector3(dir.z, 0.0, -dir.x)
				var pt: Vector3 = center + side * ((built.half_width_at(sa) + 2.9) * f_side)
				if terrain != null and terrain.distance_to_road(pt.x, pt.z) < built.half_width_at(sa) + 2.2:
					continue
				var fy: float = terrain.height_at(pt.x, pt.z) if terrain != null else center.y - 0.3
				fence_xforms.append(Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), Vector3(pt.x, fy, pt.z)))
		fd += 45.0

	if not pole_xforms.is_empty():
		_emit_multimesh(root, "PowerPoles", _baked_mesh("power_pole"), pole_xforms, [], TREE_RANGE)
	if not sign_xforms.is_empty():
		_emit_multimesh(root, "RoadSigns", _baked_mesh("road_sign"), sign_xforms, [], SMALL_RANGE)
	if not fence_xforms.is_empty():
		_emit_multimesh(root, "CountryFences", _baked_mesh("fence"), fence_xforms, [], SMALL_RANGE)


# ----------------------------------------------------------- мосты и реки


func _place_bridges_and_rivers(
	root: Node3D, start_along: float, end_along: float, seed_value: int, terrain
) -> void:
	if terrain == null:
		return
	var leg_index: int = RoadType.leg_index_at(start_along)
	var bridges: Array[Dictionary] = terrain.bridges_for_leg(leg_index)
	if bridges.is_empty():
		return
	var bridge_scene := _load_scene(BRIDGE_SMALL_PATH)
	var rock_xforms: Array[Transform3D] = []
	var rock_colors: Array[Color] = []

	for b in bridges:
		var b_along: float = float(b["along"])
		if b_along < start_along or b_along >= end_along:
			continue
		var center: Vector3 = b["center"] as Vector3
		var dir: Vector3 = b["dir"] as Vector3
		var side: Vector3 = b["side"] as Vector3
		var yaw: float = atan2(-dir.z, dir.x)

		if bridge_scene != null:
			var bridge_node := bridge_scene.instantiate() as Node3D
			if bridge_node != null:
				bridge_node.name = "Bridge_%d" % int(round(b_along))
				bridge_node.position = Vector3(center.x, center.y + 0.02, center.z)
				bridge_node.rotation.y = yaw
				# Ширина проезжей части моста: 4.5 м полуширина + обочина -> парапеты
				# на Z = ±6.4 м (исходная сцена bridge_small — ±6.98 м).
				bridge_node.scale = Vector3(1.0, 1.0, 0.92)
				root.add_child(bridge_node)

		# Лента воды на дне ущелья.
		_add_river_ribbon(root, center, dir, side)

		# Прибрежные валуны по обоим берегам реки.
		for ri in range(-10, 11):
			if abs(ri) <= 1:
				continue
			var across: float = float(ri) * 7.0
			var meander: float = sin(across * 0.045) * 4.5
			for bank_sign in [-1.0, 1.0]:
				var bank_seed: int = int(absf(center.x) * 3.0) + ri * 11 + int(bank_sign + 2.0)
				if RoadType.roll(bank_seed, seed_value, 811) > 0.65:
					continue
				var bank_offset: float = meander + float(bank_sign) * RoadType.roll_range(bank_seed, seed_value, 812, 5.5, 9.5)
				var wp: Vector3 = center + side * across + dir * bank_offset
				var wy: float = terrain.height_at(wp.x, wp.z)
				var rs: float = RoadType.roll_range(bank_seed, seed_value, 813, 0.6, 1.35)
				var ryaw: float = RoadType.roll_range(bank_seed, seed_value, 814, 0.0, TAU)
				rock_xforms.append(Transform3D(Basis(Vector3.UP, ryaw).scaled(Vector3(rs, rs * 0.75, rs)), Vector3(wp.x, wy - 0.15, wp.z)))
				rock_colors.append(Color(0.88, 0.90, 0.92, 1.0))

	if not rock_xforms.is_empty():
		_emit_multimesh(root, "RiverRocks", _baked_mesh("river_rock"), rock_xforms, rock_colors, TREE_RANGE)


func _add_river_ribbon(root: Node3D, center: Vector3, dir: Vector3, side: Vector3) -> void:
	_ensure_shared_materials()
	var steps: int = 24
	var half_len: float = 82.0
	var water_half_w: float = 6.2
	var water_y: float = center.y - 5.1

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var across: float = lerpf(-half_len, half_len, t)
		var meander: float = sin(across * 0.045) * 4.5
		var mid: Vector3 = center + side * across + dir * meander
		for w_sign in [-1.0, 1.0]:
			var pt: Vector3 = mid + dir * (water_half_w * float(w_sign))
			vertices.append(Vector3(pt.x, water_y, pt.z))
			normals.append(Vector3.UP)
			uvs.append(Vector2(0.0 if w_sign < 0.0 else 1.0, t * 8.0))

	for i in range(steps):
		var b: int = i * 2
		indices.append(b)
		indices.append(b + 1)
		indices.append(b + 2)
		indices.append(b + 1)
		indices.append(b + 3)
		indices.append(b + 2)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var water_mesh := ArrayMesh.new()
	water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var water_inst := MeshInstance3D.new()
	water_inst.name = "RiverWater"
	water_inst.mesh = water_mesh
	water_inst.material_override = _water_material
	water_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water_inst)


# --------------------------------------------------------------- деревня


func _place_villages(
	root: Node3D, start_along: float, end_along: float, seed_value: int, terrain
) -> void:
	_ensure_shared_materials()
	var leg_index: int = RoadType.leg_index_at(start_along)
	var built: RoadType.Leg = RoadType.leg(leg_index, seed_value)
	if built == null:
		return

	var forester_scene := _load_scene(FORESTER_HOUSE_PATH)
	var lamp_scene := _load_scene(LIGHT_TOWER_PATH)
	var fence_xforms: Array[Transform3D] = []
	var hay_xforms: Array[Transform3D] = []
	var car_xforms: Array[Transform3D] = []

	var placed_houses: int = 0
	for h_raw in built.houses:
		if placed_houses >= 16:
			break
		var house: Vector4 = h_raw as Vector4
		var along: float = _house_along(house, built)
		if along < start_along or along >= end_along:
			continue
		if terrain != null and terrain.distance_to_road(house.x, house.z) < built.half_width_at(along) + 4.2:
			continue
		var gy: float = terrain.height_at(house.x, house.z) if terrain != null else house.y
		var use_forester: bool = (placed_houses % 3 == 0) and forester_scene != null
		if use_forester:
			var lodge := forester_scene.instantiate() as Node3D
			if lodge != null:
				lodge.name = "VillageLodge_%d" % placed_houses
				lodge.position = Vector3(house.x, gy - 0.1, house.z)
				lodge.rotation.y = float(house.w)
				lodge.scale = Vector3.ONE * 1.25
				var win_light := lodge.get_node_or_null("WindowLight") as OmniLight3D
				if win_light != null:
					win_light.visible = is_night
				root.add_child(lodge)
		else:
			_spawn_cottage(root, house, gy, seed_value, placed_houses)

		# Придорожная изгородь перед домом.
		var road_pt: Vector3 = built.point_at(along)
		var dir: Vector3 = built.direction_at(along)
		var side := Vector3(dir.z, 0.0, -dir.x)
		var lat_sign: float = 1.0 if side.dot(Vector3(house.x - road_pt.x, 0.0, house.z - road_pt.z)) >= 0.0 else -1.0
		var fence_pt: Vector3 = road_pt + side * ((built.half_width_at(along) + 2.8) * lat_sign)
		var fy: float = terrain.height_at(fence_pt.x, fence_pt.z) if terrain != null else gy
		fence_xforms.append(Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), Vector3(fence_pt.x, fy, fence_pt.z)))

		# Иногда стог сена или припаркованная машина во дворе.
		var prop_roll: float = RoadType.roll(placed_houses, seed_value, 911)
		if prop_roll < 0.25:
			var side_pt := Vector3(house.x, gy, house.z) + dir * 4.5
			if terrain == null or terrain.distance_to_road(side_pt.x, side_pt.z) >= built.half_width_at(along) + 3.0:
				var hy: float = terrain.height_at(side_pt.x, side_pt.z) if terrain != null else gy
				hay_xforms.append(Transform3D(Basis(Vector3.UP, float(house.w)), Vector3(side_pt.x, hy, side_pt.z)))
		elif prop_roll > 0.78:
			var car_pt := Vector3(house.x, gy, house.z) - dir * 5.0
			if terrain == null or terrain.distance_to_road(car_pt.x, car_pt.z) >= built.half_width_at(along) + 3.0:
				var cy: float = terrain.height_at(car_pt.x, car_pt.z) if terrain != null else gy
				car_xforms.append(Transform3D(Basis(Vector3.UP, float(house.w) + 0.2), Vector3(car_pt.x, cy, car_pt.z)))

		placed_houses += 1

	# Уличные фонари в деревнях (через каждые 32 м).
	var lamp_count: int = 0
	for slot in range(built.domains.size()):
		if int(built.domains[slot]) != LegType.Kind.VILLAGE:
			continue
		var v_start: float = built.domain_starts[slot]
		var v_end: float = built.end_along()
		if slot + 1 < built.domain_starts.size():
			v_end = built.domain_starts[slot + 1]
		var ld: float = maxf(start_along, v_start + 8.0)
		var l_idx: int = 0
		while ld < minf(end_along, v_end - 6.0) and lamp_count < 6:
			var center: Vector3 = built.point_at(ld)
			var dir: Vector3 = built.direction_at(ld)
			var side := Vector3(dir.z, 0.0, -dir.x)
			var l_side: float = 1.0 if (l_idx % 2 == 0) else -1.0
			var l_pt: Vector3 = center + side * ((built.half_width_at(ld) + 2.2) * l_side)
			var ly: float = terrain.height_at(l_pt.x, l_pt.z) if terrain != null else center.y
			if lamp_scene != null:
				var lamp := lamp_scene.instantiate() as Node3D
				if lamp != null:
					lamp.name = "VillageLamp_%d" % lamp_count
					lamp.position = Vector3(l_pt.x, ly - 0.1, l_pt.z)
					lamp.rotation.y = atan2(dir.x, dir.z)
					lamp.scale = Vector3.ONE * 0.95
					var omni := lamp.get_node_or_null("Lamp") as OmniLight3D
					if omni != null:
						omni.visible = is_night
						omni.omni_range = 24.0
						omni.light_energy = 2.2
					root.add_child(lamp)
			lamp_count += 1
			l_idx += 1
			ld += 32.0

	if not fence_xforms.is_empty():
		_emit_multimesh(root, "VillageFences", _baked_mesh("fence"), fence_xforms, [], SMALL_RANGE)
	if not hay_xforms.is_empty():
		_emit_multimesh(root, "VillageHay", _baked_mesh("hay_bale"), hay_xforms, [], SMALL_RANGE)
	if not car_xforms.is_empty():
		_emit_multimesh(root, "VillageCars", _baked_mesh("parked_car"), car_xforms, [], SMALL_RANGE)


func _spawn_cottage(root: Node3D, house: Vector4, ground_y: float, seed_value: int, index: int) -> void:
	var h_seed: int = int(absf(house.x) * 19.0) + index * 31
	var scale_val: float = RoadType.roll_range(index, h_seed ^ seed_value, 351, 0.92, 1.24)
	var box_size := Vector3(6.8, 3.1, 5.2) * scale_val

	var cottage := Node3D.new()
	cottage.name = "Cottage_%d" % index
	cottage.position = Vector3(house.x, ground_y - 0.12, house.z)
	cottage.rotation.y = float(house.w)

	var walls := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = box_size
	walls.mesh = body_mesh
	walls.material_override = _wall_material if (index % 2 == 0) else _plank_material
	walls.position = Vector3(0.0, box_size.y * 0.5, 0.0)
	cottage.add_child(walls)

	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(box_size.z * 1.12, box_size.y * 0.58, box_size.x * 1.08)
	roof.mesh = prism
	roof.material_override = _roof_slate_material
	roof.position = Vector3(0.0, box_size.y + prism.size.y * 0.5, 0.0)
	cottage.add_child(roof)

	# Труба.
	var chimney := MeshInstance3D.new()
	var ch_mesh := BoxMesh.new()
	ch_mesh.size = Vector3(0.55, 1.25, 0.55) * scale_val
	chimney.mesh = ch_mesh
	chimney.material_override = _roof_slate_material
	chimney.position = Vector3(box_size.x * 0.25, box_size.y + prism.size.y * 0.72, -box_size.z * 0.16)
	cottage.add_child(chimney)

	# Светящиеся (ночью) окна на двух фасадах и дверь.
	var win_mat: StandardMaterial3D = _window_lit_material if is_night else _window_day_material
	var win_mesh := BoxMesh.new()
	win_mesh.size = Vector3(0.85, 0.95, 0.08) * scale_val
	for side_z in [-1.0, 1.0]:
		for wx in [-1.4 * scale_val, 1.4 * scale_val]:
			var win := MeshInstance3D.new()
			win.mesh = win_mesh
			win.material_override = win_mat
			win.position = Vector3(wx, box_size.y * 0.55, float(side_z) * (box_size.z * 0.5 + 0.03))
			cottage.add_child(win)

	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.95, 1.9, 0.08) * scale_val
	door.mesh = door_mesh
	door.material_override = _door_material
	door.position = Vector3(0.0, 0.95 * scale_val, box_size.z * 0.5 + 0.03)
	cottage.add_child(door)

	root.add_child(cottage)


static func _house_along(house: Vector4, built: RoadType.Leg) -> float:
	var best: float = INF
	var best_along: float = 0.0
	for i in range(0, built.points.size(), 4):
		var p: Vector3 = built.points[i]
		var d: float = (p.x - house.x) * (p.x - house.x) + (p.z - house.z) * (p.z - house.z)
		if d < best:
			best = d
			best_along = built.along[i]
	return best_along


# ------------------------------------------------------- общие материалы / MultiMesh


func _ensure_shared_materials() -> void:
	if _water_material == null:
		_water_material = StandardMaterial3D.new()
		_water_material.albedo_color = Color(0.08, 0.24, 0.34, 0.86)
		_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_material.roughness = 0.14
		_water_material.metallic = 0.15
		_water_material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX

	if _wall_material == null:
		_wall_material = StandardMaterial3D.new()
		_wall_material.albedo_color = Color(0.84, 0.80, 0.72, 1.0)
		if ResourceLoader.exists(WALL_TEX_PATH):
			_wall_material.albedo_texture = ResourceLoader.load(WALL_TEX_PATH) as Texture2D
		_wall_material.roughness = 0.94
		if ps1_filter:
			_wall_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS

	if _plank_material == null:
		_plank_material = StandardMaterial3D.new()
		_plank_material.albedo_color = Color(0.68, 0.54, 0.38, 1.0)
		if ResourceLoader.exists(PLANK_TEX_PATH):
			_plank_material.albedo_texture = ResourceLoader.load(PLANK_TEX_PATH) as Texture2D
		_plank_material.roughness = 0.94
		if ps1_filter:
			_plank_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS

	if _roof_slate_material == null:
		_roof_slate_material = StandardMaterial3D.new()
		_roof_slate_material.albedo_color = Color(0.45, 0.32, 0.28, 1.0)
		if ResourceLoader.exists(SLATE_TEX_PATH):
			_roof_slate_material.albedo_texture = ResourceLoader.load(SLATE_TEX_PATH) as Texture2D
		_roof_slate_material.roughness = 0.88
		if ps1_filter:
			_roof_slate_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS

	if _window_lit_material == null:
		_window_lit_material = StandardMaterial3D.new()
		_window_lit_material.albedo_color = Color(1.0, 0.78, 0.38, 1.0)
		_window_lit_material.emission_enabled = true
		_window_lit_material.emission = Color(1.0, 0.74, 0.32, 1.0)
		_window_lit_material.emission_energy_multiplier = 1.6

	if _window_day_material == null:
		_window_day_material = StandardMaterial3D.new()
		_window_day_material.albedo_color = Color(0.22, 0.30, 0.38, 1.0)
		_window_day_material.roughness = 0.25

	if _door_material == null:
		_door_material = StandardMaterial3D.new()
		_door_material.albedo_color = Color(0.24, 0.16, 0.10, 1.0)
		_door_material.roughness = 0.9


func _emit_multimesh(
	parent: Node3D,
	node_label: String,
	mesh: Mesh,
	xforms: Array[Transform3D],
	colors: Array[Color],
	vis_range: float
) -> void:
	if mesh == null or xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors and i < colors.size():
			mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = node_label
	inst.multimesh = mm
	inst.visibility_range_end = vis_range
	inst.visibility_range_end_margin = 28.0
	if vis_range <= SMALL_RANGE:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


func _load_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path] as PackedScene
	if not ResourceLoader.exists(path):
		return null
	var packed := ResourceLoader.load(path) as PackedScene
	_scene_cache[path] = packed
	return packed


func _baked_mesh(key: String) -> Mesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key] as Mesh
	var path: String = String(PROP_PATHS.get(key, ""))
	if path.is_empty():
		return null
	var packed := _load_scene(path)
	if packed == null:
		return null
	var inst_root := packed.instantiate() as Node3D
	if inst_root == null:
		return null
	var mats: Array = []
	var groups: Array = []
	_collect_surfaces(inst_root, mats, groups, Transform3D())
	inst_root.free()
	var out_mesh := ArrayMesh.new()
	for g in range(mats.size()):
		var group: Array = groups[g] as Array
		var v_arr: PackedVector3Array = group[0] as PackedVector3Array
		if v_arr.is_empty():
			continue
		var surface: Array = []
		surface.resize(Mesh.ARRAY_MAX)
		surface[Mesh.ARRAY_VERTEX] = v_arr
		surface[Mesh.ARRAY_NORMAL] = group[1]
		surface[Mesh.ARRAY_TEX_UV] = group[2]
		surface[Mesh.ARRAY_INDEX] = group[3]
		out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
		var surf_idx: int = out_mesh.get_surface_count() - 1
		if surf_idx < 0:
			continue
		var mat_entry = mats[g]
		if mat_entry != null:
			mat_entry = (mat_entry as Material).duplicate()
			if mat_entry is BaseMaterial3D and ps1_filter:
				(mat_entry as BaseMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		out_mesh.surface_set_material(surf_idx, mat_entry)
	if out_mesh.get_surface_count() == 0:
		_mesh_cache[key] = null
		return null
	_mesh_cache[key] = out_mesh
	return out_mesh


static func _collect_surfaces(
	node: Node, mats: Array, groups: Array, parent_xform: Transform3D
) -> void:
	if node == null:
		return
	var xform: Transform3D = parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var src: Mesh = mi.mesh
		if src != null:
			var normal_basis: Basis = xform.basis.inverse().transposed()
			for s in range(src.get_surface_count()):
				var arrays: Array = src.surface_get_arrays(s)
				var verts := PackedVector3Array()
				if arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
					verts = arrays[Mesh.ARRAY_VERTEX]
				if verts.is_empty():
					continue
				var src_norms := PackedVector3Array()
				if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
					src_norms = arrays[Mesh.ARRAY_NORMAL]
				var src_uvs := PackedVector2Array()
				if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
					src_uvs = arrays[Mesh.ARRAY_TEX_UV]
				var src_idx := PackedInt32Array()
				if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
					src_idx = arrays[Mesh.ARRAY_INDEX]
				var mat_ref = mi.get_active_material(s)
				var slot: int = mats.find(mat_ref)
				if slot < 0:
					slot = mats.size()
					mats.append(mat_ref)
					groups.append([
						PackedVector3Array(),
						PackedVector3Array(),
						PackedVector2Array(),
						PackedInt32Array(),
					])
				var group: Array = groups[slot] as Array
				var v_out: PackedVector3Array = group[0] as PackedVector3Array
				var n_out: PackedVector3Array = group[1] as PackedVector3Array
				var uv_out: PackedVector2Array = group[2] as PackedVector2Array
				var i_out: PackedInt32Array = group[3] as PackedInt32Array
				var base: int = v_out.size()
				var has_n: bool = src_norms.size() == verts.size()
				var has_uv: bool = src_uvs.size() == verts.size()
				for v in range(verts.size()):
					v_out.append(xform * verts[v])
					n_out.append((normal_basis * (src_norms[v] if has_n else Vector3.UP)).normalized())
					uv_out.append(src_uvs[v] if has_uv else Vector2.ZERO)
				if src_idx.is_empty():
					for v2 in range(verts.size()):
						i_out.append(base + v2)
				else:
					for idx in src_idx:
						i_out.append(base + int(idx))
				group[0] = v_out
				group[1] = n_out
				group[2] = uv_out
				group[3] = i_out
	for child in node.get_children():
		_collect_surfaces(child, mats, groups, xform)
