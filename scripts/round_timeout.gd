class_name RoundTimeout
extends RefCounted

# Original DO40..55: emerge with wand, lose balance, roll, slide out of view.
# These are modern real-second timings, independent of gameplay multipliers.
const DURATION := 7.2
const SLIP_TIME := 2.0
const ROLL_TIME := 2.65
const LAND_TIME := 5.1
const SLIDE_TIME := 5.5
const EXIT_TIME := 6.9

static func frame_at(seconds: float, reduced_motion: bool = false) -> int:
	if seconds < .45: return 0
	if seconds < .9: return 1
	if seconds < 1.15: return 2
	if seconds < 1.45: return 3
	if seconds < 1.7: return 4
	if seconds < SLIP_TIME: return 5
	if seconds < 2.3: return 6
	if seconds < ROLL_TIME: return 7
	if seconds < LAND_TIME:
		return 13 if reduced_motion else 8 + int((seconds - ROLL_TIME) / .18) % 4
	if seconds < SLIDE_TIME: return 12
	if seconds < 6.0: return 13
	if seconds < 6.5: return 14
	return 15

static func position_at(seconds: float, reduced_motion: bool = false) -> Vector2:
	if seconds < ROLL_TIME:
		return Vector2(640, lerpf(305, 359, smoothstep(.6, ROLL_TIME, seconds)))
	if seconds < LAND_TIME:
		var progress := clampf((seconds - ROLL_TIME) / (LAND_TIME - ROLL_TIME), 0, 1)
		var bounce := 0.0 if reduced_motion else absf(sin(progress * TAU * 4)) * 8
		return Vector2(640 + progress * 18 + sin(progress * TAU * 1.5) * (0 if reduced_motion else 12), 359 + pow(progress, 1.35) * 251 - bounce)
	return Vector2(658, lerpf(610, 840, smoothstep(SLIDE_TIME, EXIT_TIME, seconds)))

static func size_at(seconds: float) -> float:
	return lerpf(140, 200, smoothstep(SLIP_TIME, LAND_TIME, seconds))

static func door_open(seconds: float) -> float:
	return smoothstep(.15, .9, seconds)

static func santa_inside(seconds: float) -> bool:
	return seconds < .9
