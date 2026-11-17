class_name RoundEnding
extends RefCounted

# Real seconds, independent of gameplay speed tuning. Pose IDs address the new
# 4x4 interaction atlas. The original DO frames informed the action ordering.
const DOOR_TARGET := Vector2(.36, .025)
const ALIGN_TIME := .6
const OPEN_TIME := 1.35
const MAGIC_TIME := 2.9

static func index_for(round_index: int, round_count: int) -> int:
	return round_index + DifficultyRules.ROUND_COUNT - round_count

static func duration(round_index: int) -> float:
	return [6.0, 6.3, 7.2][clampi(round_index, 0, 2)]

static func exit_time(round_index: int) -> float:
	# In the final ending Santa stays with the tree for the celebration.
	return [4.1, 4.3, 99.0][clampi(round_index, 0, 2)]

static func door_open(round_index: int, seconds: float) -> float:
	var opening := smoothstep(ALIGN_TIME, OPEN_TIME, seconds)
	var closing := smoothstep(exit_time(round_index) + .9, exit_time(round_index) + 1.5, seconds)
	return opening * (1.0 - closing)

static func santa_presence(round_index: int, seconds: float) -> float:
	return 1.0 if seconds >= ALIGN_TIME and seconds < exit_time(round_index) + 1.5 else 0.0

static func santa_inside(round_index: int, seconds: float) -> bool:
	return seconds < OPEN_TIME or seconds >= exit_time(round_index) + .72

static func frame_at(round_index: int, seconds: float) -> int:
	if seconds < OPEN_TIME:
		return 0
	if round_index == 0:
		if seconds < 1.8: return 2
		if seconds < 2.2: return 3
		if seconds < 3.6: return 4 + int((seconds - 2.2) / .22) % 2
		return 6
	if round_index == 1:
		if seconds < 1.8: return 7
		if seconds < 2.3: return 8
		if seconds < 2.8: return 9
		if seconds < 3.4: return 10
		return 11
	if seconds < 1.8: return 12
	if seconds < 2.3: return 13
	if seconds < MAGIC_TIME: return 14
	return 15

static func tree_reveal(seconds: float) -> float:
	return smoothstep(MAGIC_TIME, MAGIC_TIME + 1.2, seconds)
