class_name LineTargeting
extends RefCounted
## Chooses which steel line a Push/Pull acts on.
##
## Manual mode: the metal nearest the crosshair ray by angle (plus a small
## distance penalty) inside a cone. The target stays locked while the button
## is held, and the scroll wheel cycles through the candidates in the cone.
##
## Traversal assist: while airborne, holding Push can pick the anchor that
## best drives the allomancer in the desired travel direction (behind/below
## relative to where they want to go), like web-swing auto targeting.

## Crosshair cone half-angle (degrees).
var max_angle_deg := 14.0
## Score penalty (radians per metre) favouring nearer metals at equal angle.
var distance_weight := 0.004
## Manual aim this precise (degrees) always wins over traversal assist.
var precise_aim_deg := 4.0
## Minimum alignment (dot) between the push direction and the desired
## direction for an assist anchor.
var assist_min_alignment := 0.25
## A new assist anchor must score this much better to replace the current one.
var assist_hysteresis := 1.3

## Candidates inside the crosshair cone, best first (reused every update).
var candidates: Array[Metallic] = []
## Current target (null if none).
var target: Metallic
## Angle (degrees) between the crosshair ray and the current target.
var target_angle_deg := 180.0
## While locked, `update` keeps the target as long as it's in range.
var locked := false
## True if the current target came from traversal assist.
var from_assist := false

var _scores := PackedFloat32Array()
var _sticky: Metallic


## Scores a metal at `to` (vector from the ray origin) for the crosshair ray
## `dir`. Lower is better; INF when outside the cone.
static func crosshair_score(to: Vector3, dir: Vector3, max_angle_deg: float, distance_weight: float) -> float:
	var d := to.length()
	if d < 0.01:
		return INF
	var c := clampf(dir.dot(to / d), -1.0, 1.0)
	if c < cos(deg_to_rad(max_angle_deg)):
		return INF
	return acos(c) + distance_weight * d


## Rebuilds the candidate list from `lines` for the crosshair ray and
## refreshes `target` (unless locked). Metals less than `min_along` metres
## along the ray (e.g. between a third-person camera and the player) are
## ignored. Returns the target.
func update(lines: Array[Metallic], origin: Vector3, dir: Vector3, min_along: float = 0.0) -> Metallic:
	candidates.clear()
	_scores.clear()
	var cos_max := cos(deg_to_rad(max_angle_deg))
	for m in lines:
		if not is_instance_valid(m):
			continue
		var to := m.global_position - origin
		var along := to.dot(dir)
		if along < min_along:
			continue
		var d := to.length()
		if d < 0.01 or along < d * cos_max:
			continue
		var score := acos(clampf(along / d, -1.0, 1.0)) + distance_weight * d
		var i := candidates.size()
		while i > 0 and _scores[i - 1] > score:
			i -= 1
		candidates.insert(i, m)
		_scores.insert(i, score)
	if locked:
		if target == null or not is_instance_valid(target) or not target.is_inside_tree() \
				or not lines.has(target):
			release()
	if not locked:
		if _sticky != null and is_instance_valid(_sticky) and candidates.has(_sticky):
			target = _sticky
		else:
			_sticky = null
			target = candidates[0] if not candidates.is_empty() else null
		from_assist = false
	target_angle_deg = 180.0
	if target != null and is_instance_valid(target):
		var to_t := target.global_position - origin
		var len_t := to_t.length()
		if len_t > 0.01:
			target_angle_deg = rad_to_deg(acos(clampf(dir.dot(to_t / len_t), -1.0, 1.0)))
	return target


## Locks the current target (call when Push/Pull is pressed).
func lock() -> void:
	locked = target != null


## Locks onto a specific metal (e.g. an assist anchor or a freshly dropped coin).
func lock_on(m: Metallic, assisted: bool = false) -> void:
	target = m
	locked = m != null
	from_assist = assisted and m != null


func release() -> void:
	locked = false
	from_assist = false


## Moves the selection `step` places through the candidates (scroll wheel).
func cycle(step: int) -> Metallic:
	if candidates.is_empty():
		return target
	var idx := candidates.find(target)
	if idx < 0:
		idx = 0 if step > 0 else 1
	idx = posmod(idx + step, candidates.size())
	target = candidates[idx]
	_sticky = target
	return target


## True if the crosshair is precisely on the current target.
func is_precise() -> bool:
	return target != null and target_angle_deg <= precise_aim_deg


## How good an anchor `m` is for a Push that should send a body at `from`
## along `desired` (normalised). 0 = useless. Heavier/anchored metals score
## higher because they give more of the reaction back.
static func traversal_score(m: Metallic, from: Vector3, desired: Vector3, max_range: float, self_mass: float, min_alignment: float) -> float:
	var away := from - m.global_position  # a Push drives us this way
	var d := away.length()
	if d < 0.3 or d >= max_range:
		return 0.0
	var align := desired.dot(away / d)
	if align < min_alignment:
		return 0.0
	var mass := m.get_body_mass()
	var anchor := 1.0
	if not is_inf(mass):
		if m.body is RigidBody3D and ((m.body as RigidBody3D).sleeping or m.body.has_method(&"is_virtual_anchor") and m.body.is_virtual_anchor()):
			anchor = 0.85
		else:
			anchor = mass / (mass + self_mass)
	return align * align * anchor * Allomancer.falloff(d, max_range, 3.0)


## Picks the best traversal anchor among `lines`, keeping the current assist
## target unless another one is clearly better. Returns null if none helps.
func pick_traversal_anchor(lines: Array[Metallic], from: Vector3, desired: Vector3, max_range: float, self_mass: float) -> Metallic:
	var best: Metallic = null
	var best_score := 0.0
	for m in lines:
		if not is_instance_valid(m):
			continue
		var s := traversal_score(m, from, desired, max_range, self_mass, assist_min_alignment)
		if s > best_score:
			best_score = s
			best = m
	if from_assist and target != null and is_instance_valid(target) and target != best:
		var cur := traversal_score(target, from, desired, max_range, self_mass, assist_min_alignment)
		if cur > 0.0 and cur * assist_hysteresis >= best_score:
			return target
	return best
