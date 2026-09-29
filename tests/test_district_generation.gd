extends TestCase
## Every district type must generate deterministically and with a dense
## enough metal-anchor network for chained Push/Pull rooftop travel (the
## "slice district" standard from docs/OPEN_WORLD.md), not just the
## vertical-slice skaa quarter near the origin.

## Anchors per 100 sq m of chunk area, floor for each district type. Measured
## with `tools/_probe_density.gd`-style sampling (see docs/PERFORMANCE.md);
## thresholds sit comfortably below the measured values so minor prop-density
## tuning doesn't make this test flaky. `kredik_shaw` is the Lord Ruler's bare
## approach grounds (no buildings by design), so its floor is just "lamps
## exist", not building-density anchors.
const MIN_ANCHOR_DENSITY := {
	&"skaa_slums": 0.30, &"merchant": 0.45, &"noble": 0.55, &"market": 0.55,
	&"docks": 0.45, &"kredik_shaw": 0.03,
}

static var _plan: CityPlan


func _get_plan() -> CityPlan:
	if _plan == null:
		_plan = CityPlan.load_from_file()
	return _plan


## First chunk coordinate whose district is `type` and (for districts with
## buildings) actually has lots — landmark-clipped/edge chunks are skipped.
func _sample_chunk(plan: CityPlan, type: StringName, seed_value: int) -> Vector2i:
	var style_empty := bool(plan.style(type).get("empty", false))
	var cr := plan.chunk_range()
	for x in range(cr.position.x, cr.end.x):
		for z in range(cr.position.y, cr.end.y):
			var c := Vector2i(x, z)
			if plan.district_at(plan.chunk_rect(c).get_center()) != type:
				continue
			var L := ChunkLayout.generate(plan, seed_value, c)
			if L.district != type:
				continue
			if style_empty or not L.lots.is_empty():
				return c
	return Vector2i(999999, 999999)


func test_every_district_type_is_deterministic() -> void:
	var plan := _get_plan()
	for type: StringName in MIN_ANCHOR_DENSITY:
		var c := _sample_chunk(plan, type, 1337)
		assert_true(c.x != 999999, "%s: found a representative chunk" % type)
		if c.x == 999999:
			continue
		var a := ChunkGenerator.generate_chunk(plan, 4242, c)
		var b := ChunkGenerator.generate_chunk(plan, 4242, c)
		assert_eq(a.metal_count, b.metal_count, "%s: deterministic metal count" % type)
		assert_eq(a.shapes.size(), b.shapes.size(), "%s: deterministic geometry" % type)
		assert_eq(a.nav_faces.size(), b.nav_faces.size(), "%s: deterministic nav source" % type)
		var la := ChunkLayout.generate(plan, 4242, c)
		var lb := ChunkLayout.generate(plan, 4242, c)
		assert_eq(la.signature(), lb.signature(), "%s: deterministic layout" % type)


func test_anchor_density_meets_slice_standard_per_district() -> void:
	var plan := _get_plan()
	var area := plan.chunk_size * plan.chunk_size
	for type: StringName in MIN_ANCHOR_DENSITY:
		var c := _sample_chunk(plan, type, 1337)
		if c.x == 999999:
			continue
		var data := ChunkGenerator.generate_chunk(plan, 1337, c)
		var density := float(data.metal_count) / area * 100.0
		print("    %s: %d anchors in chunk %s (%.2f / 100 sq m)" % [type, data.metal_count, c, density])
		assert_gt(density, float(MIN_ANCHOR_DENSITY[type]), "%s anchor density" % type)


## Rooftop lot heights within a block stay a plausible Push/Pull chain apart
## (the street/backgap widths that separate them, per docs/OPEN_WORLD.md, are
## meant to read as 4-15 m gaps, not a canyon or a hop-across seam).
func test_street_and_backgap_widths_stay_in_traversal_range() -> void:
	var plan := _get_plan()
	for type: StringName in MIN_ANCHOR_DENSITY:
		if bool(plan.style(type).get("empty", false)):
			continue
		var style: Dictionary = plan.style(type)
		var street: Array = style.get("street", [4.0, 7.0])
		var arterial: Array = style.get("arterial", [7.0, 9.0])
		var backgap: Array = style.get("backgap", [0.0, 4.0])
		assert_true(float(street[1]) <= 15.0, "%s street width stays chainable" % type)
		assert_true(float(arterial[1]) <= 15.0, "%s arterial width stays chainable" % type)
		assert_true(float(backgap[1]) <= 15.0, "%s backgap stays chainable" % type)
		assert_true(float(street[0]) >= 2.0, "%s street width leaves a real gap" % type)


## Merchant/noble get facade ornaments (pilasters, iron-railed balconies that
## are also anchors), avenues lined with ash-dead trees/planters, and walled
## keep gardens; the skaa baseline gets none of it.
func test_merchant_and_noble_have_distinct_ornament() -> void:
	var plan := _get_plan()
	for type: StringName in [&"merchant", &"noble"]:
		var c := _sample_chunk(plan, type, 1337)
		var data := ChunkGenerator.generate_chunk(plan, 1337, c)
		assert_true(data.instances.has(&"balcony"), "%s: iron balconies" % type)
	var skaa := ChunkGenerator.generate_chunk(plan, 1337, _sample_chunk(plan, &"skaa_slums", 1337))
	assert_false(skaa.instances.has(&"balcony"), "skaa keeps its plain facades")
	assert_false(skaa.instances.has(&"street_tree"), "skaa has no avenue planting")


func test_avenues_are_wider_outside_the_slice_only() -> void:
	var plan := _get_plan()
	var st := plan.style(&"merchant")
	var avenue: Array = st["avenue"]
	var normal_max := float((st["arterial"] as Array)[1])
	var wide := 0
	# Merchant ground far from the slice: every third vertical line is an avenue.
	for line in range(-16, -9):
		var w := ChunkLayout.boundary_width(plan, 1337, true, line, -9)
		if posmod(line, int(st["avenue_every"])) == 0:
			assert_true(w >= float(avenue[0]) - 0.001 and w <= float(avenue[1]) + 0.001, "avenue width %.1f on line %d" % [w, line])
			wide += 1
		else:
			assert_true(w <= normal_max + 0.001, "ordinary arterial on line %d" % line)
	assert_gt(float(wide), 0.0, "some avenues exist")
	# Inside the slice bounds the layout is untouched.
	for line in [-1, 0, 1]:
		var ws := ChunkLayout.boundary_width(plan, 1337, true, line, 0)
		assert_true(ws <= float(plan.style(plan.district_at(Vector2(line * 128.0, 64.0)))["arterial"][1]) + 0.001, "slice line %d not widened" % line)
	assert_true(float(avenue[1]) <= 15.0, "avenues stay within the 4-15 m traversal gap")
	var t := ChunkGenerator.generate_chunk(plan, 1337, Vector2i(-9, -9))
	print("    avenue chunk trees %d planters %d" % [t.instances.get(&"street_tree", []).size(), t.instances.get(&"ash_planter", []).size()])


func test_noble_keeps_have_walled_gardens() -> void:
	var plan := _get_plan()
	var lm := plan.landmark_by_id(&"keep_hasting")
	var a := ChunkGenerator.generate_landmark(plan, 1337, lm)
	var b := ChunkGenerator.generate_landmark(plan, 1337, lm)
	var hedges: Array = a.instances.get(&"hedge", [])
	assert_gt(float(hedges.size()), 40.0, "hedges line the courtyard walls")
	assert_true(a.instances.has(&"ash_planter"), "ash-dead planters")
	assert_eq(hedges.size(), (b.instances.get(&"hedge", []) as Array).size(), "deterministic garden")
