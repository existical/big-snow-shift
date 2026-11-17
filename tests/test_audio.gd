extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: Control
var requested: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func test_shuffle() -> void:
	for seed_value in 24:
		var bag := MusicPlaylist.new(GameAudio.GAME_TRACKS.size(),seed_value)
		var valid := true
		var previous := -1
		for cycle in 30:
			var seen: Array[int] = []
			for slot in GameAudio.GAME_TRACKS.size():
				var next := bag.next_index()
				valid = valid and next != previous and next >= 0 and next < GameAudio.GAME_TRACKS.size() and next not in seen
				seen.append(next)
				previous = next
		check(valid,"every shuffle cycle uses every distinct recording once with no consecutive repeats, seed %d" % seed_value)
	check(MusicPlaylist.new(0,1).next_index() == -1 and MusicPlaylist.new(1,1).next_index() == 0,"empty and single-track shuffle pools are bounded")

func run() -> void:
	test_shuffle()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/soundtrack-v0.19.json"))
	var ids: Array[String] = []
	var hashes: Array[String] = []
	for item in manifest.music:
		var bytes := FileAccess.get_file_as_bytes("res://" + item.path)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		var digest := hash.finish().hex_encode()
		check(digest == item.original_sha256 and digest == item.game_audio_sha256 and digest not in hashes,"each recording matches the original download and is included only once")
		hashes.append(digest)
		ids.append(item.id)
	check(ids.size() == GameAudio.GAME_TRACKS.size() + 1 and manifest.aliases.Comparsa == manifest.aliases["No Frills Comparsa"],"the menu and distinct gameplay catalogue deduplicate the Comparsa alias")
	var levels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameAudio.LEVELS))
	for item in manifest.music:
		check(levels.tracks.has(item.id) and float(levels.tracks[item.id].duration) > 90 and float(levels.tracks[item.id].gain_db) <= 0,"each music file decodes to the expected full length and has measured playback attenuation")
	for name in ["click","win","lose"]:
		var stream: AudioStreamOggVorbis = GameAudio.SOUNDS[name]
		var playback := stream.instantiate_playback()
		playback.start()
		var energy := 0.0
		for block in 12:
			for value in playback.mix_audio(1.0,4096): energy += value.length_squared()
		playback.stop()
		check(not stream.loop and stream.get_length() > .03 and energy > 0,"the %s Ogg decodes, contains sound and does not loop" % name)
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/sound-effects.json"))
	for effect in effects.effects:
		check(FileAccess.get_sha256("res://" + effect.path) == effect.sha256, "effect matches its recorded provenance: " + effect.path)
		check(absf(GameAudio.SOUNDS[effect.role].get_length() - float(effect.duration_seconds)) < .002, "effect retains its recorded duration: " + effect.role)
	var credits := FileAccess.get_file_as_string("res://assets/licenses/MUSIC_CREDITS.txt")
	var credited := credits.contains("Kevin MacLeod") and credits.contains("https://creativecommons.org/licenses/by/4.0/") and credits.contains("playback volume")
	for item in manifest.music: credited = credited and credits.contains(item.isrc) and credits.contains(item.title)
	check(credited and FileAccess.file_exists("res://assets/licenses/CC-BY-4.0.txt"),"all included recordings have bundled credits, source identifiers, changes and full licence")
	game = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	game.profile.path = "res://builds/audio-test-unused-profile.json"
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.sound.set_suspended(false)
	game.sound.effect_requested.connect(func(id: String): requested.append(id))
	check(game.sound.context == "menu" and game.sound.track_id() == "jingle_bells" and game.sound.music.stream.loop,"the menu uses the requested Jingle Bells recording in a loop")
	check(not GameAudio.MENU_TRACK.loop,"menu looping does not mutate the shared original stream")
	game.start_night()
	var first: String = game.sound.track_id()
	var remaining: Array = game.sound.playlist.remaining.duplicate()
	check(first != "jingle_bells" and game.sound.context == "game" and not game.sound.music.stream.loop,"starting a night selects one non-looping gameplay track")
	game.show_pause()
	game.show_settings("pause")
	game.show_privacy()
	check(game.model.paused and game.sound.paused and game.sound.track_id() == first and game.sound.playlist.remaining == remaining, "privacy preserves paused gameplay and soundtrack")
	game.show_credits()
	check(game.sound.track_id() == first and game.sound.paused and game.sound.playlist.remaining == remaining,"pause/settings/credits preserve the selected gameplay track and shuffle state")
	game.show_credits(true)
	check(game.model.paused and game.sound.track_id() == first and game.sound.paused and game.sound.playlist.remaining == remaining,"licences preserve paused gameplay and soundtrack state")
	game.handle_back_request()
	check(game.view == "credits", "Back from licences returns to credits")
	game.close_settings()
	game.resume_game()
	check(game.sound.track_id() == first and not game.sound.paused,"resume keeps the same track")
	game.show_menu()
	check(game.sound.track_id() == "jingle_bells","returning to the main menu restores Jingle Bells")
	game.profile.active_run = game.model.snapshot()
	game.continue_night()
	check(game.view == "pause" and game.sound.track_id() == first and game.sound.paused,"Continue restores gameplay audio at a pause without selecting another track")
	game.resume_game()
	check(game.sound.track_id() == first,"returning to an existing night preserves its gameplay selection")
	game.sound.music.finished.emit()
	check(game.sound.track_id() != first,"a natural finished signal chooses a different gameplay track")
	first = game.sound.track_id()
	game.show_pause()
	game.sound.music.finished.emit() # A completion queued on the pause boundary.
	check(game.sound.finish_pending and game.sound.track_id() == first,"a finish arriving during pause is retained without starting music")
	game.resume_game()
	check(game.sound.track_id() != first and not game.sound.finish_pending,"resume advances a completed track instead of repeating it")
	game._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.sound.suspended and game.sound.paused,"backgrounding suspends audio and pauses gameplay")
	game._notification(Control.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not game.sound.suspended and game.sound.paused,"focus return does not automatically resume a paused game")
	game.resume_game()
	game.profile.settings.music = 0
	game.profile.settings.effects = 0
	game.apply_settings()
	requested.clear()
	game.sound.play("click")
	var effects_muted := is_zero_approx(game.sound.outcome.volume_linear)
	for player in game.sound.effects: effects_muted = effects_muted and is_zero_approx(player.volume_linear)
	check(is_zero_approx(game.sound.music.volume_linear) and effects_muted and requested.is_empty(),"music and all current/future effects respect mute settings")
	game.profile.settings.music = .35
	game.profile.settings.effects = .7
	game.apply_settings()
	var expected := linear_to_db(.35) + float(levels.tracks[game.sound.track_id()].gain_db)
	check(is_equal_approx(game.sound.music.volume_db,expected),"music volume includes the current track's measured gain")
	game.sound.play("click")
	check(requested == ["click"] and GameAudio.SOUNDS.click.resource_path.ends_with("click.ogg"),"menu click dispatches the selected Ogg effect")
	for round_index in 3:
		game.model.begin_round(round_index)
		game.resume_game()
		requested.clear()
		game.model.prepare_finish()
		check("win" not in requested,"clearing snow does not play the final game-win cue early")
		game.model.player = RoundEnding.DOOR_TARGET
		game.model.step(.01,Vector2.ZERO)
		for tick in 100: game.model.step(.1,Vector2.ZERO)
		check(requested.count("win") == (1 if round_index == 2 else 0),"only the final completed Santa celebration plays win.ogg once")
		if round_index == 2:
			check(game.sound.context == "quiet" and game.sound.outcome.stream == GameAudio.SOUNDS.win,"the final win stops the soundtrack and selects the restored fanfare")
			game.show_result()
			game.show_result()
			check(requested.count("win") == 1,"redrawing/restoring a result does not replay its win cue")
	for count in [1,2]:
		game.model.start(55,"hard",{"no_time_limit":false,"no_icicles":false},"custom",{},count)
		for index in count:
			game.model.begin_round(index)
			game.resume_game()
			requested.clear()
			game.model.snow.brush(Vector2(.5,.5),Vector2.ONE*2,765)
			game.model.prepare_finish()
			game.model.player = RoundEnding.DOOR_TARGET
			game.model.step(.01,Vector2.ZERO)
			for tick in 28: game.model.step(.1,Vector2.ZERO)
			check(requested.count("win") == 0,"short Custom game does not play win before its final tree scene finishes")
			for tick in 55: game.model.step(.1,Vector2.ZERO)
			check(requested.count("win") == (1 if index == count-1 else 0),"short Custom game plays one final win cue")
			game.show_result()
			game.show_result()
			check(requested.count("win") == (1 if index == count-1 else 0),"short Custom result redraw cannot repeat the win cue")
	game.model.start(56,"hard")
	game.model.begin_round(1)
	game.resume_game()
	requested.clear()
	game.model.time_left = .001
	game.model.step(.1,Vector2.ZERO)
	check(game.model.state == "timeout" and "lose" not in requested,"time expiry waits for Santa's fall before the loss cue")
	for tick in 25: game.model.step(.1,Vector2.ZERO)
	game.show_pause()
	var phase: float = game.model.failure_time
	game._physics_process(.1)
	check(game.model.failure_time == phase and "lose" not in requested,"pausing during Santa's fall neither advances it nor plays the loss cue")
	game.resume_game()
	for tick in 90: game.model.step(.1,Vector2.ZERO)
	check(game.model.state == "lost" and requested.count("lose") == 1 and game.sound.outcome.stream == GameAudio.SOUNDS.lose,"lose.ogg plays once when Santa's full fall ends")
	game.show_result()
	game.show_result()
	check(requested.count("lose") == 1,"showing the loss result again does not replay the cue")
	game.profile.active_run = game.model.snapshot()
	game.show_menu()
	game.continue_night()
	check(game.view == "menu" and game.profile.active_run.is_empty() and game.sound.context == "menu" and requested.count("lose") == 1,"ended Continue saves return to menu without replaying the outcome")
	first = GameAudio.GAME_TRACKS[game.sound.current_game_track].id
	game.retry_round()
	check(game.sound.context == "game" and game.sound.track_id() != first,"retry selects the next shuffled recording without an immediate repeat")
	game.show_settings("pause")
	game.show_credits()
	var visible_credits := ""
	for child in game.overlay.get_children():
		for nested in child.get_children():
			if nested is RichTextLabel: visible_credits = nested.text
	check(visible_credits.contains("Jingle Bells") and visible_credits.contains("MUSIC CREDITS"), "in-game credits visibly include the music attribution")
	check(visible_credits.count("SOUND EFFECTS") == 1 and not credits.contains("SOUND EFFECTS"), "effect credits appear once in their own section")
	var sound_credits := FileAccess.get_file_as_string("res://assets/licenses/SOUND_CREDITS.txt").strip_edges()
	check(visible_credits.contains(sound_credits), "in-game credits include the bundled sound attributions")
	for effect in effects.effects:
		check(sound_credits.contains(effect.creator) and sound_credits.contains(effect.title) and sound_credits.contains(effect.source_url) and sound_credits.contains(effect.license_url), "recording is credited with its creator, title, source and licence")
	check(sound_credits.contains("OGG preview") and sound_credits.contains("Playback volume"), "click attribution identifies the supplied format and playback adjustment")
	check(game.credits_text().contains("Existical Games\nhttp://www.existical.com") and game.credits_text().contains("NIKITA Ltd."), "credits identify the current studio and original game's developer")
	check(not game.credits_text().contains("Permission is hereby granted") and not game.credits_text().contains("Source follow-up"), "acknowledgements omit full legal boilerplate and development tasks")
	var legal: String = game.licenses_text()
	check(legal.contains(FileAccess.get_file_as_string("res://assets/licenses/CC0-1.0.txt")), "full CC0 terms are available offline")
	check(legal.contains(Engine.get_license_text()) and legal.contains(FileAccess.get_file_as_string("res://assets/licenses/THIRD_PARTY_NOTICES.txt")) and legal.contains(FileAccess.get_file_as_string("res://assets/licenses/CC-BY-4.0.txt")), "licences retain complete engine, third-party and music terms offline")
	for name in ["Nunito", "MPLUSRounded1c"] + Array(GameLocalization.FONT_NAMES):
		check(legal.contains(FileAccess.get_file_as_string("res://assets/fonts/" + name + "-LICENSE.txt")), "licences preserve the full copyright and OFL for " + name)
	game.sound.shutdown()
	first = game.sound.track_id()
	game.sound.music.finished.emit()
	check(game.sound.track_id() == first and not game.sound.music.playing and not game.sound.outcome.playing,"shutdown prevents a finished callback from restarting audio")
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("res://builds/audio-test-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify(report))
	game.quit_game(0 if failures.is_empty() else 1)
