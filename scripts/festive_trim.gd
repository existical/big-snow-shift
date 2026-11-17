class_name FestiveTrim
extends Control

var compact := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var width := size.x
	# Frosted corners and a snow cap stay crisp at every viewport scale.
	draw_line(Vector2(23, 1), Vector2(width - 23, 1), Color("edfaff"), 9, true)
	for x in [28.0, 44.0, width * .42, width * .42 + 13, width - 40]:
		draw_circle(Vector2(x, 3), 5 if compact else 7, Color("edfaff"))
	if compact:
		return
	var colors := [Color("ff717b"), Color("ffd85a"), Color("76f1d0"), Color("ffd85a")]
	for i in int((width - 40) / 38):
		var x := 25.0 + i * 38
		draw_circle(Vector2(x, size.y - 8), 3.5, colors[i % colors.size()])
	star(Vector2(-4, 43), 13, Color("ffdb55"))
	star(Vector2(width + 2, size.y - 40), 10, Color("ffdb55"))

func star(at: Vector2, radius: float, tint: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		points.append(at + Vector2.from_angle(-PI / 2 + i * PI / 5) * radius * (1.0 if i % 2 == 0 else .48))
	draw_colored_polygon(points, tint)
