class_name TimeOfDayIndicator
extends Control
## Small, subtle HUD clock: a sun or crescent-moon glyph and the `TimeOfDay`
## time ("14:20"). Dim by design; the glyph blends through dusk and dawn.

const SIZE := Vector2(124, 34)
const SUN := Color(0.95, 0.62, 0.32)
const MOON := Color(0.78, 0.82, 0.92)

var _label: Label
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate = Color(1, 1, 1, 0.85)
	_label = Label.new()
	_label.position = Vector2(36, 1)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.8))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	refresh()


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		refresh()


## Updates the text and glyph from the clock (also called by tests).
func refresh() -> void:
	if _label != null:
		_label.text = text()
	queue_redraw()


## The shown text: the world clock.
func text() -> String:
	return TimeOfDay.clock_text()


func _draw() -> void:
	var n := TimeOfDay.night_factor()
	var c := Vector2(16, 17)
	if n < 0.5:
		var col := SUN.lerp(Color(0.8, 0.45, 0.3), n * 2.0)
		draw_circle(c, 6.5, col)
		for k in 8:
			var a := TAU * float(k) / 8.0
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * 9.0, c + d * 13.0, col, 2.0, true)
	else:
		# Crescent: the lit limb between two arcs.
		var pts := PackedVector2Array()
		for k in 17:
			var a := lerpf(-PI * 0.5, PI * 0.5, float(k) / 16.0)
			pts.append(c + Vector2(cos(a), sin(a)) * 11.0)
		for k in range(16, -1, -1):
			var a := lerpf(-PI * 0.5, PI * 0.5, float(k) / 16.0)
			pts.append(c + Vector2(cos(a) * 4.5, sin(a) * 11.0))
		draw_colored_polygon(pts, MOON.lerp(Color(0.7, 0.6, 0.55), (1.0 - n) * 2.0))
