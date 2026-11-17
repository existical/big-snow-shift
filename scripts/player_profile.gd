class_name PlayerProfile
extends RefCounted

const PATH := "user://profile.json"
const VERSION := 5
var path := PATH
var settings := {"music": 0.35, "effects": 0.7, "control_mode": "screen", "language": "system", "difficulty":"easy", "game_mode":"standard", "custom_round_count":DifficultyRules.ROUND_COUNT, "custom_parameters":DifficultyRules.custom_defaults(), "custom_assists":{"no_time_limit":false,"no_icicles":false}}
var scores: Array = []
var active_run: Dictionary = {}
var submitted: Array = []
var pending_results: Array[Dictionary] = []
var preserve_backup := false
var player_name := "Caretaker"
var storage_ok := true
var badges: Array = []
var last_submitted_id := ""
var last_was_best := false
var _worker: Thread
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _finished := Semaphore.new()
var _pending: Dictionary = {}
var _stop := false
var _closed := false
var _requested := 0
var _completed := 0
var _completed_ok := true
var _last_payload: Dictionary = {}
var _last_path := ""
var _writes := 0

func load_profile() -> void:
	for candidate in [path, path + ".bak"]:
		var data := read_document(candidate)
		if data.is_empty(): continue
		preserve_backup = candidate != path
		if data.get("settings") is Dictionary:
			var saved_count: Variant = data.settings.get("custom_round_count",DifficultyRules.ROUND_COUNT)
			settings.custom_round_count = int(saved_count) if DifficultyRules.valid_round_count(saved_count) else DifficultyRules.ROUND_COUNT
			settings.windows_display = WindowsDisplay.clean(data.settings.get("windows_display"))
			for key in ["music", "effects"]:
				var value = data.settings.get(key)
				if (value is float or value is int) and is_finite(float(value)):
					settings[key] = clampf(float(value), 0, 1)
			# Older profiles have only a pad-visibility flag. Adopt the new
			# default without changing their run, scores or other preferences.
			var mode: Variant = data.settings.get("control_mode")
			settings.control_mode = mode if mode is String and mode in ["screen", "pad"] else "screen"
			var language: Variant = data.settings.get("language")
			if language is String:
				settings.language = language
			if data.settings.get("difficulty") in DifficultyRules.IDS:
				settings.difficulty = data.settings.difficulty
			if int(data.version) < 3:
				settings.custom_parameters = DifficultyRules.catalog().presets[settings.difficulty].duplicate()
				settings.custom_parameters.landing_warnings = true # Pre-toggle preferences always displayed markers.
				if GameModel.valid_assists(data.settings.get("assists")):
					settings.custom_assists = data.settings.assists.duplicate()
					if settings.custom_assists.no_time_limit or settings.custom_assists.no_icicles: settings.game_mode = "custom"
			else:
				if data.settings.get("game_mode") in ["standard","custom"]: settings.game_mode = data.settings.game_mode
				if int(data.version) == 3 and data.settings.get("custom_difficulty") in DifficultyRules.IDS:
					settings.custom_parameters = DifficultyRules.catalog().presets[data.settings.custom_difficulty].duplicate()
					settings.custom_parameters.landing_warnings = true
				elif DifficultyRules.valid_parameters(data.settings.get("custom_parameters")):
					settings.custom_parameters = data.settings.custom_parameters.duplicate()
				if GameModel.valid_assists(data.settings.get("custom_assists")): settings.custom_assists = data.settings.custom_assists.duplicate()
		scores.clear()
		if data.get("scores") is Array:
			for entry in data.scores:
				var cleaned := clean_score(entry, int(data.version) == 1)
				if not cleaned.is_empty(): scores.append(cleaned)
			trim_scores()
		badges.clear()
		if data.get("badges") is Array:
			for id in ["hard","extreme"]:
				if id in data.badges: badges.append(id)
		if data.get("run") is Dictionary:
			active_run = {} if data.run.get("state","") in ["won","lost"] else data.run
		if data.get("submitted") is Array:
			submitted = data.submitted.slice(-30)
		pending_results.clear()
		if data.get("pending_results") is Array:
			var seen := {}
			for result in data.pending_results:
				var entry := clean_score(result)
				if entry.is_empty() or entry.id.is_empty() or entry.id in submitted or entry.category == "previous": continue
				if not seen.has(entry.id):
					seen[entry.id] = true
					pending_results.append(entry)
		if data.get("name") is String:
			player_name = clean_name(data.name)
		return

static func read_document(candidate: String) -> Dictionary:
	if not FileAccess.file_exists(candidate): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(candidate)) != OK: return {}
	var data: Variant = parser.data
	if not data is Dictionary or not DifficultyRules.number(data.get("version"),1,VERSION) or float(data.version) != floorf(float(data.version)): return {}
	return data

func restore_active(model: GameModel) -> bool:
	if active_run.is_empty() or active_run.get("id","") in submitted: return false
	if model.restore(active_run): return true
	var backup: Variant = read_document(path + ".bak").get("run")
	if not backup is Dictionary or not backup.get("id") is String or backup.id.is_empty() or backup.get("id") != active_run.get("id"): return false
	if backup.get("state") in ["won","lost"] or not model.restore(backup): return false
	active_run = backup
	preserve_backup = true
	return true

func document() -> Dictionary:
	# Ended games must never be offered by Continue, including older saves.
	if active_run.get("state","") in ["won","lost"]: active_run = {}
	# Discard this retired option even if an older in-memory profile retains it.
	settings.erase("reduced_motion")
	settings.erase("assists")
	settings.erase("custom_difficulty")
	return {"version":VERSION,"settings":settings,"scores":scores,"run":active_run,
		"pending_results":pending_results,"submitted":submitted,"name":player_name,"badges":badges}.duplicate(true)

static func clean_score(entry: Variant, legacy: bool = false) -> Dictionary:
	if not entry is Dictionary or not entry.get("name") is String or not DifficultyRules.number(entry.get("score"),0,9999999): return {}
	var id: String = entry.get("difficulty", "") if entry.get("difficulty", "") is String else ""
	var category: String = entry.get("category","previous") if entry.get("category","previous") is String else "previous"
	if legacy or id not in DifficultyRules.IDS or category not in ["standard","personal","previous"]: category = "previous"
	var version: String = entry.get("balance","legacy") if entry.get("balance","legacy") is String else "legacy"
	var date: String = entry.get("date","") if entry.get("date","") is String else ""
	var run_id: String = entry.get("id","") if entry.get("id","") is String else ""
	var mode: String = "custom" if entry.get("game_mode") == "custom" else "standard"
	var count: Variant = entry.get("round_count",DifficultyRules.ROUND_COUNT)
	if not DifficultyRules.valid_round_count(count) or (mode == "standard" and int(count) != DifficultyRules.ROUND_COUNT): return {}
	if mode == "custom": category = "personal"
	return {"name":clean_name(entry.name),"score":int(entry.score),"difficulty":id,"category":category,
		"game_mode":mode,"round_count":int(count),"balance":version.left(64),"date":date.left(30),"id":run_id.left(100)}

func trim_scores() -> void:
	scores.sort_custom(func(a, b): return a.score > b.score)
	var counts := {}
	var kept: Array = []
	for entry in scores:
		var key := "%s/%s/%s" % [entry.get("category","previous"),entry.get("difficulty",""),entry.get("balance","legacy")]
		if entry.get("game_mode", "standard") == "custom": key += "/"+str(entry.get("round_count",DifficultyRules.ROUND_COUNT))
		counts[key] = int(counts.get(key,0)) + 1
		if counts[key] <= 10: kept.append(entry)
	scores = kept

func scores_for(tab: String) -> Array:
	var result: Array = []
	var catalog := DifficultyRules.catalog()
	for entry in scores:
		var category: String = entry.get("category","previous")
		if category == "standard" and entry.get("balance","") != DifficultyRules.version_for(entry.get("difficulty",""),catalog): category = "previous"
		if (tab in DifficultyRules.IDS and category == "standard" and entry.get("difficulty","") == tab) or (tab in ["personal","previous"] and category == tab):
			result.append(entry)
	result.sort_custom(func(a, b): return a.score > b.score)
	return result

static func write_document(absolute: String, payload: Dictionary, keep_backup: bool = false, mirror: bool = false) -> bool:
	var file := FileAccess.open(absolute + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	if not ok: return false
	# Publish the backup atomically too. An empty run retires any playable
	# snapshot on both paths, including when the device loses the primary.
	mirror = mirror or payload.get("run",{}).is_empty()
	var backup_source := absolute + ".tmp" if mirror else absolute
	if (mirror or not keep_backup) and FileAccess.file_exists(backup_source):
		if DirAccess.copy_absolute(backup_source, absolute + ".bak.tmp") != OK: return false
		if DirAccess.rename_absolute(absolute + ".bak.tmp", absolute + ".bak") != OK: return false
	return DirAccess.rename_absolute(absolute + ".tmp", absolute) == OK

func save(mirror_backup: bool = false) -> bool:
	if _closed: return false
	flush_pending()
	var payload := document()
	var absolute := ProjectSettings.globalize_path(path)
	storage_ok = write_document(absolute, payload, preserve_backup, mirror_backup)
	if storage_ok: preserve_backup = false
	_mutex.lock()
	_requested += 1
	_completed = _requested
	_completed_ok = storage_ok
	_writes += 1
	_mutex.unlock()
	_last_payload = payload
	_last_path = absolute
	return storage_ok

func save_async() -> bool:
	if _closed: return false
	if preserve_backup: return save()
	var payload := document()
	var absolute := ProjectSettings.globalize_path(path)
	_mutex.lock()
	var retry := _completed == _requested and not _completed_ok
	_mutex.unlock()
	if not retry and absolute == _last_path and payload == _last_payload:
		return true
	if _worker == null:
		_worker = Thread.new()
		if _worker.start(_save_loop) != OK:
			_worker = null
			return save()
	_last_payload = payload
	_last_path = absolute
	_mutex.lock()
	_requested += 1
	# The worker owns this immutable snapshot. New requests replace only the
	# queued job, never a document currently being written.
	_pending = {"serial":_requested,"path":absolute,"payload":payload}
	_mutex.unlock()
	_wake.post()
	return true

func _save_loop() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		var job := _pending
		_pending = {}
		var stopping := _stop
		_mutex.unlock()
		if job.is_empty():
			if stopping: return
			continue
		var ok := write_document(job.path, job.payload)
		_mutex.lock()
		_completed = job.serial
		_completed_ok = ok
		_writes += 1
		_mutex.unlock()
		_finished.post()

func poll_save() -> bool:
	_mutex.lock()
	storage_ok = _completed_ok
	_mutex.unlock()
	return storage_ok

func flush_pending() -> bool:
	while true:
		_mutex.lock()
		var done := _completed >= _requested
		_mutex.unlock()
		if done: return poll_save()
		_finished.wait()
	return false

func shutdown() -> bool:
	if _closed: return storage_ok
	flush_pending()
	_closed = true
	if _worker != null:
		_mutex.lock()
		_stop = true
		_mutex.unlock()
		_wake.post()
		_worker.wait_to_finish()
		_worker = null
	return storage_ok

static func clean_name(value: String) -> String:
	var cleaned := value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(18)
	return cleaned if not cleaned.is_empty() else "Caretaker"

func submit(run: GameModel, name_text: String) -> bool:
	if run.state != "won" or run.run_id in submitted:
		return false
	record_victory(run)
	var playable := active_run
	active_run = {}
	if submit_pending(run.run_id, name_text): return true
	active_run = playable
	return false

func record_victory(run: GameModel) -> Dictionary:
	if run.state != "won" or run.run_id in submitted: return {}
	for entry in pending_results:
		if entry.id == run.run_id: return entry
	var category := run.score_category()
	if category == "previous": category = "personal"
	var entry := {"name":player_name,"score":run.score,"difficulty":run.difficulty_id,"game_mode":run.game_mode,
		"category":category,"round_count":run.round_count,"balance":run.balance_version,"id":run.run_id,"date":Time.get_datetime_string_from_system(true)}
	pending_results.append(entry)
	if category == "standard" and run.difficulty_id in ["hard","extreme"] and run.difficulty_id not in badges:
		badges.append(run.difficulty_id)
	return entry

func submit_pending(id: String, name_text: String) -> bool:
	for pending in pending_results:
		if pending.id != id or id in submitted: continue
		var before := document()
		var entry := pending.duplicate()
		player_name = clean_name(name_text)
		entry.name = player_name
		if entry.category == "standard" and entry.balance != DifficultyRules.version_for(entry.difficulty):
			entry.category = "personal"
		var prior := scores_for(entry.difficulty)
		scores.append(entry)
		trim_scores()
		submitted.append(id)
		submitted = submitted.slice(-30)
		pending_results.erase(pending)
		if save(true):
			last_was_best = entry.category == "standard" and (prior.is_empty() or entry.score > prior[0].score)
			last_submitted_id = id
			return true
		scores = before.scores
		submitted = before.submitted
		pending_results.assign(before.pending_results)
		player_name = before.name
		return false
	return false
