@tool
class_name MenuDriveRecording
extends Resource

## Четыре значения на физический кадр: газ, тормоз, руль, ручник.
## Это управляющие воздействия, не позиции машины.
@export var physics_fps: int = 60
@export var frames := PackedFloat32Array()

func frame_count() -> int:
	return frames.size() / 4

func valid() -> bool:
	return physics_fps > 0 and frames.size() >= 4 and frames.size() % 4 == 0
