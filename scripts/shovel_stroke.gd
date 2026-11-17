class_name ShovelStroke
extends RefCounted

# Lower, push, lift, tip, recover. Simulation and animation share this clock.
const DURATION := 0.90
const CONTACT_START := 0.50 * DURATION
const CONTACT_END := (5.0 / 6.0) * DURATION
const FRAME_ENDS := [1.0/6, 2.0/6, 3.0/6, 4.0/6, 5.0/6, 1.0]

static func impact_time(direction: Vector2) -> float:
	# Side frame 11, rear frame 19 and front frame 27: one scoop per cycle.
	return DURATION * (.4 if absf(direction.y) > .55 else .5)

static func frame_at(seconds: float) -> int:
	var phase := fposmod(seconds, DURATION) / DURATION
	for i in FRAME_ENDS.size():
		if phase < FRAME_ENDS[i]:
			return i
	return 5

static func contact_seconds(start: float, duration: float, direction: Vector2 = Vector2.RIGHT) -> float:
	var contact_start := CONTACT_START
	var contact_end := CONTACT_END
	if absf(direction.y) > .55:
		contact_start = (.2 if direction.y < 0 else .4) * DURATION
		contact_end = .8 * DURATION
	return overlap_seconds(start, duration, contact_start, contact_end)

static func travel_seconds(start: float, duration: float, direction: Vector2) -> float:
	# Lean into a slower push, then recover. The compact blade needs overlapping
	# passes; full-speed travel left narrow untouched bands between strokes.
	return duration - contact_seconds(start, duration, direction) * .15

static func overlap_seconds(start: float, duration: float, begin: float, finish: float) -> float:
	# Integrate overlap, including a wrap, independently of simulation tick size.
	var phase := fposmod(start, DURATION)
	var contact := 0.0
	var left := duration
	while left > 0.000001:
		var end := minf(DURATION, phase + left)
		contact += maxf(0.0, minf(end, finish) - maxf(phase, begin))
		left -= end - phase
		phase = 0.0
	return contact
