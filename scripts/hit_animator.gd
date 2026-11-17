class_name HitAnimator
extends RefCounted

const BODY = preload("res://assets/art/caretaker_hit_9_v015.png")
# Ground anchors measured on each unchanged generated cell. Sitting poses
# retain their smaller height instead of being stretched to standing height.
const PIVOTS := [Vector2(.50,.943),Vector2(.45,.943),Vector2(.50,.938),Vector2(.40,.852),Vector2(.39,.866),Vector2(.39,.864),Vector2(.39,.907),Vector2(.40,.883),Vector2(.50,.878)]
const HEADS := [Vector2(.50,.25),Vector2(.50,.26),Vector2(.50,.25),Vector2(.36,.34),Vector2(.39,.37),Vector2(.39,.37),Vector2(.39,.38),Vector2(.44,.35),Vector2(.50,.32)]

static func draw(canvas: Node2D, feet: Vector2, size: float, seconds: float, duration: float, facing: Vector2, reduced_motion: bool, alpha: float = 1.0) -> void:
	var frame := HitReaction.frame_at(seconds,duration,facing,reduced_motion)
	var flip := HitReaction.flip_for(facing,frame)
	var pose := Transform2D(0,Vector2(flip,1),0,feet)
	var ground := Vector2(-.10,.025) * size
	var origin := Vector2(.08,-.31) * size if frame == 1 else Vector2(-.18,-.30) * size
	var angle := .22
	if frame >= 3:
		origin = ground
		angle = .06
		if frame == 3 and not reduced_motion:
			var fall := clampf((seconds / duration * HitReaction.TOTAL_WEIGHT - 3.0) / 3.0,0,1)
			origin = (Vector2(.08,-.31) * size).lerp(ground,fall)
			angle = lerpf(.22,.06,fall)
	var rise := HitReaction.rise_fraction(seconds,duration)
	origin = origin.lerp(Vector2(-.16,-.55) * size,rise)
	angle = lerpf(angle,PI / 2,rise)
	# Reuse the existing rigid shovel geometry. Its entire shaft/blade rotates
	# together, resting beside the seated character before being picked up.
	var tool := pose * Transform2D(angle,origin)
	tool = tool.scaled_local(Vector2(lerpf(1,.75,rise),1))
	CaretakerAnimator.draw_tool(canvas,tool * ShovelRig.tool_transform(size,0).affine_inverse(),size,0,Color(1,1,1,alpha))
	var cell := BODY.get_size() / Vector2(3,3)
	var source := Rect2(Vector2(frame % 3,floori(frame / 3.0)) * cell,cell)
	canvas.draw_set_transform_matrix(pose)
	canvas.draw_texture_rect_region(BODY,Rect2(-PIVOTS[frame] * size,Vector2.ONE * size),source,Color(1,1,1,alpha))
	if frame in [4,5,6]:
		var head: Vector2 = (HEADS[frame] - PIVOTS[frame]) * size
		for i in 3:
			var orbit := i * TAU / 3 + (0.0 if reduced_motion else seconds * 3)
			var at := head + Vector2(cos(orbit) * size * .13,-size * .15 + sin(orbit) * size * .035)
			canvas.draw_circle(at,size * .015,Color(1,.86,.40,alpha))
	canvas.draw_set_transform(Vector2.ZERO)
