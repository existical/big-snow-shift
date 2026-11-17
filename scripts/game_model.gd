class_name GameModel
extends RefCounted

signal hit
signal snow_cleared(amount: int)
signal round_completed(final_round: bool)
signal round_failed
signal ice_landed(point: Vector2)
signal stairs_cleared
signal ending_started
signal tree_revealed
signal timeout_started
signal santa_slipped
signal santa_landed

const STAGES: String = "res://resources/stages/rounds.json"
const SIDE_SNOW_SPEED := 42.0 # Base world pixels/player-second, scaled by GameSettings.
const SIDE_WALK_SPEED := 110.0
const VERTICAL_SNOW_SPEED := 18.0
const VERTICAL_WALK_SPEED := 75.0
var stages: Array = []
var settings: GameSettings
var snow := SnowField.new()
var rng := RandomNumberGenerator.new()
var stage_index := 0
var round_count := DifficultyRules.ROUND_COUNT
var state := "playing"
var paused := false
var player := Vector2(0.5, 0.93)
var facing := Vector2.RIGHT
var moving := false
var time_left := 120.0
var elapsed := 0.0
var stun := 0.0
var hit_duration := GameSettings.DEFAULT_HIT_RECOVERY
var immunity := 0.0
var score := 0
var round_hits := 0
var total_hits := 0
var last_reward := 0
var spawn_countdown := 2.5
var hazards: Array[Dictionary] = []
var run_id := ""
var clear_fraction := 0.0
var shovel_time := 0.0
var shoveling := false
var last_cut_point := Vector2.ZERO
var ending_time := 0.0
var ending_start_player := Vector2.ZERO
var failure_time := 0.0
var difficulty_id := "hard"
var game_mode := "standard"
var custom_parameters: Dictionary = {}
var balance_version := ""
var difficulty_config: Dictionary = {}
var base_stages: Array = []
var development_player: Dictionary = {}
var target_bias := .65
var grace_seconds := 1.8
var first_spawn := 2.5
var landing_warnings := true
var time_allowance := 0.0
var assists := {"no_time_limit":false,"no_icicles":false}
var adjusted_run := false
var legacy_run := false
var failed_attempts := 0

func rules_snapshot() -> Dictionary:
	return {"difficulty":difficulty_id,"version":balance_version,"stages":stages.duplicate(true),
		"player":DifficultyRules.player_values(settings),"target_bias":target_bias,"grace":grace_seconds,"first_spawn":first_spawn,"landing_warnings":landing_warnings}

# Rules are installed only by start() or restore(); retries reuse this snapshot.
func _apply_rules(rules: Dictionary) -> void:
	difficulty_id = rules.difficulty
	balance_version = rules.version
	stages = rules.stages.duplicate(true)
	settings = DifficultyRules.player_settings(rules.player)
	target_bias = rules.target_bias
	grace_seconds = rules.grace
	first_spawn = rules.first_spawn
	landing_warnings = rules.get("landing_warnings",true)

func score_category() -> String:
	if game_mode == "custom" or round_count != DifficultyRules.ROUND_COUNT or adjusted_run or assists.no_time_limit or assists.no_icicles: return "personal"
	if legacy_run or balance_version != DifficultyRules.version_for(difficulty_id): return "previous"
	if not DifficultyRules.matches_standard(rules_snapshot()): return "personal"
	return "standard"

static func valid_assists(value: Variant) -> bool:
	return value is Dictionary and value.get("no_time_limit") is bool and value.get("no_icicles") is bool

func identify_development_rules() -> void:
	# Editable developer tuning remains available, with an honest Custom label.
	if balance_version == DifficultyRules.version_for(difficulty_id) and not DifficultyRules.matches_standard(rules_snapshot()):
		game_mode = "custom"
	if game_mode == "custom" and custom_parameters.is_empty():
		custom_parameters = difficulty_config.presets[difficulty_id].duplicate()

static func saved_mode(data: Dictionary) -> String:
	# Pre-0.25 assisted saves keep their exact mechanics when migrated.
	var options: Variant = data.get("assists",{})
	if valid_assists(options) and (options.no_time_limit or options.no_icicles): return "custom"
	return "custom" if data.get("game_mode") == "custom" else "standard"

func is_active() -> bool:
	return state in ["playing", "returning", "greeting", "timeout"]

func controls_locked() -> bool:
	return state in ["greeting", "timeout"]

func is_timeout_scene() -> bool:
	return state == "timeout" or (state == "lost" and failure_time > 0)

func pose_frame() -> int:
	var animation_speed := settings.idle_animation_multiplier if not moving or stun > 0 else settings.player_speed_multiplier
	return ShovelRig.frame_for(facing, moving, shoveling, elapsed * animation_speed, stun > 0, shovel_time)

func probe_frame() -> int:
	return 19 if facing.y < -.55 else (27 if facing.y > .55 else 12)

func snow_at_blade() -> bool:
	return scoop_amount(player, facing) > 0

static func horizontal_contact(feet: Vector2, direction: Vector2) -> Vector2:
	var contact := ShovelRig.contact_world(feet, direction.normalized(), 12)
	contact.y = StairSurface.project(Vector2(feet.x, StairSurface.tread_center(StairSurface.tread_at(feet.y)))).y
	return contact

static func vertical_contact(feet: Vector2, direction: Vector2) -> Vector2:
	# Stable digging pose, rather than tracing the lifted blade through the snow.
	var contact := ShovelRig.contact_uv(feet, direction.normalized(), 19 if direction.y < 0 else 27)
	contact.x = feet.x # Both vertical poses work beneath the same body corridor.
	return contact

static func vertical_radius(feet: Vector2, center: Vector2) -> Vector2:
	var radius := ShovelRig.brush_radius(feet, center)
	radius.x *= .26 / .17 # A front-facing scoop spans the character's footprint.
	return radius

func scoop_amount(feet: Vector2, direction: Vector2, clear: bool = false) -> int:
	if direction.x != 0:
		var center := horizontal_contact(feet, direction)
		var half_width := ShovelRig.size_at(feet) * .17
		return snow.tread_strip(StairSurface.tread_at(feet.y), center.x - half_width, center.x + half_width, clear, settings.snow_per_scoop)
	var center := vertical_contact(feet, direction)
	var radius := vertical_radius(feet, center)
	return snow.box(Rect2(center - radius, radius * 2), clear, settings.snow_per_scoop)

func movement_blocked(start: Vector2, finish: Vector2, direction: Vector2) -> bool:
	# The BACK of the scoop may only advance across cleared cells. The blade's
	# front can slide under the next chunk; it cannot leave an uncut gap behind.
	if direction.x != 0:
		var half_width := ShovelRig.size_at(start) * .17 - 1.0
		var first := horizontal_contact(start, direction).x - direction.x * half_width
		var last := horizontal_contact(finish, direction).x - direction.x * half_width
		return snow.tread_strip(StairSurface.tread_at(start.y), minf(first, last) - .01, maxf(first, last) + .01) > 0
	var first := vertical_contact(start, direction)
	var last := vertical_contact(finish, direction)
	var first_radius := vertical_radius(start, first)
	var last_radius := vertical_radius(finish, last)
	var inset := 1.0 / (StairSurface.BOTTOM - StairSurface.TOP)
	first.y -= direction.y * (first_radius.y - inset)
	last.y -= direction.y * (last_radius.y - inset)
	# A central corridor leaves room for the scoop's rounded rendered corners
	# and perspective changes while keeping the travelled lane free of islands.
	var half_width := minf(first_radius.x, last_radius.x) * .65
	var low := first.min(last) - Vector2(half_width, .00001)
	var high := first.max(last) + Vector2(half_width, .00001)
	return snow.box(Rect2(low, high - low)) > 0

static func movement_target(feet: Vector2, direction: Vector2, seconds: float, speed: float) -> Vector2:
	if direction.x != 0:
		var world := StairSurface.project(feet) + Vector2(direction.x * speed * seconds, 0)
		var target := StairSurface.constrain(StairSurface.unproject(world))
		target.y = feet.y # Preserve the exact tread level, including float rounding.
		return target
	return StairSurface.constrain(feet + Vector2(0, direction.y * speed * seconds / (StairSurface.BOTTOM - StairSurface.TOP)))

func move_on_cleared_snow(seconds: float, direction: Vector2, speed: float) -> void:
	var target := movement_target(player, direction, seconds, speed)
	var unit := direction.normalized()
	if not movement_blocked(player, target, unit):
		player = target
	elif not movement_blocked(player, player, unit):
		# Stop at the snow boundary, instead of rejecting a whole coarse tick.
		var low := 0.0
		var high := 1.0
		for iteration in 10:
			var middle := (low + high) * .5
			if movement_blocked(player, player.lerp(target, middle), unit):
				high = middle
			else:
				low = middle
		player = player.lerp(target, low)

func step_shoveling(delta: float, direction: Vector2) -> void:
	var walk_speed := SIDE_WALK_SPEED if facing.x != 0 else VERTICAL_WALK_SPEED
	var work_speed := SIDE_SNOW_SPEED if facing.x != 0 else VERTICAL_SNOW_SPEED
	var left := delta
	while left > .0000001:
		if not shoveling:
			var target := movement_target(player, direction, left, walk_speed)
			if not snow_at_blade() and not movement_blocked(player, target, facing):
				move_on_cleared_snow(left, direction, walk_speed)
				return
			shoveling = true
			shovel_time = 0.0
		var impact := ShovelStroke.impact_time(facing)
		var before_impact := shovel_time < impact - .0000001
		var boundary := impact if before_impact else ShovelStroke.DURATION
		var slice := minf(left, boundary - shovel_time)
		var travel_speed := work_speed
		var walk_target := movement_target(player, direction, slice, walk_speed)
		var lookahead := 8.0 if facing.x != 0 else 6.0
		var probe := movement_target(player, direction, maxf(slice, lookahead / (walk_speed * direction.length())), walk_speed)
		if not snow_at_blade() and scoop_amount(probe, facing) == 0 and not movement_blocked(player, walk_target, facing):
			# Finish the lift visually, but do not keep walking slowly after a
			# small deposit has already been removed from an otherwise bare lane.
			travel_speed = walk_speed
		move_on_cleared_snow(slice, direction, travel_speed)
		shovel_time += slice
		left -= slice
		if shovel_time >= boundary - .0000001:
			shovel_time = boundary
			if before_impact:
				var removed := scoop_amount(player, facing, true)
				if removed > 0:
					last_cut_point = horizontal_contact(player, facing) if facing.x != 0 else StairSurface.project(vertical_contact(player, facing))
					snow_cleared.emit(removed)
			else:
				shovel_time = 0.0
				shoveling = snow_at_blade()

func _init(tuning: GameSettings = null) -> void:
	settings = tuning if tuning != null else GameSettings.new()
	stages = JSON.parse_string(FileAccess.get_file_as_string(STAGES))
	base_stages = stages.duplicate(true)
	development_player = DifficultyRules.player_values(settings)
	difficulty_config = DifficultyRules.catalog()
	balance_version = difficulty_config.version

func start(seed_value: int = 0, difficulty: String = "hard", selected_assists: Dictionary = {"no_time_limit":false,"no_icicles":false}, mode: String = "standard", parameters: Dictionary = {}, selected_round_count: int = DifficultyRules.ROUND_COUNT) -> void:
	if run_id.is_empty():
		development_player = DifficultyRules.player_values(settings)
		base_stages = stages.duplicate(true)
	game_mode = "custom" if mode == "custom" else "standard"
	round_count = selected_round_count if game_mode == "custom" and DifficultyRules.valid_round_count(selected_round_count) else DifficultyRules.ROUND_COUNT
	var id := difficulty if difficulty in DifficultyRules.IDS else "easy"
	custom_parameters = (parameters if DifficultyRules.valid_parameters(parameters) else difficulty_config.presets[id]).duplicate() if game_mode == "custom" else {}
	_apply_rules(DifficultyRules.resolve(id,difficulty_config,base_stages,development_player,custom_parameters))
	assists = selected_assists.duplicate() if game_mode == "custom" and valid_assists(selected_assists) else {"no_time_limit":false,"no_icicles":false}
	identify_development_rules()
	adjusted_run = false
	legacy_run = false
	failed_attempts = 0
	rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system() * 1000)
	run_id = "%d-%d" % [int(Time.get_unix_time_from_system() * 1000), rng.randi()]
	score = 0
	total_hits = 0
	begin_round(0)

func begin_round(index: int) -> void:
	stage_index = clampi(index, 0, round_count - 1)
	state = "playing"
	paused = false
	player = Vector2(0.5, 0.93)
	facing = Vector2.RIGHT
	moving = false
	time_left = float(stage().seconds)
	time_allowance = time_left
	elapsed = 0.0
	stun = 0.0
	hit_duration = settings.hit_recovery_seconds
	immunity = 0.0
	round_hits = 0
	spawn_countdown = first_spawn
	clear_fraction = 0.0
	shovel_time = 0.0
	shoveling = false
	ending_time = 0.0
	ending_start_player = player
	failure_time = 0.0
	hazards.clear()
	snow.generate(float(stage().coverage), rng)

func stage() -> Dictionary:
	return stages[stage_index]

func ending_index() -> int:
	return RoundEnding.index_for(stage_index,round_count)

func next_round() -> void:
	if state == "celebrating" and stage_index < round_count - 1:
		begin_round(stage_index + 1)

func step(delta: float, direction: Vector2) -> void:
	if not is_active() or paused:
		moving = false
		return
	delta = clampf(delta, 0.0, 0.1)
	if delta <= 0.0:
		return
	if state == "timeout":
		step_timeout(delta)
		return
	if state == "greeting":
		step_ending(delta)
		return
	var movement_delta := maxf(0,delta - stun)
	stun = maxf(0.0, stun - delta)
	if stun < .0000001:
		stun = 0.0
	immunity = maxf(0.0, immunity - delta)
	moving = direction.length() > 0.1 and movement_delta > .0000001
	if moving:
		direction = direction.limit_length(1.0)
		# Original inputs select one direction. In particular, a slightly diagonal
		# thumbstick must not drift sideways work into another stair row.
		var strength := direction.length()
		direction = (Vector2(0, signf(direction.y)) if absf(direction.normalized().y) > .55 else Vector2(signf(direction.x), 0)) * strength
		var next_facing := direction.normalized()
		if next_facing != facing:
			shoveling = false
			shovel_time = 0.0
		facing = next_facing
		# Movement and stroke phase use the same player-time scale, preserving
		# scoop overlap. Round time, hazards, stun and immunity stay in real time.
		if state == "returning":
			var speed := SIDE_WALK_SPEED if facing.x != 0 else VERTICAL_WALK_SPEED
			player = movement_target(player, direction, movement_delta * settings.player_speed_multiplier, speed)
		else:
			step_shoveling(movement_delta * settings.player_speed_multiplier, direction)
	else:
		shoveling = false
		shovel_time = 0.0
	if state == "returning":
		elapsed += delta
		if player.y <= .07 and absf(player.x - .5) <= .23:
			state = "greeting"
			ending_time = 0.0
			ending_start_player = player
			moving = false
			ending_started.emit()
	else:
		step_round(delta)

func step_round(delta: float) -> void:
	# Clearing the final patch wins this tick before an impact or the deadline.
	# Sweep away sub-pixel residue rather than making children hunt invisible dots.
	if snow.remaining <= int(snow.initial * 0.001) and not snow.has_visible_piles():
		if snow.remaining > 0:
			snow.brush(Vector2(.5,.5), Vector2.ONE * 2, 255)
		prepare_finish()
		return
	elapsed += delta
	if not assists.no_time_limit:
		time_left = maxf(0.0, time_left - delta)
	if not assists.no_icicles: spawn_countdown -= delta
	if spawn_countdown <= 0.0 and not assists.no_icicles:
		spawn_hazard()
		spawn_countdown = float(stage().hazard_interval) * rng.randf_range(0.8, 1.2)
	for i in range(hazards.size() - 1, -1, -1):
		var hazard: Dictionary = hazards[i]
		hazard.age += delta
		if float(hazard.age) >= float(hazard.warning) + float(hazard.flight):
			var point := Vector2(hazard.x, hazard.y)
			var distance := (player - point) / Vector2(0.085, 0.105)
			if distance.length_squared() < 1.0:
				# The character intercepts the icicle even during immunity. A body
				# hit must never also deposit snow or play the stair-impact burst.
				if immunity <= 0.0:
					apply_hit()
			else:
				snow.add_pile(point, int(float(hazard.get("deposition",stage().deposition)) * 255), point.x * 31.0 + point.y * 17.0)
				ice_landed.emit(point)
			hazards.remove_at(i)
	if time_left <= 0.0 and not assists.no_time_limit:
		begin_timeout()

func begin_timeout() -> void:
	if state != "playing":
		return
	state = "timeout"
	failed_attempts += 1
	time_left = 0.0
	failure_time = 0.0
	moving = false
	shoveling = false
	shovel_time = 0.0
	stun = 0.0
	immunity = 0.0
	last_reward = 0
	hazards.clear()
	timeout_started.emit()

func step_timeout(delta: float) -> void:
	var previous := failure_time
	failure_time = minf(failure_time + delta, RoundTimeout.DURATION)
	elapsed += delta
	if previous < RoundTimeout.SLIP_TIME and failure_time >= RoundTimeout.SLIP_TIME:
		santa_slipped.emit()
	if previous < RoundTimeout.LAND_TIME and failure_time >= RoundTimeout.LAND_TIME:
		santa_landed.emit()
	if failure_time >= RoundTimeout.DURATION - .0000001:
		failure_time = RoundTimeout.DURATION
		state = "lost"
		round_failed.emit()

func spawn_hazard() -> void:
	if assists.no_icicles: return
	var target := Vector2(rng.randf_range(0.06, 0.94), rng.randf_range(0.1, 0.95))
	if rng.randf() < target_bias:
		target = (player + Vector2(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.12, 0.12))).clamp(Vector2(0.05, 0.08), Vector2(0.95, 0.96))
	hazards.append({"x": target.x, "y": target.y, "age": 0.0, "warning": float(stage().warning), "flight": float(stage().flight),"deposition":float(stage().deposition)})

func apply_hit() -> void:
	if state != "playing" or paused or immunity > 0:
		return
	hit_duration = settings.hit_recovery_seconds
	stun = hit_duration
	immunity = hit_duration + grace_seconds
	moving = false
	shoveling = false
	shovel_time = 0.0
	round_hits += 1
	total_hits += 1
	# Recovery already costs real countdown time; impact adds no time deduction.
	hit.emit()

func prepare_finish() -> void:
	if state != "playing":
		return
	# Secure the cleared round immediately. No falling icicle can add new work
	# or hit the player on the way to the door; the remaining-time reward freezes.
	state = "returning"
	hazards.clear()
	stun = 0.0
	immunity = 0.0
	moving = false
	shoveling = false
	shovel_time = 0.0
	stairs_cleared.emit()

func step_ending(delta: float) -> void:
	var previous := ending_time
	var ending := ending_index()
	ending_time = minf(ending_time + delta, RoundEnding.duration(ending))
	elapsed += delta
	player = ending_start_player.lerp(RoundEnding.DOOR_TARGET, smoothstep(0, RoundEnding.ALIGN_TIME, ending_time))
	facing = Vector2.RIGHT
	moving = ending_time < RoundEnding.ALIGN_TIME
	if ending == 2 and previous < RoundEnding.MAGIC_TIME and ending_time >= RoundEnding.MAGIC_TIME:
		tree_revealed.emit()
	if ending_time >= RoundEnding.duration(ending):
		finish_round()

func finish_round() -> void:
	if state != "greeting":
		return
	last_reward = int(stage().reward) + (0 if assists.no_time_limit else int(ceil(time_left)) * 10) + (300 if round_hits == 0 else 0)
	score += last_reward
	state = "won" if stage_index == round_count - 1 else "celebrating"
	hazards.clear()
	moving = false
	round_completed.emit(state == "won")

func snapshot() -> Dictionary:
	return {"game_mode":game_mode,"round_count":round_count,"custom_parameters":custom_parameters.duplicate(),"rules":rules_snapshot(),"rule_catalog":difficulty_config.duplicate(true),"base_stages":base_stages.duplicate(true),
		"development_player":development_player.duplicate(),"time_allowance":time_allowance,"assists":assists.duplicate(),
		"adjusted_run":adjusted_run,"legacy_run":legacy_run,"failed_attempts":failed_attempts,
		"stage": stage_index, "state": state, "player": [player.x, player.y], "facing": [facing.x, facing.y],
		"time": time_left, "elapsed": elapsed, "stun": stun, "hit_duration":hit_duration, "immunity": immunity, "score": score,
		"round_hits": round_hits, "total_hits": total_hits, "last_reward": last_reward, "countdown": spawn_countdown,
		"hazards": hazards.duplicate(true), "rng": str(rng.state), "seed": str(rng.seed), "id": run_id, "snow": snow.snapshot(), "clear_fraction": clear_fraction,
		"shovel_time": shovel_time, "shoveling": shoveling,
		"ending_time":ending_time, "ending_start_player":[ending_start_player.x, ending_start_player.y], "failure_time":failure_time}

func restore(data: Dictionary) -> bool:
	var old_run := not data.has("rules")
	var saved_catalog: Variant = data.get("rule_catalog",DifficultyRules.catalog())
	var saved_base: Variant = data.get("base_stages",base_stages)
	var saved_player: Variant = data.get("development_player",development_player)
	if not DifficultyRules.valid_catalog(saved_catalog) or not DifficultyRules.valid_rounds(saved_base) or not DifficultyRules.valid_player(saved_player): return false
	var saved_rules: Variant = data.get("rules",DifficultyRules.resolve("hard",saved_catalog,saved_base,saved_player))
	var saved_assists: Variant = data.get("assists",{"no_time_limit":false,"no_icicles":false})
	if not DifficultyRules.valid_rules(saved_rules) or not valid_assists(saved_assists): return false
	if data.has("game_mode") and data.game_mode not in ["standard","custom"]: return false
	if data.get("game_mode") == "standard" and (saved_assists.no_time_limit or saved_assists.no_icicles): return false
	var saved_count: Variant = data.get("round_count",DifficultyRules.ROUND_COUNT)
	if not DifficultyRules.valid_round_count(saved_count): return false
	if saved_mode(data) != "custom" and int(saved_count) != DifficultyRules.ROUND_COUNT: return false
	var saved_parameters: Variant = data.get("custom_parameters",{})
	if not saved_parameters is Dictionary or (not saved_parameters.is_empty() and not DifficultyRules.valid_parameters(saved_parameters)): return false
	for key in ["adjusted_run","legacy_run"]:
		if data.has(key) and not data[key] is bool: return false
	if data.has("failed_attempts") and not DifficultyRules.number(data.failed_attempts,0,100000): return false
	if data.has("time_allowance") and not DifficultyRules.number(data.time_allowance,1,3600): return false
	if not data.get("stage") is float and not data.get("stage") is int:
		return false
	if not DifficultyRules.number(data.stage,0,int(saved_count)-1) or float(data.stage) != floorf(float(data.stage)) or data.get("state", "") not in ["playing", "returning", "greeting", "timeout", "celebrating", "won", "lost"]:
		return false
	if data.state == "celebrating" and int(data.stage) == int(saved_count)-1: return false
	for key in ["player", "facing"]:
		if not data.get(key) is Array or data[key].size() != 2:
			return false
		for number in data[key]:
			if (not number is float and not number is int) or not is_finite(float(number)):
				return false
	for key in ["time", "elapsed", "stun", "immunity", "score", "round_hits", "total_hits", "last_reward", "countdown"]:
		if not data.get(key) is float and not data.get(key) is int:
			return false
		if not is_finite(float(data[key])):
			return false
	var saved_snow := SnowField.new()
	if not data.get("snow") is Dictionary or not saved_snow.restore(data.snow):
		return false
	var round_rules: Dictionary = saved_rules.stages[int(data.stage)]
	var lifetime := float(round_rules.warning) + float(round_rules.flight)
	var max_hazards := maxi(12, ceili(lifetime / (float(round_rules.hazard_interval) * .8)) + 1)
	if not data.get("hazards") is Array or data.hazards.size() > max_hazards:
		return false
	var restored_hazards: Array[Dictionary] = []
	for hazard in data.hazards:
		if not hazard is Dictionary:
			return false
		for key in ["x", "y", "age", "warning", "flight"]:
			if (not hazard.get(key) is float and not hazard.get(key) is int) or not is_finite(float(hazard[key])):
				return false
		if hazard.x < 0 or hazard.x > 1 or hazard.y < 0 or hazard.y > 1 or hazard.warning < 0.1 or hazard.flight < 0.1:
			return false
		if hazard.has("deposition") and not DifficultyRules.number(hazard.deposition,0,3): return false
		if not hazard.has("deposition"): hazard = hazard.merged({"deposition":float(saved_rules.stages[int(data.stage)].deposition)})
		restored_hazards.append(hazard.duplicate())
	if not data.get("id") is String or not data.get("rng") is String or not data.get("seed") is String:
		return false
	var saved_ending: Variant = data.get("ending_time", 0.0)
	if (not saved_ending is float and not saved_ending is int) or not is_finite(float(saved_ending)) or float(saved_ending) < 0 or float(saved_ending) > RoundEnding.duration(RoundEnding.index_for(int(data.stage),int(saved_count))):
		return false
	var saved_start: Variant = data.get("ending_start_player", data.player)
	if not saved_start is Array or saved_start.size() != 2:
		return false
	for value in saved_start:
		if (not value is float and not value is int) or not is_finite(float(value)):
			return false
	if data.state in ["returning", "greeting"] and saved_snow.remaining != 0:
		return false
	var saved_failure: Variant = data.get("failure_time", 0.0)
	if (not saved_failure is float and not saved_failure is int) or not is_finite(float(saved_failure)) or float(saved_failure) < 0 or float(saved_failure) > RoundTimeout.DURATION:
		return false
	if data.state == "timeout" and float(data.time) != 0:
		return false
	# Old snapshots used a one-second stun and have no reaction duration.
	var saved_hit: Variant = data.get("hit_duration",1.0)
	if (not saved_hit is float and not saved_hit is int) or not is_finite(float(saved_hit)) or float(saved_hit) < GameSettings.MIN_HIT_RECOVERY or float(saved_hit) > GameSettings.MAX_HIT_RECOVERY:
		return false
	snow = saved_snow
	difficulty_config = saved_catalog.duplicate(true)
	base_stages = saved_base.duplicate(true)
	development_player = saved_player.duplicate()
	_apply_rules(saved_rules)
	game_mode = saved_mode(data)
	round_count = int(saved_count)
	custom_parameters = (saved_parameters if not saved_parameters.is_empty() else saved_catalog.presets[difficulty_id]).duplicate() if game_mode == "custom" else {}
	if not old_run: identify_development_rules()
	assists = saved_assists.duplicate()
	adjusted_run = data.get("adjusted_run",false)
	legacy_run = old_run or data.get("legacy_run",false)
	failed_attempts = int(data.get("failed_attempts",0))
	stage_index = int(data.stage)
	state = data.state
	player = StairSurface.constrain(Vector2(data.player[0], data.player[1]))
	facing = Vector2(data.facing[0], data.facing[1]).limit_length(1.0)
	time_allowance = maxf(float(stage().seconds),float(data.get("time_allowance",stage().seconds)))
	time_left = clampf(float(data.time), 0.0, time_allowance)
	elapsed = maxf(0.0, float(data.elapsed))
	hit_duration = float(saved_hit)
	stun = clampf(float(data.stun), 0.0, hit_duration)
	# A recovery already in progress retains protection from its previous mode.
	immunity = clampf(float(data.immunity), stun, hit_duration + 10.0)
	score = clampi(int(data.score), 0, 9999999)
	round_hits = maxi(0, int(data.round_hits))
	total_hits = maxi(0, int(data.total_hits))
	last_reward = maxi(0, int(data.last_reward))
	spawn_countdown = clampf(float(data.countdown), 0.0, 10000.0)
	hazards = restored_hazards
	if assists.no_icicles: hazards.clear()
	rng.seed = int(data.seed)
	rng.state = int(data.rng)
	run_id = data.id
	clear_fraction = clampf(float(data.get("clear_fraction", 0.0)), 0.0, 1.0)
	shovel_time = clampf(float(data.get("shovel_time", 0.0)), 0.0, ShovelStroke.DURATION)
	shoveling = bool(data.get("shoveling", false))
	ending_time = float(saved_ending)
	ending_start_player = StairSurface.constrain(Vector2(saved_start[0], saved_start[1]))
	failure_time = float(saved_failure)
	if state in ["returning", "greeting", "timeout"]:
		hazards.clear()
		stun = 0.0
		immunity = 0.0
		shoveling = false
	paused = true
	moving = false
	return true
