extends TestCase
## `DialogueSystem` (play/advance/choose/finish) and `GameState`'s story flags.


func test_play_missing_dialogue_returns_false() -> void:
	assert_false(DialogueSystem.play(&"does_not_exist_at_all"))


func test_play_shows_first_line() -> void:
	var shown: Array = [null]
	Events.dialogue_line_shown.connect(func(_id, speaker, text, _color): shown[0] = [speaker, text])
	assert_true(DialogueSystem.play(&"meet_kelsier"))
	assert_true(shown[0] != null, "first line should have been shown")
	assert_eq(shown[0][0], "Kelsier")


func test_advance_through_all_lines_finishes() -> void:
	var finished: Array = [false]
	Events.dialogue_finished.connect(func(id): if id == &"meet_dockson": finished[0] = true)
	DialogueSystem.play(&"meet_dockson")  # 3 lines, no choices; play() itself shows line 0.
	DialogueSystem.advance()  # line 1
	DialogueSystem.advance()  # line 2 (the last one)
	DialogueSystem.advance()  # past the end -> finishes
	assert_true(finished[0], "dialogue should finish after its last line")
	assert_false(DialogueSystem.is_active())


func test_choice_sets_flag_and_branches() -> void:
	GameState.dialogue_flags.clear()
	DialogueSystem.play(&"ball_noble_1")  # line 0 shown
	DialogueSystem.advance()  # line 1: Valette's line with 2 choices
	var line := DialogueSystem.current_line()
	assert_true(line.has("choices"), "expected a choice line")
	assert_false(GameState.has_dialogue_flag(&"talked_noble_1"))
	DialogueSystem.choose(0)
	assert_true(GameState.has_dialogue_flag(&"talked_noble_1"), "choosing should set its flag")


func test_game_state_dialogue_flag_helpers() -> void:
	GameState.dialogue_flags.clear()
	assert_false(GameState.has_dialogue_flag(&"met_marsh"))
	assert_eq(GameState.get_dialogue_flag(&"met_marsh", false), false)
	GameState.set_dialogue_flag(&"met_marsh")
	assert_true(GameState.has_dialogue_flag(&"met_marsh"))
	assert_eq(GameState.get_dialogue_flag(&"met_marsh"), true)


func test_set_dialogue_flag_emits_event() -> void:
	var got: Array = [false]
	Events.dialogue_flag_set.connect(func(flag, _value): if flag == &"test_flag_event": got[0] = true)
	GameState.set_dialogue_flag(&"test_flag_event")
	assert_true(got[0])


func test_dialogue_flags_round_trip_through_save() -> void:
	GameState.reset_run()
	GameState.set_dialogue_flag(&"talked_noble_2")
	GameState.save_game(GameState.QUICK_SLOT)
	GameState.reset_run()
	assert_false(GameState.has_dialogue_flag(&"talked_noble_2"))
	GameState.load_game(GameState.QUICK_SLOT)
	assert_true(GameState.has_dialogue_flag(&"talked_noble_2"))
