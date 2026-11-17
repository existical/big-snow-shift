class_name HitReaction
extends RefCounted

# EXE DS:00B2: directional impact, collapse, repeated seated poses, turn/rise.
# DS:012A supplies these relative delays; real seconds are a remake setting.
const WEIGHTS := [3,3,3,3,10,10,10,10,10,10,10,10,10,3,3]
const FRAMES := [1,3,4,5,6,5,4,5,6,5,4,5,6,7,8]
const TOTAL_WEIGHT := 108.0
const GRACE_SECONDS := 1.8

static func phase_at(seconds: float, duration: float) -> int:
	var cursor := clampf(seconds / maxf(duration,.001),0,1) * TOTAL_WEIGHT
	for phase in WEIGHTS.size():
		if cursor < WEIGHTS[phase] - .000001:
			return phase
		cursor -= WEIGHTS[phase]
	return WEIGHTS.size() - 1

static func frame_at(seconds: float, duration: float, facing: Vector2, reduced_motion: bool = false) -> int:
	var phase := phase_at(seconds,duration)
	if reduced_motion and phase < 13:
		return 4
	if phase == 0:
		return 2 if facing.y < -.55 else (0 if facing.y > .55 else 1)
	return FRAMES[phase]

static func rise_fraction(seconds: float, duration: float) -> float:
	return smoothstep(105.0 / TOTAL_WEIGHT,1.0,seconds / maxf(duration,.001))

static func flip_for(facing: Vector2, frame: int) -> float:
	# The DOS loader creates TR9 by mirroring TR1. All later seated frames
	# use the same shared orientation, regardless of the incoming direction.
	return -1.0 if facing.x < -.4 and frame == 1 else 1.0
