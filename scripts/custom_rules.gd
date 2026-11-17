class_name CustomRules
extends RefCounted
## Presentation and bounded adjustments for the eight editable preset parameters.
const FIELDS := [
	["extra_seconds","custom.extraTime",30.0],
	["interval_multiplier","custom.icicleGap",.1],
	["extra_warning","custom.warning",.5],
	["deposit_multiplier","custom.snowAmount",.25],
	["target_bias","custom.targeting",.05],
	["first_spawn","custom.firstIcicle",.5],
	["recovery_multiplier","custom.recovery",.5],
	["grace","custom.protection",.5],
]

static func adjusted(parameters: Dictionary, key: String, direction: int, player: Dictionary) -> float:
	var value := float(parameters[key])
	if key == "recovery_multiplier":
		# Display and change the effective sitting time, avoiding invisible steps
		# in the model's clamped duration (including imported developer tuning).
		var seconds := clampf(value * float(player.recovery),1,10)
		var next := clampf(seconds+direction*.5,1,10)
		if is_equal_approx(seconds,next): return value
		return clampf(next/float(player.recovery),DifficultyRules.LIMITS[key][0],DifficultyRules.LIMITS[key][1])
	for field in FIELDS:
		if field[0] == key:
			return clampf(snappedf(value+direction*float(field[2]),.000001),DifficultyRules.LIMITS[key][0],DifficultyRules.LIMITS[key][1])
	return value

static func value(parameters: Dictionary, key: String, rounds: Array, player: Dictionary, language: GameLocalization) -> String:
	var number := float(parameters[key])
	if key == "extra_seconds":
		var seconds := int(round(number))
		return "+%d:%02d" % [seconds/60,seconds%60]
	if key in ["target_bias","deposit_multiplier"]: return "%d%%" % roundi(number*100)
	if key == "interval_multiplier": number *= float(rounds[0].hazard_interval)
	elif key == "extra_warning": number += float(rounds[0].warning)
	elif key == "recovery_multiplier": number = clampf(number * float(player.recovery),1,10)
	var display := str(roundi(number)) if is_equal_approx(number,roundf(number)) else "%.1f" % number
	return language.text("custom.seconds",{"value":display})
