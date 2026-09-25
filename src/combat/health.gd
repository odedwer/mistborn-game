class_name Health
extends Node
## Hit points for any actor. Add as a child named "Health" of the actor's body.
##
## Damage modifiers (pewter toughness, armour, blocking) register as Callables
## `func(amount: float, kind: StringName, source: Node) -> float` and are
## applied in order before the damage lands.

signal damaged(amount: float, source: Node, kind: StringName)
signal healed(amount: float)
signal died(killer: Node)

@export var max_health := 100.0
@export var regen_per_second := 0.0
@export var regen_delay := 4.0
@export var invulnerable := false

var current: float
var dead := false
var _since_hit := 0.0
var _modifiers: Array[Callable] = []


func _ready() -> void:
	current = max_health


func _physics_process(delta: float) -> void:
	if dead or regen_per_second <= 0.0:
		return
	_since_hit += delta
	if _since_hit >= regen_delay and current < max_health:
		heal(regen_per_second * delta)


func add_modifier(c: Callable) -> void:
	_modifiers.append(c)


func remove_modifier(c: Callable) -> void:
	_modifiers.erase(c)


## Damage kinds: &"blunt", &"blade", &"coin", &"fall", &"crush", &"fire".
func take_damage(amount: float, source: Node = null, kind: StringName = &"blunt") -> float:
	if dead or invulnerable or amount <= 0.0:
		return 0.0
	for m in _modifiers:
		amount = m.call(amount, kind, source)
		if amount <= 0.0:
			return 0.0
	current = maxf(current - amount, 0.0)
	_since_hit = 0.0
	damaged.emit(amount, source, kind)
	Events.damage_dealt.emit(get_parent(), amount, source, kind)
	if current <= 0.0:
		dead = true
		died.emit(source)
		Events.actor_died.emit(get_parent(), source)
	return amount


func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	var before := current
	current = minf(current + amount, max_health)
	if current > before:
		healed.emit(current - before)


func revive(fraction := 1.0) -> void:
	dead = false
	current = max_health * fraction
	healed.emit(current)


func ratio() -> float:
	return current / max_health if max_health > 0.0 else 0.0


## Finds the Health component on `node` or any ancestor (hitboxes are often
## child shapes of the actor).
static func find_on(node: Node) -> Health:
	var n := node
	while n != null:
		var h := n.get_node_or_null(^"Health")
		if h is Health:
			return h
		n = n.get_parent()
	return null
