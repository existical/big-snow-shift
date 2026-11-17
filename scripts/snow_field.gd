class_name SnowField
extends RefCounted

const WIDTH := 144
const HEIGHT := 72
const SHOVEL_RADIUS := Vector2(0.082, 0.043)
const MAX_PILE_DEPTH := 510
const PILE_HEIGHT := 36.0
const RENDER_PAD := 60.0
var cells := PackedInt32Array() # Total removable snow, including piled snow.
var piles := PackedInt32Array() # Extra depth; preserves the natural mound profile.
var remaining: int = 0
var initial: int = 1
const ALL_CELLS := Rect2i(0, 0, WIDTH, HEIGHT)
static var scanlines: Array = build_scanlines()
var dirty_cells := ALL_CELLS
var _dirty := true
var dirty: bool:
	get: return _dirty
	set(value):
		_dirty = value
		dirty_cells = ALL_CELLS if value else Rect2i()
var mask_pixels := PackedByteArray()
var raw_mask: Image
var smooth_mask: Image

static func build_scanlines() -> Array:
	var rows: Array = []
	for row in 16: rows.append([])
	for y in HEIGHT:
		var uv_y := (y + .5) / HEIGHT
		var bounds := StairSurface.bounds_at(lerpf(StairSurface.TOP, StairSurface.BOTTOM, uv_y))
		rows[StairSurface.tread_at(uv_y)].append({"y": y, "left": bounds.x, "right": bounds.y, "width": (bounds.y - bounds.x) / WIDTH})
	return rows

func mark_dirty(area: Rect2i) -> void:
	area = area.intersection(ALL_CELLS)
	if not area.has_area(): return
	dirty_cells = dirty_cells.merge(area) if _dirty else area
	_dirty = true

func generate(coverage: float, random: RandomNumberGenerator) -> void:
	cells.resize(WIDTH * HEIGHT)
	piles.resize(WIDTH * HEIGHT)
	piles.fill(0)
	remaining = 0
	var offset := random.randf_range(0.0, 50.0)
	for y in HEIGHT:
		for x in WIDTH:
			# Every tread starts covered from rail to rail. Difficulty changes depth.
			var drift := sin(x * 0.09 + offset) * 9.0 + cos(y * 0.23 + x * 0.04) * 7.0
			var value := clampi(int(lerpf(120, 255, coverage) + drift), 100, 255)
			cells[y * WIDTH + x] = value
			remaining += value
	initial = maxi(1, remaining)
	dirty = true

func brush(center: Vector2, radius: Vector2, amount: int, shovel_shape: bool = false) -> int:
	var before := remaining
	var low_x := maxi(0, int(floor((center.x - radius.x) * WIDTH)))
	var high_x := mini(WIDTH - 1, int(ceil((center.x + radius.x) * WIDTH)))
	var low_y := maxi(0, int(floor((center.y - radius.y) * HEIGHT)))
	var high_y := mini(HEIGHT - 1, int(ceil((center.y + radius.y) * HEIGHT)))
	for y in range(low_y, high_y + 1):
		for x in range(low_x, high_x + 1):
			var offset := (Vector2((x + 0.5) / WIDTH, (y + 0.5) / HEIGHT) - center) / radius
			if not inside_shovel(offset) if shovel_shape else offset.length_squared() > 1.0:
				continue
			var index := y * WIDTH + x
			var previous := int(cells[index])
			var value := 0 if amount >= 255 else maxi(0, previous - amount)
			if amount < 0:
				value = mini(255, previous - piles[index] - amount) + piles[index]
			piles[index] = maxi(0, piles[index] - maxi(0, previous - value))
			cells[index] = value
			remaining += value - previous
	if remaining != before:
		mark_dirty(Rect2i(low_x, low_y, high_x - low_x + 1, high_y - low_y + 1))
	return before - remaining

func add_pile(center: Vector2, peak: int, variant: float = 0.0) -> int:
	var bounds := StairSurface.bounds_at(StairSurface.project(center).y)
	var radius := Vector2(lerpf(20, 28, center.y) / (bounds.y - bounds.x), lerpf(9, 12, center.y) / (StairSurface.BOTTOM - StairSurface.TOP))
	var before := remaining
	for y in range(maxi(0, floori((center.y - radius.y * 1.2) * HEIGHT)), mini(HEIGHT, ceili((center.y + radius.y * 1.2) * HEIGHT))):
		for x in range(maxi(0, floori((center.x - radius.x * 1.2) * WIDTH)), mini(WIDTH, ceili((center.x + radius.x * 1.2) * WIDTH))):
			var offset := (Vector2((x + .5) / WIDTH, (y + .5) / HEIGHT) - center) / radius
			var angle := offset.angle()
			var rim := 1.0 + .08 * sin(angle * 3 + variant) + .045 * cos(angle * 5 - variant * .7)
			var profile := pow(maxf(0, 1.0 - offset.length_squared() / (rim * rim)), 3.0)
			var index := y * WIDTH + x
			var added := mini(MAX_PILE_DEPTH - piles[index], roundi(maxi(0, peak) * profile))
			piles[index] += added
			cells[index] += added
			remaining += added
	if remaining != before:
		mark_dirty(Rect2i(Vector2i(floori((center.x - radius.x * 1.2) * WIDTH), floori((center.y - radius.y * 1.2) * HEIGHT)),
			Vector2i(ceili(radius.x * 2.4 * WIDTH) + 2, ceili(radius.y * 2.4 * HEIGHT) + 2)))
	return remaining - before

func has_visible_piles() -> bool:
	# Do not let the tiny-residue shortcut erase an entire small, visible mound.
	for depth in piles:
		if depth >= 8:
			return true
	return false

func surface_height(point: Vector2) -> float:
	var index := clampi(floori(point.y * HEIGHT), 0, HEIGHT - 1) * WIDTH + clampi(floori(point.x * WIDTH), 0, WIDTH - 1)
	var base := cells[index] - piles[index]
	var row := StairSurface.tread_at(point.y)
	var y := StairSurface.project(point).y
	var phase := clampf((y - StairSurface.TREAD_EDGES[row]) / (StairSurface.TREAD_EDGES[row + 1] - StairSurface.TREAD_EDGES[row]), 0, 1)
	var roll := .40 + .60 * smoothstep(0, .54, phase) - .12 * smoothstep(.78, 1, phase)
	var height := lerpf(11.5, 19, point.y) * sqrt(base / 255.0) * roll if base > 0 else 0.0
	return height + PILE_HEIGHT * sqrt(piles[index] / float(MAX_PILE_DEPTH))

func clear_path(start: Vector2, finish: Vector2, strength: int, radius: Vector2 = SHOVEL_RADIUS) -> int:
	if strength <= 0:
		return 0
	var steps := maxi(1, int(ceil(start.distance_to(finish) / (radius.x * .5))))
	var removed := 0
	for i in steps:
		removed += brush(start.lerp(finish, float(i + 1) / steps), radius, strength, true)
	return removed

# Horizontal work is a strip of one stair, independent of animated blade height.
# Test cell extents against the swept world-X interval so even a long tick cannot
# jump over a column. Each mask scanline belongs to exactly one tread.
func tread_strip(row: int, from_x: float, to_x: float, clear: bool = false, depth: int = 255 + MAX_PILE_DEPTH) -> int:
	var total := 0
	var low := minf(from_x, to_x)
	var high := maxf(from_x, to_x)
	var changed := Rect2i()
	for scan in scanlines[row]:
		var y: int = scan.y
		if high <= scan.left or low >= scan.right:
			continue
		var first := maxi(0, floori((low - scan.left) / scan.width))
		var last := mini(WIDTH - 1, ceili((high - scan.left) / scan.width) - 1)
		var strip := Rect2i(first, y, last - first + 1, 1)
		changed = changed.merge(strip) if changed.has_area() else strip
		for x in range(first, last + 1):
			var index := y * WIDTH + x
			total += remove_depth(index, depth) if clear else cells[index]
	if clear and total > 0:
		remaining -= total
		mark_dirty(changed)
	return total

func has_snow_near(point: Vector2, radius: Vector2 = SHOVEL_RADIUS) -> bool:
	for y in range(maxi(0, int((point.y - radius.y) * HEIGHT)), mini(HEIGHT, ceili((point.y + radius.y) * HEIGHT))):
		for x in range(maxi(0, int((point.x - radius.x) * WIDTH)), mini(WIDTH, ceili((point.x + radius.x) * WIDTH))):
			var offset := (Vector2((x + .5) / WIDTH, (y + .5) / HEIGHT) - point) / radius
			if inside_shovel(offset) and cells[y * WIDTH + x] > 0:
				return true
	return false

# Whole-cell chunks and narrow movement probes use the same cell intersections.
# Even a probe thinner than one cell must detect snow instead of falling between
# sample centers. Coverage smoothing belongs to the renderer, not the cut clock.
func box(area: Rect2, clear: bool = false, depth: int = 255 + MAX_PILE_DEPTH) -> int:
	if area.end.x <= 0 or area.end.y <= 0 or area.position.x >= 1 or area.position.y >= 1:
		return 0
	var first := Vector2i(maxi(0, floori(area.position.x * WIDTH)), maxi(0, floori(area.position.y * HEIGHT)))
	var last := Vector2i(mini(WIDTH - 1, ceili(area.end.x * WIDTH) - 1), mini(HEIGHT - 1, ceili(area.end.y * HEIGHT) - 1))
	var total := 0
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var index := y * WIDTH + x
			total += remove_depth(index, depth) if clear else cells[index]
	if clear and total > 0:
		remaining -= total
		mark_dirty(Rect2i(first, last - first + Vector2i.ONE))
	return total

func remove_depth(index: int, depth: int) -> int:
	# Lift the upper pile first, then any base snow reached by this scoop.
	# Callers account for the returned mass once for the complete footprint.
	var removed := mini(cells[index], maxi(0, depth))
	cells[index] -= removed
	piles[index] = maxi(0, piles[index] - removed)
	return removed

static func inside_shovel(offset: Vector2) -> bool:
	# A scoop clears a short strip with rounded corners, not round footprints.
	var corner := (offset.abs() - Vector2.ONE * .65).max(Vector2.ZERO) / .35
	return corner.length_squared() <= 1.0

func completion() -> float:
	return clampf(1.0 - float(remaining) / initial, 0.0, 1.0)

func image() -> Image:
	if smooth_mask != null and not dirty:
		return smooth_mask
	# Keep depth and coverage separate. Linear interpolation of the coverage
	# channel rounds cut edges without making low-depth icicle deposits transparent.
	if raw_mask == null:
		mask_pixels.resize(WIDTH * HEIGHT * 4)
		dirty_cells = ALL_CELLS
	var area := dirty_cells
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var i := y * WIDTH + x
			mask_pixels[i * 4] = cells[i] - piles[i]
			mask_pixels[i * 4 + 1] = 255 if cells[i] > 0 else 0
			mask_pixels[i * 4 + 2] = roundi(piles[i] * 255.0 / MAX_PILE_DEPTH)
			mask_pixels[i * 4 + 3] = 255
	if raw_mask == null:
		raw_mask = Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8, mask_pixels)
	else:
		raw_mask.set_data(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8, mask_pixels)
	# Smooth the procedural coverage field before extrusion so cut walls follow
	# rounded contours instead of revealing the simulation's coarse cell corners.
	if smooth_mask == null or area == ALL_CELLS:
		smooth_mask = raw_mask.duplicate()
		smooth_mask.resize(WIDTH * 2, HEIGHT * 2, Image.INTERPOLATE_CUBIC)
	else:
		var output := area.grow(2).intersection(ALL_CELLS)
		var source := output.grow(2).intersection(ALL_CELLS)
		var patch := raw_mask.get_region(source)
		patch.resize(source.size.x * 2, source.size.y * 2, Image.INTERPOLATE_CUBIC)
		smooth_mask.blit_rect(patch, Rect2i((output.position - source.position) * 2, output.size * 2), output.position * 2)
	dirty = false
	return smooth_mask

func snapshot() -> Dictionary:
	return {"format": 2, "cells": Marshalls.raw_to_base64(cells.to_byte_array()), "piles": Marshalls.raw_to_base64(piles.to_byte_array()), "initial": initial}

func restore(data: Dictionary) -> bool:
	if not data.get("cells") is String or not data.get("initial") is float and not data.get("initial") is int:
		return false
	var decoded := Marshalls.base64_to_raw(data.cells)
	var restored_cells := PackedInt32Array()
	var restored_piles := PackedInt32Array()
	if data.get("format", 1) == 1:
		if decoded.size() != WIDTH * HEIGHT:
			return false
		restored_cells = PackedInt32Array(Array(decoded))
		restored_piles.resize(WIDTH * HEIGHT)
	else:
		if data.get("format") != 2 or decoded.size() != WIDTH * HEIGHT * 4 or not data.get("piles") is String:
			return false
		var pile_bytes := Marshalls.base64_to_raw(data.piles)
		if pile_bytes.size() != decoded.size():
			return false
		restored_cells = decoded.to_int32_array()
		restored_piles = pile_bytes.to_int32_array()
		for i in restored_cells.size():
			var base := restored_cells[i] - restored_piles[i]
			if base < 0 or base > 255 or restored_piles[i] < 0 or restored_piles[i] > MAX_PILE_DEPTH:
				return false
	cells = restored_cells
	piles = restored_piles
	initial = clampi(int(data.initial), 1, WIDTH * HEIGHT * 255)
	remaining = 0
	for value in cells:
		remaining += value
	dirty = true
	return true
