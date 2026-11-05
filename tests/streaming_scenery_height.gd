# godot --headless --path . --script res://tests/streaming_scenery_height.gd
# Placement must agree with the actual streamed triangles, including before
# a terrain tile is available and across negative-coordinate tile seams.
extends SceneTree

const Stage = preload("res://scripts/rally_stage.gd")
const Streamer = preload("res://scripts/world_streamer.gd")
const TerrainJob = preload("res://scripts/stream_terrain_job.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")
const Network = preload("res://scripts/road_network.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func expected_height(job, gx: int, gz: int, u: float, v: float) -> float:
	var index: int = gz * job.width + gx
	var h00: float = job.vertices[index].y
	var h10: float = job.vertices[index + 1].y
	var h01: float = job.vertices[index + job.width].y
	var h11: float = job.vertices[index + job.width + 1].y
	if u + v <= 1.0:
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	return h11 * (u + v - 1.0) + h10 * (1.0 - v) + h01 * (1.0 - u)

func _run() -> void:
	var stage = Stage.new()
	stage.track = Track.new()
	stage.track.terrain_seed = 4711
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, -300))
	curve.add_point(Vector3(0, 25, 300))
	stage.network = Network.build_sparse(curve)
	stage._setup_noise()
	var streamer = Streamer.new()
	stage.add_child(streamer)
	streamer.stage = stage
	stage.world_streamer = streamer
	for key in [Vector2i(-1, -1), Vector2i(0, 0), Vector2i(1, -1)]:
		var job = TerrainJob.new(stage, key, streamer.TILE_SIZE, streamer.TILE_DIVISIONS)
		job.advance(0)
		var body := Node3D.new()
		body.set_meta("terrain_heights", job.heights)
		streamer.add_child(body)
		for cell_pos in [Vector2i(0, 0), Vector2i(7, 8), Vector2i(15, 15)]:
			for uv in [Vector2(0.2, 0.3), Vector2(0.8, 0.7), Vector2(0.5, 0.5)]:
				var x: float = job.origin.x + (float(cell_pos.x) + uv.x) * job.cell
				var z: float = job.origin.z + (float(cell_pos.y) + uv.y) * job.cell
				var expected := expected_height(job, cell_pos.x, cell_pos.y, uv.x, uv.y)
				# Scenery can be built before the tile's worker finishes.
				streamer.tiles.erase(key)
				check(absf(stage.ground_height(x, z) - expected) < 0.001, "unloaded tile %s at %s" % [key, uv])
				streamer.tiles[key] = body
				check(absf(stage.ground_height(x, z) - expected) < 0.001, "loaded tile %s at %s" % [key, uv])
		streamer.tiles.erase(key)
		body.free()
	stage.free()
	print("Streamed scenery height: %d failures" % failures)
	quit(0 if failures == 0 else 1)
