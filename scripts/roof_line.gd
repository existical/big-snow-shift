class_name RoofLine
extends RefCounted

# Underside of the painted roof snow in the 1280 × 720 scene.
const EAVE: Array[Vector2] = [
	Vector2(140, 182), Vector2(210, 177), Vector2(295, 178), Vector2(369, 178),
	Vector2(420, 181), Vector2(453, 155), Vector2(500, 121), Vector2(546, 87),
	Vector2(590, 53), Vector2(638, 22), Vector2(681, 48), Vector2(725, 82),
	Vector2(772, 117), Vector2(819, 153), Vector2(849, 180),
	Vector2(920, 179), Vector2(985, 180), Vector2(1053, 182), Vector2(1160, 183)]

static func anchor(x: float) -> Vector2:
	x = clampf(x, EAVE[0].x, EAVE[-1].x)
	for i in range(1, EAVE.size()):
		if x <= EAVE[i].x:
			var left := EAVE[i - 1]
			var right := EAVE[i]
			return Vector2(x, lerpf(left.y, right.y, (x - left.x) / (right.x - left.x)))
	return EAVE[-1]

static func icicle_top(target: Vector2, age: float, warning: float, flight: float, length: float) -> Vector2:
	var origin := anchor(target.x)
	if age < warning:
		return origin
	var progress := clampf((age - warning) / flight, 0, 1)
	return origin.lerp(target - Vector2(0, length), progress * progress)
