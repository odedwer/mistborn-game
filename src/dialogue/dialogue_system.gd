extends Node
## Lightweight, data-driven dialogue system (autoload `DialogueSystem`).
##
## Dialogue is JSON under `res://src/mission/dialogues/<id>.json`: an array of
## lines, each `{"speaker": "...", "text": "...", "color": "#rrggbb",
## "choices": [{"text": "...", "set_flag": "...", "value": true, "goto": 2}]}`.
## `color` and `choices` are optional. `goto` is a 0-based index into `lines`;
## omitting it just advances to the next line.
##
## `play(id)` starts a dialogue and shows `dialogue_box.tscn` (if present).
## `advance()`/`choose(index)` step through it — called by the box UI on
## input, or directly by tests/mission scripts without any UI at all. Every
## step is mirrored on `Events.dialogue_*` so the box, the mission director
## and tests can all react without holding a reference to this autoload.

const DIALOGUE_DIR := "res://src/mission/dialogues"
const BOX_SCENE := "res://src/ui/dialogue_box.tscn"

var current_id: StringName = &""
var _lines: Array = []
var _index: int = -1
var _box: CanvasLayer


func is_active() -> bool:
	return current_id != &""


## Loads and starts dialogue `id`. Returns false (and does nothing) if the
## file is missing, so a bad mission JSON id fails loudly via a warning
## instead of soft-locking a stage.
func play(id: StringName) -> bool:
	var data := load_dialogue(id)
	if data.is_empty():
		push_warning("DialogueSystem: no dialogue found for '%s'" % id)
		return false
	_lines = data
	_index = -1
	current_id = id
	Events.dialogue_started.emit(id)
	_ensure_box()
	advance()
	return true


## Loads dialogue `id`'s lines without playing it (used by tests and by the
## mission JSON validator).
static func load_dialogue(id: StringName) -> Array:
	var path := "%s/%s.json" % [DIALOGUE_DIR, String(id)]
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return parsed.get("lines", [])


func current_line() -> Dictionary:
	if _index < 0 or _index >= _lines.size():
		return {}
	return _lines[_index]


## Advances to the next line, or finishes the dialogue past the last one.
func advance() -> void:
	if not is_active():
		return
	_index += 1
	if _index >= _lines.size():
		_finish()
		return
	var line: Dictionary = _lines[_index]
	var color := Color(0.85, 0.85, 0.9)
	if line.has("color"):
		color = Color(String(line["color"]))
	Events.dialogue_line_shown.emit(current_id, line.get("speaker", ""), line.get("text", ""), color)
	var choices: Array = line.get("choices", [])
	if not choices.is_empty():
		Events.dialogue_choices_shown.emit(current_id, choices)


## Picks choice `choice_index` of the current line: sets its flag (if any),
## jumps to its `goto` line (if any), then advances/shows that line.
func choose(choice_index: int) -> void:
	var line := current_line()
	var choices: Array = line.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	var c: Dictionary = choices[choice_index]
	if c.has("set_flag"):
		GameState.set_dialogue_flag(StringName(c["set_flag"]), c.get("value", true))
	if c.has("goto"):
		_index = int(c["goto"]) - 1  # advance() below increments past this.
	advance()


func _finish() -> void:
	var id := current_id
	current_id = &""
	_lines.clear()
	_index = -1
	if _box != null and is_instance_valid(_box):
		_box.visible = false
	Events.dialogue_finished.emit(id)


func _ensure_box() -> void:
	if _box != null and is_instance_valid(_box):
		_box.visible = true
		return
	if not ResourceLoader.exists(BOX_SCENE):
		return
	_box = (load(BOX_SCENE) as PackedScene).instantiate()
	if is_inside_tree():
		get_tree().root.add_child.call_deferred(_box)
