## Optional PC OpenXR mode. The normal desktop renderer/input remain untouched.
extends Node

signal mode_changed(enabled: bool)

var enabled := false
var requested := false
var interface: XRInterface
var rig: XROrigin3D
var headset: XRCamera3D
var left: XRController3D
var right: XRController3D
var stage: Node3D
var car: RallyCar
var overlay: Label3D
var _pressed: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(_on_scene_changed)

func start() -> bool:
	if requested:
		return true
	interface = XRServer.find_interface("OpenXR")
	if interface == null:
		return false
	# Keep menus on the desktop until a stage is loaded: the headset only
	# starts rendering once a tracked camera exists in the world.
	requested = true
	mode_changed.emit(true)
	return true

func stop() -> void:
	_detach()
	requested = false
	if enabled:
		get_viewport().use_xr = false
		if interface != null:
			interface.uninitialize()
	enabled = false
	interface = null
	mode_changed.emit(false)

func _on_scene_changed(scene: Node) -> void:
	_detach()
	if requested and scene is RallyStage:
		attach.call_deferred(scene)
	elif enabled:
		# Menus use the ordinary screen, even when VR remains selected.
		get_viewport().use_xr = false

func attach(target: Node3D) -> void:
	if not requested or rig != null or not is_instance_valid(target):
		return
	if not enabled:
		if interface == null or not interface.initialize():
			stop()
			return
		enabled = true
	stage = target
	car = target.get_node_or_null("RallyCar") as RallyCar
	if car == null:
		return
	car.camera_mode = RallyCar.CameraMode.COCKPIT_1ST
	car.active_camera.current = false
	rig = XROrigin3D.new()
	rig.name = "DriverXR"
	stage.add_child(rig)
	headset = XRCamera3D.new()
	headset.far = 850.0
	rig.add_child(headset)
	left = XRController3D.new()
	left.tracker = &"left_hand"
	rig.add_child(left)
	right = XRController3D.new()
	right.tracker = &"right_hand"
	rig.add_child(right)
	overlay = Label3D.new()
	overlay.font_size = 32
	overlay.pixel_size = 0.001
	overlay.position = Vector3(0, -0.32, -0.8)
	overlay.no_depth_test = true
	headset.add_child(overlay)
	get_viewport().use_xr = true

func _detach() -> void:
	for action in _pressed:
		if _pressed[action]:
			Input.action_release(action)
	_pressed.clear()
	if is_instance_valid(rig):
		rig.queue_free()
	rig = null
	headset = null
	left = null
	right = null
	overlay = null
	car = null
	stage = null

func _process(_delta: float) -> void:
	if not enabled or not is_instance_valid(car) or not is_instance_valid(rig):
		return
	# Use the fixed cockpit marker, not the shaken/zoomed desktop camera.
	# Head tracking is composed by OpenXR after this transform.
	rig.global_transform = car.cam_cockpit.global_transform
	if car.camera_mode != RallyCar.CameraMode.COCKPIT_1ST:
		car.camera_mode = RallyCar.CameraMode.COCKPIT_1ST
	var paused: bool = bool(stage.get("is_paused"))
	if is_instance_valid(overlay):
		overlay.text = "ПАУЗА — меню на экране ПК" if paused else "%d км/ч   %s" % [roundi(car.speed_kmh), str(car.current_gear)]
	# Godot's default OpenXR action map: triggers and primary thumbsticks.
	# Inject actions so the existing driving physics, gearbox and pause logic
	# continue to use the same input pipeline as keyboard/gamepad.
	var steer := left.get_vector2(&"primary").x if left.get_is_active() else 0.0
	_set_action(&"steer_left", steer, steer > 0.15 and not paused)
	_set_action(&"steer_right", -steer, steer < -0.15 and not paused)
	_set_action(&"throttle", right.get_float(&"trigger"), not paused)
	_set_action(&"brake", left.get_float(&"trigger"), not paused)
	_set_action(&"handbrake", left.is_button_pressed(&"grip_click"), not paused)
	_set_action(&"shift_up", right.is_button_pressed(&"primary_click"), not paused)
	_set_action(&"shift_down", left.is_button_pressed(&"primary_click"), not paused)
	_set_action(&"pause", left.is_button_pressed(&"menu_button") or right.is_button_pressed(&"menu_button"), true)
	# Head rotation is tracked; no artificial steering of the XR camera.

func _set_action(action: StringName, value: Variant, allowed: bool) -> void:
	var strength: float = float(value) if value is float else (1.0 if value else 0.0)
	var down := allowed and strength > 0.15
	if down:
		Input.action_press(action, clampf(strength, 0.0, 1.0))
	elif _pressed.get(action, false):
		Input.action_release(action)
	_pressed[action] = down
