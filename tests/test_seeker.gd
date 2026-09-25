extends TestCase
## `Seeker` (Act II, `src/enemies/seeker.gd`): senses the player's own
## allomantic pulses (`Events.allomantic_pulse`) instead of relying only on
## sight/sound. Copper suppresses the pulse at the source
## (`Allomancer._tick_pulses`), so a Seeker within range reacts to a pulse
## that arrives, and simply never hears one that doesn't.

var _seeker: Seeker


func before_each() -> void:
	var scene: PackedScene = load("res://src/enemies/seeker.tscn")
	_seeker = scene.instantiate()
	add_child(_seeker)
	_seeker.global_position = Vector3.ZERO


func after_each() -> void:
	if is_instance_valid(_seeker):
		_seeker.queue_free()


func _fake_source(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	return n


func test_close_pulse_alarms_straight_to_combat() -> void:
	var src := _fake_source(Vector3(3, 0, 0))
	Events.allomantic_pulse.emit(src, Metal.Type.STEEL, src.global_position)
	assert_eq(_seeker.state, EnemyBase.State.COMBAT)
	assert_eq(_seeker.target, src)
	src.queue_free()


func test_far_pulse_within_sense_range_investigates() -> void:
	var src := _fake_source(Vector3(15, 0, 0))
	Events.allomantic_pulse.emit(src, Metal.Type.IRON, src.global_position)
	assert_eq(_seeker.state, EnemyBase.State.INVESTIGATE)
	src.queue_free()


func test_pulse_far_beyond_sense_range_is_ignored() -> void:
	var src := _fake_source(Vector3(500, 0, 0))
	Events.allomantic_pulse.emit(src, Metal.Type.STEEL, src.global_position)
	assert_eq(_seeker.state, EnemyBase.State.IDLE)
	src.queue_free()


## The counter is copper, not distance: `Allomancer` never emits a pulse at
## all while its source is burning copper, so a Seeker beside a coppercloud
## allomancer hears nothing.
func test_copper_suppresses_the_pulse_at_the_source() -> void:
	var body := Node3D.new()
	add_child(body)
	body.global_position = Vector3(2, 0, 0)
	var allomancer := Allomancer.new()
	body.add_child(allomancer)
	allomancer.body = body
	allomancer.set_burning(Metal.Type.STEEL, true)
	allomancer.set_burning(Metal.Type.COPPER, true)
	var got_pulse := [false]
	Events.allomantic_pulse.connect(func(_s, _m, _p): got_pulse[0] = true)
	# Drive the same internal tick `_process` would call, without waiting a
	# real `pulse_interval` worth of frames.
	allomancer._pulse_timer = 999.0
	allomancer._tick_pulses(0.0)
	assert_false(got_pulse[0], "copper should suppress the pulse at the source")
	assert_eq(_seeker.state, EnemyBase.State.IDLE)
	body.queue_free()
