class_name CollectibleLore
extends RefCounted
## Flavor text for collectibles (atium beads, crew notes), loaded from
## `res://src/mission/activities/data/collectibles.json`. Crew notes are short,
## original lore snippets — never copied from the books. Also the source of
## truth for how many collectibles exist in total (for the journal's
## "found / total" count).

const PATH := "res://src/mission/activities/data/collectibles.json"

static var _cache: Dictionary


static func _entries() -> Dictionary:
	if _cache == null or _cache.is_empty():
		_cache = {}
		var text := FileAccess.get_file_as_string(PATH)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_ARRAY:
			for e: Dictionary in parsed:
				_cache[str(e.get("id", ""))] = e
	return _cache


static func all_ids() -> Array:
	return _entries().keys()


static func text_for(id: StringName) -> String:
	var e: Dictionary = _entries().get(String(id), {})
	return str(e.get("text", ""))


static func kind_for(id: StringName) -> StringName:
	var e: Dictionary = _entries().get(String(id), {})
	return StringName(e.get("kind", ""))


static func total_count() -> int:
	return _entries().size()
