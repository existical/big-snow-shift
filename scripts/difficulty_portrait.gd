class_name DifficultyPortrait
extends Node2D
## Reuses the actual caretaker art and rigid shovel, with original weather motifs.
var difficulty := "easy"

func _draw() -> void:
	var index := DifficultyRules.IDS.find(difficulty)
	var colors := [Color("49bdac"),Color("479bcc"),Color("7064bc"),Color("b75b9a")]
	draw_circle(Vector2.ZERO,88,colors[maxi(0,index)].darkened(.25))
	draw_arc(Vector2.ZERO,88,0,TAU,64,Color(1,1,1,.35),3,true)
	draw_arc(Vector2(0,8),74,PI*.08,PI*.93,36,Color("dff8ff"),7,true)
	if index == 3:
		var cape := PackedVector2Array([Vector2(-8,-24),Vector2(-41,4),Vector2(-88,70),Vector2(-43,60),Vector2(-66,90),Vector2(26,64),Vector2(17,-21)])
		draw_colored_polygon(cape,Color("db3855"))
		draw_polyline(cape,Color("ffbc59"),3,true)
		for i in 3:
			draw_line(Vector2(-10+i*9,-10),Vector2(-54+i*23,62),Color("f36b70"),3,true)
	for i in (1 if index == 0 else (3 if index == 1 else 6)):
		var angle := -.3 + i * 1.07
		var point := Vector2(cos(angle)*72,sin(angle)*61-10)
		for axis in 3:
			var ray := Vector2.from_angle(axis * PI / 3) * (8 if index < 2 else 6)
			draw_line(point-ray,point+ray,Color("dff7ff"),2.4,true)
	if index >= 2:
		for i in 3:
			draw_arc(Vector2(-15,12+i*10),78,-.7,.15,16,Color(1,1,1,.45),2,true)
	CaretakerAnimator.draw(self,Vector2(-12,100),190,30,1,0,Color.WHITE)
