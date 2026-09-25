class_name ChunkGenerator
extends RefCounted
## Entry points for building streaming units off the main thread.
## Both functions are pure: same (plan, seed, id) -> same ChunkBuildData.

## Extra navigation border around each chunk so neighbouring navmeshes share edges.
const NAV_BORDER := 2.0


static func chunk_key(c: Vector2i) -> String:
	return "c:%d,%d" % [c.x, c.y]


static func landmark_key(id: StringName) -> String:
	return "lm:%s" % id


## Full build of grid chunk `c` (ground, canals, buildings, props, wall, markers, nav source).
static func generate_chunk(plan: CityPlan, seed_value: int, c: Vector2i) -> ChunkBuildData:
	var L := ChunkLayout.generate(plan, seed_value, c)
	var data := ChunkBuildData.new()
	data.key = chunk_key(c)
	data.coord = c
	GroundBuilder.build(data, plan, L, seed_value, NAV_BORDER)
	for lot in L.lots:
		BuildingBuilder.build_lot(data, lot)
	PropPlacer.place(data, plan, L, seed_value)
	CityWallBuilder.build(data, plan, L.rect)
	data.markers.append_array(L.markers)
	# Landmarks sitting on this chunk contribute to its navigation source.
	var nav_area := L.rect.grow(NAV_BORDER)
	for lm in plan.landmarks:
		if lm.footprint.intersects(nav_area):
			var ld := LandmarkBuilder.build(plan, seed_value, lm)
			data.nav_faces.append_array(ld.nav_faces)
			data.nav_obstructions.append_array(ld.nav_obstructions)
	data.nav_rect = L.rect
	return data


## Full build of landmark `lm`.
static func generate_landmark(plan: CityPlan, seed_value: int, lm: CityPlan.Landmark) -> ChunkBuildData:
	return LandmarkBuilder.build(plan, seed_value, lm)
