class_name DifficultyRules
extends RefCounted
## Presets are resolved once per run. Continue restores the saved rules.

const IDS := ["easy", "medium", "hard", "extreme"]
const PATH := "res://resources/difficulty/presets.json"
const ROUNDS := "res://resources/stages/rounds.json"
const ROUND_COUNT := 3
const LIMITS := {
	"extra_seconds": [0.0, 1800.0], "interval_multiplier": [.25, 5.0],
	"extra_warning": [0.0, 10.0], "target_bias": [0.0, 1.0],
	"deposit_multiplier": [0.0, 3.0], "recovery_multiplier": [.1, 2.0],
	"grace": [0.0, 10.0], "first_spawn": [.1, 60.0],
}

static func number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func catalog() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))

static func version_for(id: String, data: Dictionary = {}) -> String:
	var source := catalog() if data.is_empty() else data
	return source.get("preset_versions",{}).get(id,source.version)

static func valid_catalog(data: Variant) -> bool:
	if not data is Dictionary or not data.get("version") is String or data.version.is_empty() or data.version.length() > 64 or not data.get("presets") is Dictionary:
		return false
	var versions: Variant = data.get("preset_versions",{})
	if not versions is Dictionary: return false
	for id in versions:
		if id not in IDS or not versions[id] is String or versions[id].length() not in range(1,65): return false
	for id in IDS:
		if not valid_parameters(data.presets.get(id)): return false
	return true

static func valid_parameters(data: Variant) -> bool:
	if not data is Dictionary: return false
	if not data.get("landing_warnings",true) is bool: return false
	for key in LIMITS:
		if not number(data.get(key),LIMITS[key][0],LIMITS[key][1]): return false
	return true

static func custom_defaults() -> Dictionary:
	return catalog().presets.easy.duplicate()

static func valid_round_count(value: Variant) -> bool:
	return number(value,1,ROUND_COUNT) and float(value) == floorf(float(value))

static func valid_rounds(data: Variant) -> bool:
	if not data is Array or data.size() != ROUND_COUNT: return false
	var limits := {"seconds":[1,3600],"coverage":[0,1],"hazard_interval":[.1,10000],"warning":[.1,30],"flight":[.1,30],"deposition":[0,3],"reward":[0,100000]}
	for round_data in data:
		if not round_data is Dictionary: return false
		for key in limits:
			if not number(round_data.get(key), limits[key][0], limits[key][1]): return false
	return true

static func player_values(settings: GameSettings) -> Dictionary:
	return {"speed":settings.player_speed_multiplier,"idle":settings.idle_animation_multiplier,
		"scoop":settings.snow_per_scoop,"recovery":settings.hit_recovery_seconds}

static func valid_player(data: Variant) -> bool:
	return data is Dictionary and number(data.get("speed"),.25,3) and number(data.get("idle"),.25,3) and number(data.get("scoop"),1,765) and float(data.scoop) == floorf(float(data.scoop)) and number(data.get("recovery"),1,10)

static func player_settings(data: Dictionary) -> GameSettings:
	var result := GameSettings.new()
	result.player_speed_multiplier = data.speed
	result.idle_animation_multiplier = data.idle
	result.snow_per_scoop = int(data.scoop)
	result.hit_recovery_seconds = data.recovery
	return result

static func resolve(id: String, data: Dictionary, rounds: Array, player: Dictionary, parameters: Dictionary = {}) -> Dictionary:
	var preset: Dictionary = parameters if valid_parameters(parameters) else data.presets[id]
	var effective_rounds := rounds.duplicate(true)
	for stage in effective_rounds:
		stage.seconds += preset.extra_seconds
		stage.hazard_interval *= preset.interval_multiplier
		stage.warning += preset.extra_warning
		stage.deposition *= preset.deposit_multiplier
	var effective_player := player.duplicate()
	effective_player.recovery = clampf(float(player.recovery) * float(preset.recovery_multiplier), 1, 10)
	return {"difficulty":id,"version":version_for(id,data),"stages":effective_rounds,"player":effective_player,"landing_warnings":preset.get("landing_warnings",true),
		"target_bias":preset.target_bias,"grace":preset.grace,"first_spawn":preset.first_spawn}

static func valid_rules(data: Variant) -> bool:
	if not data is Dictionary or not data.get("landing_warnings",true) is bool: return false
	return data is Dictionary and data.get("difficulty") in IDS and data.get("version") is String and data.version.length() in range(1,65) and valid_rounds(data.get("stages")) and valid_player(data.get("player")) and number(data.get("target_bias"),0,1) and number(data.get("grace"),0,10) and number(data.get("first_spawn"),.1,60)

static func standard(id: String) -> Dictionary:
	return resolve(id, catalog(), JSON.parse_string(FileAccess.get_file_as_string(ROUNDS)), player_values(GameSettings.new()))

static func matches_standard(rules: Dictionary) -> bool:
	var expected := standard(rules.difficulty)
	# Idle animation is cosmetic and does not alter score eligibility.
	var actual := rules.duplicate(true)
	actual.player.idle = expected.player.idle
	return equivalent(actual,expected)

static func equivalent(first: Variant, second: Variant) -> bool:
	# JSON decimal round trips may lose a last binary digit. Do not reclassify
	# a normal continued game as custom because of that serialization noise.
	if (first is float or first is int) and (second is float or second is int):
		return absf(float(first)-float(second)) <= .000001
	if first is Dictionary and second is Dictionary:
		if first.size() != second.size(): return false
		for key in first:
			if not second.has(key) or not equivalent(first[key],second[key]): return false
		return true
	if first is Array and second is Array:
		if first.size() != second.size(): return false
		for i in first.size():
			if not equivalent(first[i],second[i]): return false
		return true
	return first == second
