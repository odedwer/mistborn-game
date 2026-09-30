extends Node
## World clock (autoload `TimeOfDay`): an ash-grey, hazy day and a misty night.
##
## `hour` is the raw clock (0..24). It only advances while `clock_running` is
## true (the open-world game scene turns it on) and nothing forces a phase.
## Everything visual reads `night_factor()` / `effective_hour()` through the
## world's `DayNightDriver`; gameplay reads `phase` (DAY or NIGHT).
##
## Forcing: `force_phase(reason, phase)` pins the *effective* phase without
## touching the raw clock, and pauses the clock, until `release(reason)`.
## Story missions authored at night (`MissionData.time_of_day == "night"`)
## force NIGHT under reason &"mission"; interiors force NIGHT under
## &"interior" so every hand-built mission scene keeps its authored lighting.
##
## Debug: `--time=<hour>` on the command line sets the clock at startup; in
## debug builds F7 toggles day/night and F8 advances one hour.

signal time_changed(hour: float)
signal phase_changed(phase: int)

enum Phase { DAY, NIGHT }

## New games start in the middle of the night (the game used to be night-only).
const DEFAULT_HOUR := 22.0
## Canonical hours used when a phase is forced or waited for.
const NIGHT_HOUR := 22.0
const DAY_HOUR := 11.0
## Dusk ramps day -> night over these hours; dawn ramps back.
const DUSK_START := 18.5
const DUSK_END := 20.0
const DAWN_START := 5.0
const DAWN_END := 6.5

## Real seconds per in-game 24 h.
@export var day_length_seconds := 2400.0

var hour := DEFAULT_HOUR
var clock_running := false
var phase: int = Phase.NIGHT
var _forces: Dictionary = {}   # reason (StringName) -> Phase


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var ev := get_node_or_null(^"/root/Events")
	if ev != null:
		if ev.has_signal(&"interior_entered"):
			ev.connect(&"interior_entered", func(_p: String) -> void: force_phase(&"interior", Phase.NIGHT))
		if ev.has_signal(&"interior_exited"):
			ev.connect(&"interior_exited", func() -> void: release(&"interior"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			set_hour(float(a.substr(7)))
	phase = _phase_for(effective_hour())


func _process(delta: float) -> void:
	if not clock_running or not _forces.is_empty() or day_length_seconds <= 0.0:
		return
	_set_raw(hour + delta * 24.0 / day_length_seconds)


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F7:
			set_hour(DAY_HOUR if is_night() else NIGHT_HOUR)
		KEY_F8:
			set_hour(hour + 1.0)


## Sets the raw clock (wrapped to 0..24).
func set_hour(h: float) -> void:
	_set_raw(h)


func _set_raw(h: float) -> void:
	hour = fposmod(h, 24.0)
	time_changed.emit(hour)
	_update_phase()


## Hour the world is lit for: the canonical hour of a forced phase, else `hour`.
func effective_hour() -> float:
	var f := forced_phase()
	if f == Phase.NIGHT:
		return NIGHT_HOUR
	if f == Phase.DAY:
		return DAY_HOUR
	return hour


## The forced phase, or -1 if nothing forces one. Night wins a conflict.
func forced_phase() -> int:
	if _forces.is_empty():
		return -1
	return Phase.NIGHT if _forces.values().has(Phase.NIGHT) else Phase.DAY


func is_forced() -> bool:
	return not _forces.is_empty()


func force_phase(reason: StringName, p: int) -> void:
	_forces[reason] = p
	time_changed.emit(hour)
	_update_phase()


func release(reason: StringName) -> void:
	if not _forces.has(reason):
		return
	_forces.erase(reason)
	time_changed.emit(hour)
	_update_phase()


## 0 = full day, 1 = full night, smooth through dusk and dawn.
func night_factor() -> float:
	return night_factor_at(effective_hour())


static func night_factor_at(h: float) -> float:
	h = fposmod(h, 24.0)
	if h >= DUSK_END or h <= DAWN_START:
		return 1.0
	if h >= DAWN_END and h <= DUSK_START:
		return 0.0
	if h > DUSK_START:
		return smoothstep(DUSK_START, DUSK_END, h)
	return 1.0 - smoothstep(DAWN_START, DAWN_END, h)


static func _phase_for(h: float) -> int:
	return Phase.NIGHT if night_factor_at(h) >= 0.5 else Phase.DAY


func is_night() -> bool:
	return phase == Phase.NIGHT


## True if content requiring `required` ("", "any", "day" or "night") may run now.
func allows(required: String) -> bool:
	match required:
		"night":
			return phase == Phase.NIGHT
		"day":
			return phase == Phase.DAY
	return true


## Phase name ("day"/"night") -> Phase, or -1.
static func parse_phase(s: String) -> int:
	match s.to_lower():
		"night":
			return Phase.NIGHT
		"day":
			return Phase.DAY
	return -1


## Skips the clock forward to the next time `target` begins (its canonical
## hour). Returns false if a forced phase makes waiting pointless.
func wait_until(target: int) -> bool:
	if is_forced():
		return false
	set_hour(NIGHT_HOUR if target == Phase.NIGHT else DAY_HOUR)
	return true


func reset() -> void:
	_forces.clear()
	clock_running = false
	_set_raw(DEFAULT_HOUR)


## "Day", "Dusk", "Night" or "Dawn" for the effective hour (map tab, HUD).
func phase_name() -> String:
	var h := effective_hour()
	var n := night_factor_at(h)
	if n > 0.0 and n < 1.0:
		return "Dusk" if h > 12.0 else "Dawn"
	return "Night" if n >= 1.0 else "Day"


## "HH:MM" of the raw clock.
func clock_text() -> String:
	var m := int(hour * 60.0) % (24 * 60)
	return "%02d:%02d" % [m / 60, m % 60]


func _update_phase() -> void:
	var p := _phase_for(effective_hour())
	if p != phase:
		phase = p
		phase_changed.emit(phase)
