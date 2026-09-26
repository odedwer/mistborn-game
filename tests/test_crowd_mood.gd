extends TestCase
## `CrowdMoodMeter`/`CrowdMember` (Act II): a shared crowd-temper meter driven
## by zinc (riot) / brass (soothe) through `receive_emotional_allomancy`, and
## the player's emotional targeting reaching `CrowdMember`s at all.

func test_meter_starts_neutral_and_drifts_back() -> void:
	var meter := CrowdMoodMeter.new()
	add_child(meter)
	meter.mood = 90.0
	meter._process(1.0)
	assert_true(meter.mood < 90.0, "mood should drift back toward neutral")
	assert_true(meter.mood >= meter.neutral_mood)
	meter.queue_free()


func test_soothe_lowers_mood_and_riot_raises_it() -> void:
	var meter := CrowdMoodMeter.new()
	add_child(meter)
	meter.mood = 50.0
	meter.apply(&"soothe", 1.0)
	assert_true(meter.mood < 50.0)
	meter.mood = 50.0
	meter.apply(&"riot", 1.0)
	assert_true(meter.mood > 50.0)
	meter.queue_free()


func test_mood_clamped_to_0_100() -> void:
	var meter := CrowdMoodMeter.new()
	add_child(meter)
	meter.mood = 5.0
	for i in 20:
		meter.apply(&"soothe", 1.0)
	assert_eq(meter.mood, 0.0)
	meter.queue_free()


## `CrowdMember.receive_emotional_allomancy` forwards to the scene's
## `CrowdMoodMeter` (found via group `"crowd_mood"`) instead of holding its
## own soothed/riled state.
func test_crowd_member_forwards_to_shared_meter() -> void:
	var meter := CrowdMoodMeter.new()
	add_child(meter)
	meter.mood = 50.0
	var member := CrowdMember.new()
	add_child(member)
	assert_true(member.is_in_group(&"enemy"), "crowd members must be targetable by zinc/brass")
	member.receive_emotional_allomancy(&"riot", 1.0)
	assert_true(meter.mood > 50.0)
	member.queue_free()
	meter.queue_free()
