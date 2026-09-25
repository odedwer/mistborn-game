class_name ProceduralTextures
extends RefCounted
## Fallback texture painter used when the generated PNG textures are absent.
##
## Everything is drawn with native `Image.fill_rect` calls (tiled so edges
## wrap seamlessly), then a height image is turned into a normal map with
## `Image.bump_map_to_normal_map`. Takes a few milliseconds per texture.

const SIZE := 256


## Returns [albedo: Image, normal: Image] for a texture set name.
static func generate(set_name: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(set_name)
	var alb := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var hgt := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	match set_name:
		"stone_wall":
			_blocks(alb, hgt, rng, 6, Vector2i(56, 118), 3, Color(0.47, 0.45, 0.42), 0.10, Color(0.20, 0.19, 0.18), false)
		"brick_soot":
			_blocks(alb, hgt, rng, 16, Vector2i(34, 34), 2, Color(0.36, 0.2, 0.15), 0.12, Color(0.16, 0.15, 0.14), true)
		"cobblestone":
			_blocks(alb, hgt, rng, 10, Vector2i(18, 34), 4, Color(0.32, 0.32, 0.33), 0.12, Color(0.09, 0.09, 0.09), false)
		"slate_roof":
			_slate(alb, hgt, rng)
		"wood_planks":
			_planks(alb, hgt, rng)
		"plaster_dirty":
			_plaster(alb, hgt, rng, Color(0.55, 0.52, 0.47))
		"iron_rusty":
			_plaster(alb, hgt, rng, Color(0.2, 0.2, 0.21))
			_speckle(alb, hgt, rng, 500, Color(0.36, 0.17, 0.08), 0.15, 6)
		_:
			_plaster(alb, hgt, rng, Color(0.5, 0.5, 0.5))
	_speckle(alb, hgt, rng, 1400, Color(0, 0, 0, 0), 0.12, 2)
	alb.generate_mipmaps()
	hgt.bump_map_to_normal_map(6.0)
	hgt.generate_mipmaps()
	return [alb, hgt]


## Fills a rectangle that wraps around the image edges (seamless tiling).
static func _wrap_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	x = posmod(x, SIZE)
	y = posmod(y, SIZE)
	var w0 := mini(w, SIZE - x)
	var h0 := mini(h, SIZE - y)
	img.fill_rect(Rect2i(x, y, w0, h0), c)
	if w0 < w:
		img.fill_rect(Rect2i(0, y, w - w0, h0), c)
	if h0 < h:
		img.fill_rect(Rect2i(x, 0, w0, h - h0), c)
	if w0 < w and h0 < h:
		img.fill_rect(Rect2i(0, 0, w - w0, h - h0), c)


static func _vary(c: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var v := rng.randf_range(-amount, amount)
	var warm := rng.randf_range(-amount, amount) * 0.3
	return Color(clampf(c.r + v + warm, 0, 1), clampf(c.g + v, 0, 1), clampf(c.b + v - warm, 0, 1))


## Coursed masonry: `rows` courses with block widths in `wr`, `mortar` px.
static func _blocks(alb: Image, hgt: Image, rng: RandomNumberGenerator, rows: int, wr: Vector2i,
		mortar: int, base: Color, vary: float, mortar_col: Color, running_bond: bool) -> void:
	alb.fill(mortar_col)
	hgt.fill(Color(0.15, 0.15, 0.15))
	var rh := SIZE / rows
	for r in rows:
		var x := rng.randi_range(0, wr.y) if not running_bond else (wr.x / 2 if r % 2 == 1 else 0)
		var start := x
		while x < start + SIZE:
			var w := rng.randi_range(wr.x, wr.y)
			if x + w > start + SIZE:
				w = start + SIZE - x
			var c := _vary(base, rng, vary)
			_wrap_rect(alb, x + mortar, r * rh + mortar, w - mortar, rh - mortar, c)
			var hv := rng.randf_range(0.65, 0.95)
			_wrap_rect(hgt, x + mortar, r * rh + mortar, w - mortar, rh - mortar, Color(hv, hv, hv))
			# Chipped highlight/shadow edges.
			_wrap_rect(alb, x + mortar, r * rh + mortar, w - mortar, 1, c.lightened(0.08))
			_wrap_rect(hgt, x + mortar, r * rh + rh - 2, w - mortar, 1, Color(hv * 0.8, hv * 0.8, hv * 0.8))
			x += w


static func _slate(alb: Image, hgt: Image, rng: RandomNumberGenerator) -> void:
	alb.fill(Color(0.05, 0.055, 0.06))
	hgt.fill(Color(0.1, 0.1, 0.1))
	var rows := 12
	var rh := SIZE / rows
	for r in rows:
		var x := (rng.randi_range(0, 12) if r % 2 == 0 else 12)
		var start := x
		while x < start + SIZE:
			var w := rng.randi_range(18, 26)
			if x + w > start + SIZE:
				w = start + SIZE - x
			var c := _vary(Color(0.17, 0.19, 0.22), rng, 0.05)
			for k in 4:
				var t := float(k) / 4.0
				var cc := c.lerp(c.lightened(0.15), t)
				_wrap_rect(alb, x + 1, r * rh + int(t * rh), w - 2, rh / 4 + 1, cc)
				var hv := 0.4 + 0.5 * t
				_wrap_rect(hgt, x + 1, r * rh + int(t * rh), w - 2, rh / 4 + 1, Color(hv, hv, hv))
			x += w


static func _planks(alb: Image, hgt: Image, rng: RandomNumberGenerator) -> void:
	alb.fill(Color(0.08, 0.06, 0.05))
	hgt.fill(Color(0.2, 0.2, 0.2))
	var planks := 8
	var pw := SIZE / planks
	for p in planks:
		var c := _vary(Color(0.24, 0.17, 0.12), rng, 0.05)
		_wrap_rect(alb, p * pw + 1, 0, pw - 2, SIZE, c)
		_wrap_rect(hgt, p * pw + 1, 0, pw - 2, SIZE, Color(0.8, 0.8, 0.8))
		for g in 10:
			var gy := rng.randi_range(0, SIZE)
			var gc := c.darkened(rng.randf_range(0.1, 0.3))
			_wrap_rect(alb, p * pw + rng.randi_range(2, pw - 6), gy, rng.randi_range(2, 4), rng.randi_range(20, 80), gc)
		var seam := rng.randi_range(0, SIZE)
		_wrap_rect(alb, p * pw, seam, pw, 2, Color(0.06, 0.05, 0.04))
		_wrap_rect(hgt, p * pw, seam, pw, 2, Color(0.2, 0.2, 0.2))


static func _plaster(alb: Image, hgt: Image, rng: RandomNumberGenerator, base: Color) -> void:
	alb.fill(base)
	hgt.fill(Color(0.6, 0.6, 0.6))
	for i in 160:
		var w := rng.randi_range(8, 60)
		var h := rng.randi_range(8, 60)
		var c := _vary(base, rng, 0.07)
		var x := rng.randi_range(0, SIZE)
		var y := rng.randi_range(0, SIZE)
		_wrap_rect(alb, x, y, w, h, c)
		var hv := rng.randf_range(0.5, 0.7)
		_wrap_rect(hgt, x, y, w, h, Color(hv, hv, hv))
	# Vertical grime streaks.
	for i in 40:
		var x := rng.randi_range(0, SIZE)
		var streak_len := rng.randi_range(30, 180)
		_wrap_rect(alb, x, rng.randi_range(0, SIZE), rng.randi_range(1, 4), streak_len, base.darkened(rng.randf_range(0.15, 0.35)))


## Small random dots: grit in the height map and dark/tinted specks.
static func _speckle(alb: Image, hgt: Image, rng: RandomNumberGenerator, count: int, col: Color,
		strength: float, max_size: int) -> void:
	for i in count:
		var x := rng.randi_range(0, SIZE)
		var y := rng.randi_range(0, SIZE)
		var s := rng.randi_range(1, max_size)
		if col.a > 0.0:
			_wrap_rect(alb, x, y, s, s, _vary(col, rng, 0.05))
		else:
			var px := alb.get_pixel(x % SIZE, y % SIZE)
			_wrap_rect(alb, x, y, s, s, px.darkened(rng.randf_range(0.0, strength * 2.0)))
		var hv := rng.randf_range(0.3, 0.6)
		_wrap_rect(hgt, x, y, s, s, Color(hv, hv, hv))
