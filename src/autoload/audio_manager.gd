extends Node
## Pooled positional/UI audio playback and music layers.
## STUB — owned by the audio agent; see docs/ARCHITECTURE.md for the API.


func play_3d(_id: StringName, _position: Vector3, _volume_db := 0.0, _pitch := 1.0) -> void:
	pass


func play_ui(_id: StringName, _volume_db := 0.0) -> void:
	pass


func set_music_intensity(_level: float) -> void:
	pass
