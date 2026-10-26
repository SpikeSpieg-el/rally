class_name RallyEngineSound
extends AudioStreamPlayer3D

const RallyCarType = preload("res://scripts/rally_car.gd")

const MIX_RATE: float = 22050.0
const FLUTTER_DURATION: float = 0.35

@onready var car: RallyCarType = get_parent() as RallyCarType

var generator: AudioStreamGenerator = null
var playback: AudioStreamGeneratorPlayback = null
var engine_phase: float = 0.0
var flutter_phase: float = 0.0
var filtered_noise: float = 0.0
var previous_throttle: float = 0.0
var flutter_remaining: float = 0.0
var synthesis_enabled: bool = true


func _ready() -> void:
	generator = stream as AudioStreamGenerator
	if generator == null:
		generator = AudioStreamGenerator.new()
		stream = generator
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.12
	# Dummy audio has no output callback and cannot retire active generator playbacks.
	synthesis_enabled = DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy"
	if not synthesis_enabled:
		return
	play()
	playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _exit_tree() -> void:
	if synthesis_enabled:
		stop()
	playback = null
	generator = null


func _process(delta: float) -> void:
	if not synthesis_enabled or car == null:
		return
	if playback == null:
		playback = get_stream_playback() as AudioStreamGeneratorPlayback
		if playback == null:
			return

	var throttle: float = car.throttle_input
	if previous_throttle > 0.35 and throttle < 0.12 and car.current_rpm > 3000.0:
		flutter_remaining = FLUTTER_DURATION
	previous_throttle = throttle
	flutter_remaining = maxf(0.0, flutter_remaining - delta)
	_fill_audio_buffer()


func _fill_audio_buffer() -> void:
	var frames_available: int = playback.get_frames_available()
	var fundamental_hz: float = clampf(car.current_rpm / 60.0 * 2.0, 24.0, 280.0)
	var phase_step: float = fundamental_hz / MIX_RATE
	var flutter_envelope: float = flutter_remaining / FLUTTER_DURATION

	for frame_index in range(frames_available):
		var sawtooth: float = 0.0
		for harmonic in range(1, 7):
			var harmonic_float: float = float(harmonic)
			sawtooth += sin(engine_phase * TAU * harmonic_float) / harmonic_float
		sawtooth *= 0.42

		var white_noise: float = randf_range(-1.0, 1.0)
		filtered_noise = lerpf(filtered_noise, white_noise, 0.075)

		var flutter_sample: float = 0.0
		if flutter_envelope > 0.0:
			var flutter_gate: float = 0.35 + 0.65 * absf(sin(flutter_phase * TAU))
			flutter_sample = filtered_noise * flutter_gate * flutter_envelope
			flutter_phase = fmod(flutter_phase + 27.0 / MIX_RATE, 1.0)

		var engine_load: float = 0.62 + car.throttle_input * 0.38
		var sample: float = (sawtooth * 0.30 + filtered_noise * 0.075) * engine_load
		sample += flutter_sample * 0.24
		sample = clampf(sample, -0.92, 0.92)
		playback.push_frame(Vector2(sample, sample))
		engine_phase = fmod(engine_phase + phase_step, 1.0)
