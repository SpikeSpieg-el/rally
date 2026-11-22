# godot --headless --path . --script res://tests/sponsor_banner.gd
# ЖК-щит спонсора (scenes/props/sponsor_banner.tscn):
#   * оба экрана щита рисуются шейдером с атласом textures/4XSponsorBanners.png;
#   * материал лежит в сцене — значит, попадает и в запечённый MultiMesh трассы;
#   * баннеры идут по кругу 0→1→2→3→0 с шагом cycle_time;
#   * правка в инспекторе (cycle_time, сетка атласа) доходит до материала.
extends SceneTree

const BannerScene := preload("res://scenes/props/sponsor_banner.tscn")
const ATLAS := preload("res://textures/4XSponsorBanners.png")
const SHADER := preload("res://shaders/sponsor_banner.gdshader")

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)
	else:
		print("PASS: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Как при запекании пропсов: сцена вне дерева, скрипт ещё не отработал.
	var baked := BannerScene.instantiate() as Node3D
	var front := baked.get_node_or_null("Mesh_screen_front") as MeshInstance3D
	var back := baked.get_node_or_null("Mesh_screen_back") as MeshInstance3D
	check(front != null and back != null, "у щита есть лицевой и задний экран")
	if front == null or back == null:
		_finish()
		return
	var baked_material := front.get_active_material(0) as ShaderMaterial
	check(
		baked_material != null and baked_material.shader == SHADER, "экран рисуется шейдером щита"
	)
	check(
		baked_material != null and baked_material.get_shader_parameter("banner_atlas") == ATLAS,
		"атлас 4XSponsorBanners.png лежит в материале сцены (виден в MultiMesh)"
	)
	check(back.get_active_material(0) == baked_material, "задний экран делит материал с лицевым")
	check(
		back.transform.basis.z.dot(front.transform.basis.z) < -0.99,
		"задний экран смотрит в обратную сторону"
	)
	baked.free()

	var banner := BannerScene.instantiate() as RallySponsorBanner
	root.add_child(banner)
	await process_frame
	check(banner.screen_materials().size() == 1, "один материал на оба экрана")
	var order: Array[int] = []
	for i in range(5):
		order.append(banner.current_banner(banner.cycle_time * (float(i) + 0.5)))
	check(str(order) == "[0, 1, 2, 3, 0]", "баннеры идут по кругу: %s" % str(order))
	banner.cycle_time = 5.0
	banner.atlas_grid = Vector2i(4, 1)
	var material: ShaderMaterial = banner.screen_materials()[0]
	check(
		is_equal_approx(float(material.get_shader_parameter("cycle_time")), 5.0),
		"cycle_time доходит до шейдера"
	)
	check(
		material.get_shader_parameter("atlas_grid") == Vector2i(4, 1),
		"сетка атласа доходит до шейдера"
	)
	var other := BannerScene.instantiate() as RallySponsorBanner
	root.add_child(other)
	await process_frame
	check(
		is_equal_approx(float(other.screen_materials()[0].get_shader_parameter("cycle_time")), 3.0),
		"настройки одного щита не меняют другие"
	)
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("OK: щит спонсора")
		quit(0)
	else:
		printerr("щит спонсора: %d проблем(ы)" % failures.size())
		quit(1)
