class_name UIHelpers
extends RefCounted
## Small helpers for building UI screens procedurally in code, so menus stay
## data-driven and don't need heavyweight hand-authored `.tscn` node trees.
## Every UI scene in `src/ui/` is a thin `.tscn` (root + script) that calls
## into these helpers from `_ready()`.

const THEME_PATH := "res://src/ui/theme.tres"

static var _theme: Theme


static func theme() -> Theme:
	if _theme == null:
		_theme = load(THEME_PATH)
	return _theme


static func title_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"TitleLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func heading_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeadingLabel"
	return l


static func dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"DimLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func(): AudioManager.play_ui(&"ui_hover"))
	b.pressed.connect(func(): AudioManager.play_ui(&"ui_click"))
	return b


static func labeled_slider(label_text: String, min_v: float, max_v: float, step: float, value: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(220, 0)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(240, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(50, 0)
	value_lbl.text = str(value)
	slider.value_changed.connect(func(v: float): value_lbl.text = "%.2f" % v)
	row.add_child(lbl)
	row.add_child(slider)
	row.add_child(value_lbl)
	row.set_meta("slider", slider)
	return row


static func get_slider(row: HBoxContainer) -> HSlider:
	return row.get_meta("slider") as HSlider


static func labeled_option(label_text: String, options: Array, selected: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(220, 0)
	var opt := OptionButton.new()
	for o in options:
		opt.add_item(str(o))
	opt.selected = selected
	opt.focus_mode = Control.FOCUS_ALL
	row.add_child(lbl)
	row.add_child(opt)
	row.set_meta("option", opt)
	return row


static func get_option(row: HBoxContainer) -> OptionButton:
	return row.get_meta("option") as OptionButton


static func labeled_checkbox(label_text: String, value: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(220, 0)
	var cb := CheckBox.new()
	cb.button_pressed = value
	cb.focus_mode = Control.FOCUS_ALL
	row.add_child(lbl)
	row.add_child(cb)
	row.set_meta("checkbox", cb)
	return row


static func get_checkbox(row: HBoxContainer) -> CheckBox:
	return row.get_meta("checkbox") as CheckBox


static func vsep(h := 12.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Applies the shared theme to the whole subtree rooted at `root`.
static func apply_theme(root: Control) -> void:
	root.theme = theme()
