# godot --headless --path . --script res://tests/prop_lod.gd
extends SceneTree

const LOD = preload("res://scripts/track/prop_lod.gd")
const Stage = preload("res://scripts/rally_stage.gd")
const StageSettings = preload("res://scripts/data/rally_stage_settings.gd")
const Scenery = preload("res://scripts/data/rally_scenery_config.gd")
const Prop = preload("res://scripts/data/rally_prop.gd")

func _initialize() -> void:
	call_deferred("_test")

func _test() -> void:
	var original := CylinderMesh.new()
	original.radial_segments = 7
	original.rings = 1
	var original_material := StandardMaterial3D.new()
	original.material = original_material
	var base: Array = original.surface_get_arrays(0)
	var middle: Array = LOD.primitive_at_level(original, 1).surface_get_arrays(0)
	var far: Array = LOD.primitive_at_level(original, 2).surface_get_arrays(0)
	var built: Dictionary = LOD.surface_with_lods(base, middle, far, 2.0)
	var lods: Dictionary = built["lods"]
	assert(lods.size() == 2, "три настоящих уровня меша")
	var keys: Array = lods.keys()
	keys.sort()
	var count0: int = (base[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	var count1: int = (lods[keys[0]] as PackedInt32Array).size()
	var count2: int = (lods[keys[1]] as PackedInt32Array).size()
	assert(count0 > count1 and count1 > count2, "дальние уровни содержат меньше треугольников")
	var vertices: PackedVector3Array = built["arrays"][Mesh.ARRAY_VERTEX]
	for key in keys:
		for index in lods[key]:
			assert(index >= 0 and index < vertices.size(), "индексы указывают на добавленные вершины")
	var mesh: Mesh = LOD.mesh_with_lods(original)
	assert(mesh != original and mesh.surface_get_material(0) == original_material)
	assert(original.radial_segments == 7 and original.rings == 1, "исходная сцена не меняется")
	var imported := ImporterMesh.from_mesh(mesh)
	assert(imported.get_surface_lod_count(0) == 2, "рендерер получил оба LOD")
	assert(imported.get_surface_lod_indices(0, 0).size() == count1)
	assert(imported.get_surface_lod_indices(0, 1).size() == count2)

	# Плоскость нельзя упростить без разрушения: она остаётся нетронутой.
	var quad := QuadMesh.new()
	assert(LOD.mesh_with_lods(quad) == quad)

	# Процедурные MultiMesh используют тот же механизм, включая материалы.
	var stage = Stage.new()
	stage.settings = StageSettings.new()
	stage.scenery = Scenery.new()
	var prop = Prop.new()
	prop.scene = load("res://scenes/props/fir_tree.tscn")
	var baked: Mesh = stage._bake_prop_mesh(prop)
	assert(baked.get_surface_count() >= 1)
	var baked_import := ImporterMesh.from_mesh(baked)
	var found := false
	for surface in range(baked_import.get_surface_count()):
		if baked_import.get_surface_lod_count(surface) == 2:
			found = true
			assert(baked_import.get_surface_lod_indices(surface, 0).size() > baked_import.get_surface_lod_indices(surface, 1).size())
	assert(found, "у процедурной ели есть три уровня")

	# Вручную поставленная сосна сохраняет коллайдер, материал и трансформы.
	stage.settings.scenery_lod_enabled = false
	var disabled: Mesh = stage._bake_prop_mesh(prop)
	var disabled_import := ImporterMesh.from_mesh(disabled)
	for surface in range(disabled_import.get_surface_count()):
		assert(disabled_import.get_surface_lod_count(surface) == 0, "выключатель отключает генерацию LOD")
	stage.settings.scenery_lod_enabled = true
	var root_node := Node3D.new()
	root_node.name = "StudioProps"
	stage.add_child(root_node)
	var pine: Node3D = load("res://scenes/props/pine_tree.tscn").instantiate()
	root_node.add_child(pine)
	var body: Node = pine.get_node("Body")
	var trunk := pine.get_node("Trunk") as MeshInstance3D
	var trunk_mesh: Mesh = trunk.mesh
	var trunk_transform := trunk.transform
	var duplicate := MeshInstance3D.new()
	duplicate.mesh = trunk_mesh
	root_node.add_child(duplicate)
	await stage._setup_authored_prop_lods()
	assert(trunk.mesh != trunk_mesh and duplicate.mesh == trunk.mesh, "копии используют один кешированный меш")
	assert(trunk.transform == trunk_transform and pine.get_node("Body") == body)
	assert(ImporterMesh.from_mesh(trunk.mesh).get_surface_lod_count(0) == 2)
	stage.free()
	print("Prop LOD: OK")
	quit(0)
