class_name CoinPool
extends Node
## Pool and manager for every Coin in play (not an autoload: created lazily
## by `CoinPool.get_for(node)` and added to the current scene).
##
## Caps active coins at `max_active` (recycling the oldest), clamps coin speed,
## and recycles coins left alone for `idle_lifetime` seconds. All per-coin
## work happens here, in one loop per physics tick.

const GROUP := &"coin_pool"
const COIN_SCENE := preload("res://src/combat/coin.tscn")

@export var max_active := 256
## Seconds after the last throw/Push/Pull before a coin is recycled.
@export var idle_lifetime := 20.0
## Terminal speed of a coin (m/s).
@export var max_coin_speed := 85.0
## Coins below this height are recycled.
@export var kill_height := -500.0

var _active: Array[Coin] = []
var _free: Array[Coin] = []


## Returns the scene's pool, creating it on first use.
static func get_for(node: Node) -> CoinPool:
	var tree := node.get_tree()
	var existing := tree.get_first_node_in_group(GROUP)
	if existing is CoinPool:
		return existing
	var pool := CoinPool.new()
	pool.name = "CoinPool"
	pool.add_to_group(GROUP)
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(pool)
	return pool


func active_count() -> int:
	return _active.size()


func active_coins() -> Array[Coin]:
	return _active


## Puts a coin into play at `xform` with `velocity`. `thrower` gets credit.
func spawn(xform: Transform3D, velocity: Vector3, thrower: Node = null) -> Coin:
	var coin: Coin
	if not _free.is_empty():
		coin = _free.pop_back()
		add_child(coin)
		MetalRegistry.register(coin.metallic)
	elif _active.size() >= max_active:
		coin = _active.pop_front()
	else:
		coin = COIN_SCENE.instantiate() as Coin
		add_child(coin)
	coin.global_transform = xform
	coin.linear_velocity = velocity
	coin.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	coin.sleeping = false
	coin.freeze = false
	coin.visible = true
	coin.active = true
	coin.idle_time = 0.0
	coin.virtual_anchor_time = 0.0
	coin.impact_speed = velocity.length()
	coin.last_pusher = null
	coin.set_last_pusher(thrower)
	_active.append(coin)
	return coin


## Takes a coin out of play (it stays allocated for reuse).
func recycle(coin: Coin) -> void:
	var i := _active.find(coin)
	if i >= 0:
		_active.remove_at(i)
	_park(coin)


func _park(coin: Coin) -> void:
	if not coin.active:
		return
	coin.active = false
	coin.linear_velocity = Vector3.ZERO
	coin.angular_velocity = Vector3.ZERO
	if coin.get_parent() == self:
		remove_child(coin)  # Metallic unregisters on exit_tree
	_free.append(coin)


func _physics_process(delta: float) -> void:
	var i := 0
	while i < _active.size():
		var c := _active[i]
		if not is_instance_valid(c):
			_active.remove_at(i)
			continue
		var v := c.linear_velocity
		var sp := v.length()
		if sp > max_coin_speed:
			c.linear_velocity = v * (max_coin_speed / sp)
			sp = max_coin_speed
		c.pool_tick(delta, sp)
		if c.idle_time > idle_lifetime or c.global_position.y < kill_height:
			_active.remove_at(i)
			_park(c)
			continue
		i += 1


func _exit_tree() -> void:
	for c in _free:
		if is_instance_valid(c):
			c.free()
	_free.clear()
