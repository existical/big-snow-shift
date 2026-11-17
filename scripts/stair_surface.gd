class_name StairSurface
extends RefCounted

# Traced at the INSIDE stone/rail seam in the 1672 x 941 house illustration.
# Each tread widens over its shallow top surface, then has a vertical front.
const TOP := 358.087141
const BOTTOM := 664.144527
const TOP_WIDTH := 298.564593
const BOTTOM_WIDTH := 702.009569
const CENTER := 636.555024
const TREAD_EDGES: Array[float] = [358.087141, 371.859724, 386.397450, 402.465462, 417.768332, 434.601488, 451.434644, 469.798087, 488.926674, 508.820404, 530.244421, 550.903294, 573.857598, 596.811902, 621.296493, 646.546227, 664.144527]
const TREAD_LEFT: Array[float] = [488.421053, 478.468900, 466.985646, 457.033493, 444.019139, 431.004785, 417.990431, 404.976077, 391.196172, 378.181818, 363.636364, 349.090909, 333.779904, 318.468900, 301.626794, 285.550239]
const TREAD_RIGHT: Array[float] = [786.985646, 796.172249, 804.593301, 816.076555, 828.325359, 841.339713, 854.354067, 868.133971, 881.148325, 895.693780, 910.239234, 925.550239, 940.861244, 956.937799, 972.248804, 987.559809]

static func tread_at(uv_y: float) -> int:
	var world_y := lerpf(TOP, BOTTOM, uv_y)
	for row in TREAD_LEFT.size():
		if world_y < TREAD_EDGES[row + 1]:
			return row
	return TREAD_LEFT.size() - 1

static func tread_center(row: int) -> float:
	return ((TREAD_EDGES[row] + TREAD_EDGES[row + 1]) * .5 - TOP) / (BOTTOM - TOP)

static func bounds_at(y: float) -> Vector2:
	var row := 15
	for i in 16:
		if y < TREAD_EDGES[i + 1]:
			row = i
			break
	var phase := clampf((y - TREAD_EDGES[row]) / (TREAD_EDGES[row + 1] - TREAD_EDGES[row]), 0, 1)
	var blend := smoothstep(0.0, 0.15, phase) if row > 0 else 1.0
	return Vector2(lerpf(TREAD_LEFT[maxi(0, row - 1)], TREAD_LEFT[row], blend), lerpf(TREAD_RIGHT[maxi(0, row - 1)], TREAD_RIGHT[row], blend))

static func project(point: Vector2) -> Vector2:
	var y := lerpf(TOP, BOTTOM, point.y)
	var bounds := bounds_at(y)
	return Vector2(lerpf(bounds.x, bounds.y, point.x), y)

static func unproject(point: Vector2) -> Vector2:
	var bounds := bounds_at(point.y)
	return Vector2((point.x - bounds.x) / (bounds.y - bounds.x), (point.y - TOP) / (BOTTOM - TOP))

static func constrain(point: Vector2) -> Vector2:
	return point.clamp(Vector2(0.025, 0.025), Vector2(0.975, 0.975))

static func contains(point: Vector2) -> bool:
	var logical := unproject(point)
	return Rect2(0, 0, 1, 1).has_point(logical)
