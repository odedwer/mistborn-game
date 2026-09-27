extends Node
## Small controller-rumble helper. Every call is a no-op when
## `GameSettings.vibration_enabled` is false or no joypad is connected, so
## other systems can call these unconditionally.
##
## Hooked up to: Push/Pull strength (player.gd), landing impact (player.gd),
## taking damage (hud.gd, via `Events.damage_dealt`), and coin hits (coin.gd).

const DEFAULT_DEVICE := 0


## Raw pulse: `weak`/`strong` are 0..1 motor strengths, `duration` in seconds
## (0 = until stopped). Safe to call every frame (Godot coalesces repeats).
func pulse(weak: float, strong: float, duration: float = 0.12, device: int = DEFAULT_DEVICE) -> void:
	if not _enabled():
		return
	Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


func stop(device: int = DEFAULT_DEVICE) -> void:
	Input.stop_joy_vibration(device)


## A held Push/Pull line. `strength` is 0..1 (see `Events.allomantic_line_used`).
func push_pull(strength: float) -> void:
	if strength <= 0.0:
		return
	pulse(strength * 0.25, strength * 0.55, 0.08)


## A landing impact in m/s over the safe-landing threshold.
func landing(impact_over_safe: float) -> void:
	if impact_over_safe <= 0.0:
		return
	var s := clampf(impact_over_safe / 20.0, 0.15, 1.0)
	pulse(s * 0.4, s, 0.2)


## Took `amount` damage.
func damage(amount: float) -> void:
	var s := clampf(amount / 40.0, 0.2, 1.0)
	pulse(s * 0.3, s * 0.8, 0.18)


## A coin (thrown/Pushed by the player) hit something.
func coin_hit() -> void:
	pulse(0.15, 0.35, 0.06)


func _enabled() -> bool:
	return GameSettings.vibration_enabled and Input.get_connected_joypads().size() > 0
