class_name CrowdMoodMeter
extends Node
## "Soothing the Masses" / "Soothing riots": a shared mood meter for a group
## of `CrowdMember`s (group `"crowd_mood"`). Brass (soothe) pulls `mood`
## toward 0 (calm); zinc (riot) pushes it toward 100 (violent). Idle mood
## drifts slowly back to `neutral_mood` so the player has to keep working the
## crowd rather than land one Push and walk away.
##
## `MissionDirector`'s `crowd_mood` objective type polls the first node in
## this group for its `mood` property; `ActivityManager`'s `crowd_riot`
## activity type does the same for the "Soothing riots" side activity.

signal mood_changed(mood: float)

@export var neutral_mood := 50.0
@export var drift_per_sec := 1.5
@export var soothe_gain := -14.0
@export var riot_gain := 14.0

var mood: float = 50.0


func _ready() -> void:
	add_to_group(&"crowd_mood")
	mood = neutral_mood


func _process(delta: float) -> void:
	if absf(mood - neutral_mood) < 0.01:
		return
	var step := drift_per_sec * delta
	if mood > neutral_mood:
		mood = maxf(neutral_mood, mood - step)
	else:
		mood = minf(neutral_mood, mood + step)
	mood_changed.emit(mood)


## Called by `CrowdMember.receive_emotional_allomancy` when the player
## targets any member of the crowd.
func apply(kind: StringName, strength: float) -> void:
	var delta := (soothe_gain if kind == &"soothe" else riot_gain) * clampf(strength, 0.0, 1.0)
	mood = clampf(mood + delta, 0.0, 100.0)
	mood_changed.emit(mood)
