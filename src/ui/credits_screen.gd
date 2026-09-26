class_name CreditsScreen
extends CanvasLayer
## Scrolling end credits. Rolled by `MissionDirector`'s `roll_credits` action
## at the end of "The Lord Ruler" (then the game drops into post-game free
## roam) and also opened from the main menu's Credits button.
##
## Pauses the tree while it runs (it processes with `PROCESS_MODE_ALWAYS`).
## Any of `ui_accept`/`ui_cancel`/`pause`/`interact` skips to the end once the
## first second has passed, so a stray key held from gameplay doesn't skip
## the whole thing. `finish()` ends it programmatically (tests).

signal finished

const SCROLL_SPEED := 42.0  # pixels per second
const HOLD_AT_END := 3.0

## Each entry: [kind, text], kind is "title", "heading", "line" or "gap".
const SECTIONS := [
	["title", "Mistborn: Ashes of Luthadel"],
	["line", "An unofficial fan game"],
	["gap", ""],
	["heading", "A Fan Project"],
	["line", "This is a free, non-commercial fan game made by fans, for fans."],
	["line", "Mistborn, its world, characters and all related names are the property of"],
	["line", "Brandon Sanderson and Dragonsteel Entertainment."],
	["line", "This project is not affiliated with, sponsored or endorsed by them."],
	["line", "All dialogue and in-game text is original writing for this project;"],
	["line", "no passages from the novels are reproduced."],
	["line", "If you enjoyed this, read the books."],
	["gap", ""],
	["heading", "Story Beats Adapted From"],
	["line", "Mistborn: The Final Empire, by Brandon Sanderson"],
	["gap", ""],
	["heading", "Design, Code and Content"],
	["line", "The Ashes of Luthadel fan team"],
	["line", "Written and built with the help of Claude (Anthropic)"],
	["gap", ""],
	["heading", "Built With"],
	["line", "Godot Engine 4 (MIT License)"],
	["line", "Jolt Physics (MIT License)"],
	["line", "Blender (character models)"],
	["line", "Python (procedural texture and audio generators)"],
	["gap", ""],
	["heading", "Assets"],
	["line", "Textures, audio, shaders and models: original, procedurally generated,"],
	["line", "released under CC0 1.0 (public domain)."],
	["line", "Optional reference textures and HDRIs: Poly Haven, CC0."],
	["line", "Fonts: Cinzel and EB Garamond, SIL Open Font License 1.1."],
	["gap", ""],
	["heading", "Thank You"],
	["line", "To everyone who ever looked up at the mists and wondered."],
	["gap", ""],
	["gap", ""],
	["line", "The mists are yours now. Luthadel remains open to explore."],
]

var _scroll: VBoxContainer
var _elapsed := 0.0
var _done := false
var _running := false
var _was_paused := false
var _end_y := 0.0


func _init() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "CreditsScreen"


func _ready() -> void:
	add_to_group(&"credits_screen")
	_build()


## Every line of text the credits show, in order (tests / localisation).
static func all_text() -> PackedStringArray:
	var out := PackedStringArray()
	for s: Array in SECTIONS:
		if String(s[1]) != "":
			out.append(String(s[1]))
	return out


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIHelpers.theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.015, 0.02, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_scroll = VBoxContainer.new()
	_scroll.name = "Scroll"
	_scroll.add_theme_constant_override("separation", 8)
	_scroll.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(_scroll)
	for s: Array in SECTIONS:
		var kind: String = s[0]
		var text: String = s[1]
		var c: Control
		match kind:
			"title":
				c = UIHelpers.title_label(text)
			"heading":
				c = UIHelpers.heading_label(text)
			"gap":
				c = UIHelpers.vsep(28)
			_:
				c = UIHelpers.dim_label(text)
		if c is Label:
			(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			(c as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
		_scroll.add_child(c)
	var hint := Label.new()
	hint.text = "Press Esc / Enter to skip"
	hint.modulate = Color(1, 1, 1, 0.35)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-240, -36)
	root.add_child(hint)


## Starts rolling. Emits `finished` at the end (or on skip).
func play() -> void:
	_running = true
	_done = false
	_elapsed = 0.0
	if is_inside_tree():
		_was_paused = get_tree().paused
		get_tree().paused = true
		var vp := get_viewport().get_visible_rect().size
		_scroll.position = Vector2(0, vp.y)


func _process(delta: float) -> void:
	if not _running or _done:
		return
	_elapsed += delta
	_scroll.position.y -= SCROLL_SPEED * delta
	var h := _scroll.get_combined_minimum_size().y
	if _scroll.position.y + h < get_viewport().get_visible_rect().size.y * 0.45:
		_end_y += delta
		_scroll.position.y += SCROLL_SPEED * delta  # hold the last lines
		if _end_y >= HOLD_AT_END:
			finish()


func _unhandled_input(event: InputEvent) -> void:
	if not _running or _done or _elapsed < 1.0:
		return
	for a: StringName in [&"ui_accept", &"ui_cancel", &"pause", &"interact"]:
		if InputMap.has_action(a) and event.is_action_pressed(a):
			get_viewport().set_input_as_handled()
			finish()
			return


## Ends the credits now: unpauses (unless the tree was already paused when
## they started, e.g. from a menu), emits `finished` and frees the screen.
func finish() -> void:
	if _done:
		return
	_done = true
	_running = false
	if is_inside_tree():
		get_tree().paused = _was_paused
	finished.emit()
	queue_free()
