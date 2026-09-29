extends SceneTree
## Authoring tool: fills every major district up to TARGET activities per type
## with instances that pass `ActivityValidator` (ring/path clearance against the
## generated geometry). Deterministic for a given plan and SEED.
##   godot --headless -s res://tools/gen_activities.gd
## Writes res://src/mission/activities/data/<id>.json for each new activity and
## the matching plan markers to tools/_generated_markers.txt (paste them into
## luthadel_plan.json's `markers`).

const TARGET := 3
const SEED := 20260929
const MIN_SPACING := 110.0
const DISTRICTS: Array[StringName] = [&"skaa_slums", &"merchant", &"noble", &"docks"]
const TYPES: Array[StringName] = [&"coin_race", &"rooftop_pursuit", &"obligator_ambush", &"crowd_riot"]
const SHORT := {&"skaa_slums": "skaa", &"merchant": "merchant", &"noble": "noble", &"docks": "docks"}
const KIND := {&"coin_race": "coin_race", &"rooftop_pursuit": "pursuit", &"obligator_ambush": "ambush", &"crowd_riot": "riot"}
const NAMES := {
	&"coin_race": {
		&"skaa_slums": ["Ash Alley Dash", "Laundry Line Run", "Soot Roof Sprint"],
		&"merchant": ["Guildhall Gallop", "Counting-House Dash", "Silk Row Sprint"],
		&"noble": ["Keep Ring Circuit", "Gilded Terrace Run", "Bannerline Dash"],
		&"docks": ["Jetty Run", "Cargo Crane Circuit", "Barge Row Sprint"],
	},
	&"rooftop_pursuit": {
		&"skaa_slums": ["Rooftop Pursuit: Pickpocket", "Rooftop Pursuit: Runner", "Rooftop Pursuit: Informant"],
		&"merchant": ["Rooftop Pursuit: Fence", "Rooftop Pursuit: Tally Runner", "Rooftop Pursuit: Silk Thief"],
		&"noble": ["Rooftop Pursuit: Jewel Thief", "Rooftop Pursuit: Spy", "Rooftop Pursuit: Courier"],
		&"docks": ["Rooftop Pursuit: Smuggler", "Rooftop Pursuit: Cargo Runner", "Rooftop Pursuit: Dock Cutpurse"],
	},
	&"obligator_ambush": {
		&"skaa_slums": ["Obligator Ambush: Ash Lane", "Obligator Ambush: Soup Line", "Obligator Ambush: Tenement Row"],
		&"merchant": ["Obligator Ambush: Guild Court", "Obligator Ambush: Silk Row", "Obligator Ambush: Ledger Street"],
		&"noble": ["Obligator Ambush: Garden Gate", "Obligator Ambush: Carriage Road", "Obligator Ambush: Banner Court"],
		&"docks": ["Obligator Ambush: Cargo Quay", "Obligator Ambush: Net Loft", "Obligator Ambush: Toll Bridge"],
	},
	&"crowd_riot": {
		&"skaa_slums": ["Soup Line Unrest", "Ration Day Unrest", "Ashfall Unrest"],
		&"merchant": ["Guild Levy Unrest", "Counting-House Unrest", "Market Toll Unrest"],
		&"noble": ["Servants' Quarter Unrest", "Kitchen Gate Unrest", "Stable Yard Unrest"],
		&"docks": ["Stevedores' Unrest", "Shipwrights' Unrest", "Ferrymen's Unrest"],
	},
}

var plan: CityPlan
var v: ActivityValidator
var rng := RandomNumberGenerator.new()
var made: Array[Dictionary] = []   # {data: Dictionary, marker: Dictionary}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	plan = CityPlan.load_from_file()
	v = ActivityValidator.new(plan, 1337)
	rng.seed = SEED
	_repair_legacy()
	var have := _existing_counts()
	for d in DISTRICTS:
		for t in TYPES:
			var n := int(have.get([d, t], 0))
			for k in maxi(0, TARGET - n):
				if not _make(d, t, n + k + 1):
					push_error("could not place %s/%s #%d" % [d, t, n + k + 1])
	# Final pass: all markers are now in the plan, so lots are forced exactly as
	# in the real game. Anything that no longer validates is dropped.
	v.clear()
	var lines: Array[String] = []
	for m in made:
		var a := ActivityData.from_dict(m["data"])
		var errs := v.validate(a, v.resolve_start(a.id))
		if not errs.is_empty():
			push_error("%s failed final validation: %s" % [a.id, ", ".join(errs)])
			continue
		var f := FileAccess.open("res://src/mission/activities/data/%s.json" % a.id, FileAccess.WRITE)
		f.store_string(JSON.stringify(m["data"], "\t") + "\n")
		f.close()
		lines.append(JSON.stringify(m["marker"]))
	var out := FileAccess.open("res://tools/_generated_markers.txt", FileAccess.WRITE)
	out.store_string(",\n".join(lines) + "\n")
	out.close()
	print("generated %d activities" % lines.size())
	quit()


## Counts only activities that currently validate (a clipping ring path or a
## start marker that never resolves doesn't count towards TARGET).
func _existing_counts() -> Dictionary:
	var counts := {}
	for a in ActivityData.load_all():
		var start := v.resolve_start(a.id)
		if start == Vector3.INF or not v.validate(a, start).is_empty():
			continue
		var key := [plan.district_at(Vector2(start.x, start.z)), a.type]
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


## Re-authors hand-written (unflagged) activities that clip buildings or whose
## start marker never resolves: keeps id, title, rewards, medals, time limits
## and ring/waypoint counts, but replaces the geometry-dependent parts (ring
## and path offsets, spawn radius). If no clear layout exists at the current
## marker, the marker moves to another spot in the same district (applied to
## luthadel_plan.json directly).
func _repair_legacy() -> void:
	var moved: Array[Dictionary] = []
	for a in ActivityData.load_all():
		var path := "res://src/mission/activities/data/%s.json" % a.id
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		# `-- all` re-checks (and, where needed, re-authors) already-validated
		# activities too, e.g. after the city geometry changed.
		if bool(data.get("validated", false)) and not OS.get_cmdline_user_args().has("all"):
			continue
		var marker: Dictionary = {}
		for m: Dictionary in plan.markers:
			if str(m.get("activity_id", "")) == String(a.id):
				marker = m
		if marker.is_empty():
			continue
		var pa: Array = marker["pos"]
		var d := plan.district_at(Vector2(float(pa[0]), float(pa[1])))
		var fixed := false
		for reloc in 14:
			var start := v.resolve_start(a.id)
			if start != Vector3.INF and _fix(a, data, start):
				fixed = true
				break
			var p := _candidate(d)
			if p == Vector2.INF:
				break
			marker["pos"] = [p.x, p.y]
			v.invalidate_chunk(plan.chunk_of(p))
			moved.append({"id": String(a.id), "x": p.x, "y": p.y})
		if not fixed:
			push_error("repair: could not fix %s" % a.id)
			continue
		data["validated"] = true
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data, "\t") + "\n")
		f.close()
		print("repaired %s" % a.id)
	# Persist the final position of every relocated marker into the plan file.
	var last := {}
	for mv in moved:
		last[mv["id"]] = mv
	if last.is_empty():
		return
	var text := FileAccess.get_file_as_string("res://src/world/data/luthadel_plan.json")
	for id: String in last:
		var re := RegEx.create_from_string("(\"activity_id\": \"%s\"[^\n]*?\"pos\": )\\[[^\\]]*\\]" % id)
		text = re.sub(text, "$1[%d, %d]" % [int(last[id]["x"]), int(last[id]["y"])])
		print("moved %s -> %d, %d" % [id, int(last[id]["x"]), int(last[id]["y"])])
	var pf := FileAccess.open("res://src/world/data/luthadel_plan.json", FileAccess.WRITE)
	pf.store_string(text)
	pf.close()


## Makes `data` (an activity JSON dictionary) valid at `start`, in place.
func _fix(a: ActivityData, data: Dictionary, start: Vector3) -> bool:
	if v.validate(ActivityData.from_dict(data), start).is_empty():
		return true
	var params: Dictionary = data["params"]
	match String(a.type):
		"coin_race":
			var offs := v.find_ring_offsets(start, (params["ring_offsets"] as Array).size(), rng.randi())
			if offs.is_empty():
				return false
			params["ring_offsets"] = offs
		"rooftop_pursuit":
			var offs := v.find_path_offsets(start, (params["path_offsets"] as Array).size(), rng.randi())
			if offs.is_empty():
				return false
			params["path_offsets"] = offs
		_:
			if not _fit_radius(data, start, [float(params.get("spawn_radius", 8.0)), 6.0, 5.0, 4.0, 3.0, 2.5]):
				return false
	return v.validate(ActivityData.from_dict(data), start).is_empty()


func _candidate(d: StringName) -> Vector2:
	for i in 400:
		var p := Vector2(rng.randf_range(plan.bounds.position.x, plan.bounds.end.x),
				rng.randf_range(plan.bounds.position.y, plan.bounds.end.y))
		if plan.district_at(p) != d or plan.distance_to_wall(p) < 90.0:
			continue
		if d == &"skaa_slums" and plan.slice_bounds.grow(60.0).has_point(p):
			continue
		if not plan.canals_overlapping(Rect2(p, Vector2.ZERO).grow(40.0)).is_empty():
			continue
		if plan.landmark_overlapping(Rect2(p, Vector2.ZERO).grow(45.0)) != null:
			continue
		var close := false
		for m: Dictionary in plan.markers:
			var pa: Array = m["pos"]
			if Vector2(float(pa[0]), float(pa[1])).distance_to(p) < MIN_SPACING:
				close = true
				break
		if close:
			continue
		return Vector2(snappedf(p.x, 1.0), snappedf(p.y, 1.0))
	return Vector2.INF


func _make(d: StringName, t: StringName, n: int) -> bool:
	var taken := {}
	for m: Dictionary in plan.markers:
		taken[str(m.get("activity_id", ""))] = true
	while taken.has("%s_%s_%d" % [KIND[t], SHORT[d], n]):
		n += 1
	var id := "%s_%s_%d" % [KIND[t], SHORT[d], n]
	var names: Array = NAMES[t][d]
	var title: String = names[(n - 1) % names.size()]
	for attempt in 40:
		var p := _candidate(d)
		if p == Vector2.INF:
			return false
		var rooftop := t == &"coin_race" or t == &"rooftop_pursuit"
		var marker := {"group": "activity_start", "activity_id": id,
				"placement": "rooftop" if rooftop else "street", "pos": [p.x, p.y]}
		if rooftop:
			marker["floors"] = 4
			marker["flat"] = true
		plan.markers.append(marker)
		v.invalidate_chunk(plan.chunk_of(p))
		var start := v.resolve_start(StringName(id))
		var data := _build_data(id, t, title, d, start)
		if not data.is_empty():
			var errs := v.validate(ActivityData.from_dict(data), start)
			if errs.is_empty():
				made.append({"data": data, "marker": marker})
				return true
		plan.markers.pop_back()
		v.invalidate_chunk(plan.chunk_of(p))
	return false


func _build_data(id: String, t: StringName, title: String, d: StringName, start: Vector3) -> Dictionary:
	if start == Vector3.INF:
		return {}
	var base := {"id": id, "type": String(t), "title": title, "start_marker": id, "validated": true}
	var scale := 1.0 + 0.15 * float(SHORT.keys().find(d))
	match t:
		&"coin_race":
			var offs := v.find_ring_offsets(start, 5, rng.randi())
			if offs.is_empty():
				return {}
			var length := _length(Vector3.ZERO, offs)
			base["params"] = {"ring_offsets": offs, "time_limit": _r(length / 2.8),
					"medals": {"gold": _r(length / 5.2), "silver": _r(length / 3.85), "bronze": _r(length / 3.05)}}
			base["rewards"] = {"coins": int(40 * scale), "mastery_points": 1}
		&"rooftop_pursuit":
			var offs := v.find_path_offsets(start, 6, rng.randi())
			if offs.is_empty():
				return {}
			var speed := 5.5
			var tt := _length(Vector3.ZERO, offs) / speed
			base["params"] = {"path_offsets": offs, "thief_speed": speed, "catch_distance": 3.0,
					"time_limit": _r(tt * 3.1),
					"medals": {"gold": _r(tt * 1.25), "silver": _r(tt * 1.95), "bronze": _r(tt * 2.7)}}
			base["rewards"] = {"coins": int(60 * scale), "vials": 1, "mastery_points": 1}
		&"obligator_ambush":
			var pool := ["guard", "guard", "hazekiller", "coinshot", "thug"]
			var types: Array = []
			for i in 3:
				types.append(pool[rng.randi() % pool.size()])
			base["params"] = {"enemy_types": types, "spawn_radius": 9.0}
			base["rewards"] = {"coins": int(80 * scale), "vials": 1, "mastery_points": 2}
			if not _fit_radius(base, start, [9.0, 7.0, 5.5, 4.0]):
				return {}
		&"crowd_riot":
			base["params"] = {"start_mood": 78.0, "calm_threshold": 25.0, "member_count": 5,
					"spawn_radius": 6.0, "time_limit": 33.0}
			base["rewards"] = {"coins": int(45 * scale), "vials": 1, "mastery_points": 1}
			if not _fit_radius(base, start, [6.0, 5.0, 4.0, 3.0]):
				return {}
	return base


## Streets are narrow: picks the largest spawn radius whose ring of spawn points
## is clear of buildings (ambush/riot spawn around the start marker).
func _fit_radius(base: Dictionary, start: Vector3, radii: Array) -> bool:
	for r: float in radii:
		base["params"]["spawn_radius"] = r
		if v.validate(ActivityData.from_dict(base), start).is_empty():
			return true
	return false


static func _r(x: float) -> float:
	return snappedf(x, 0.5)


static func _length(start: Vector3, offs: Array) -> float:
	var total := 0.0
	var prev := start
	for o: Array in offs:
		var p := Vector3(float(o[0]), float(o[1]), float(o[2]))
		total += prev.distance_to(p)
		prev = p
	return total
