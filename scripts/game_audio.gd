class_name GameAudio
extends Node

signal track_changed(id: String)
signal effect_requested(id: String)

const MENU_TRACK = preload("res://assets/audio/music/jingle_bells.mp3")
const GAME_TRACKS := [
	{"id":"blue_ska","stream":preload("res://assets/audio/music/blue_ska.mp3")},
	{"id":"sunday_dub","stream":preload("res://assets/audio/music/sunday_dub.mp3")},
	# Comparsa and No Frills Comparsa share the catalogue's Comparsa.mp3.
	{"id":"no_frills_comparsa","stream":preload("res://assets/audio/music/no_frills_comparsa.mp3")},
	{"id":"peppy_pepe","stream":preload("res://assets/audio/music/peppy_pepe.mp3")},
	{"id":"bama_country","stream":preload("res://assets/audio/music/bama_country.mp3")}]
const SOUNDS := {
	"click":preload("res://assets/audio/click.ogg"),
	"win":preload("res://assets/audio/win.ogg"),
	"lose":preload("res://assets/audio/lose.ogg"),
	"hit":preload("res://assets/audio/hit.wav"),
	"shovel":preload("res://assets/audio/shovel.wav"),
	"chime":preload("res://assets/audio/chime.wav")}
const LEVELS := "res://assets/audio/music/playback_levels.json"

var music := AudioStreamPlayer.new()
var outcome := AudioStreamPlayer.new()
var effects: Array[AudioStreamPlayer] = []
var playlist := MusicPlaylist.new(GAME_TRACKS.size())
var context := ""
var current_game_track := -1
var game_position := 0.0
var finish_pending := false
var effect_volume := .7
var music_volume := .35
var next_player := 0
var paused := false
var suspended := false
var stopped := false
var music_started := false
var gains: Dictionary = {}

func _ready() -> void:
	add_child(music)
	add_child(outcome) # Clicks and shovel sounds cannot cut off a result cue.
	music.finished.connect(_on_music_finished)
	track_changed.connect(func(id: String):
		if OS.is_debug_build(): print("BIG_SNOW_SHIFT_MUSIC ",id))
	if FileAccess.file_exists(LEVELS):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVELS))
		if data is Dictionary: gains = data.get("tracks",{})
	for index in 6:
		var player := AudioStreamPlayer.new()
		add_child(player)
		effects.append(player)

func audible() -> bool:
	return DisplayServer.get_name() != "headless" and not stopped

func track_id() -> String:
	if context == "menu": return "jingle_bells"
	if context == "game" and current_game_track >= 0: return GAME_TRACKS[current_game_track].id
	return ""

func update_volume() -> void:
	var gain: float = gains.get(track_id(),{}).get("gain_db",-6.0)
	music.volume_db = linear_to_db(music_volume) + gain
	outcome.volume_db = linear_to_db(effect_volume)
	for player in effects:
		player.volume_db = linear_to_db(effect_volume)

func apply(settings: Dictionary) -> void:
	music_volume = clampf(float(settings.music),0,1)
	effect_volume = clampf(float(settings.effects),0,1)
	update_volume()

func set_suspended(value: bool) -> void:
	suspended = value
	if suspended:
		for player in effects: player.stop()
	outcome.stream_paused = suspended
	update_pause()

func update_pause() -> void:
	if not paused and not suspended and context == "game" and finish_pending:
		advance_track()
	if not audible() or music.stream == null:
		return
	if paused or suspended:
		music.stream_paused = true
	else:
		# Godot reports playing=false for a paused player too. Keep explicit
		# ownership of the started stream so resuming never calls play(0).
		if not music_started:
			music.play(game_position if context == "game" else 0)
			music_started = true
		music.stream_paused = false

func set_context(next: String, pause_music: bool = false) -> void:
	if stopped: return
	paused = pause_music
	if context == next:
		update_pause()
		return
	if context == "game" and current_game_track >= 0 and audible() and music.stream != null and music_started:
		game_position = music.get_playback_position()
	music.stop()
	music_started = false
	music.stream_paused = false
	context = next
	if context == "menu":
		var stream := MENU_TRACK.duplicate() as AudioStreamMP3
		stream.loop = true
		music.stream = stream
		track_changed.emit(track_id())
	elif context == "game":
		if current_game_track < 0:
			current_game_track = playlist.next_index()
			game_position = 0
		music.stream = GAME_TRACKS[current_game_track].stream
		track_changed.emit(track_id())
	else:
		music.stream = null
	update_volume()
	update_pause()

func begin_gameplay() -> void:
	# Keep shuffle history when starting another night/retry.
	if context == "game":
		music.stop()
		music_started = false
		context = ""
	current_game_track = -1
	game_position = 0
	finish_pending = false
	outcome.stop()

func _on_music_finished() -> void:
	if stopped or context != "game":
		return
	music_started = false
	if paused or suspended:
		finish_pending = true
		return
	advance_track()
	update_pause()

func advance_track() -> void:
	finish_pending = false
	music_started = false
	current_game_track = playlist.next_index()
	game_position = 0
	music.stream = GAME_TRACKS[current_game_track].stream
	update_volume()
	track_changed.emit(track_id())

func play_outcome(sound: String) -> void:
	if stopped or sound not in ["win","lose"]: return
	set_context("quiet")
	outcome.stop()
	outcome.stream = SOUNDS[sound]
	if effect_volume <= 0: return
	effect_requested.emit(sound)
	if audible():
		outcome.volume_db = linear_to_db(effect_volume)
		outcome.play()
		outcome.stream_paused = suspended

func play(sound: String) -> void:
	if stopped or effect_volume <= 0 or not SOUNDS.has(sound): return
	effect_requested.emit(sound)
	if not audible() or suspended: return
	var player := effects[next_player]
	next_player = (next_player + 1) % effects.size()
	player.stream = SOUNDS[sound]
	player.volume_db = linear_to_db(effect_volume)
	player.play()

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	stopped = true
	music_started = false
	music.stop()
	outcome.stop()
	for player in effects: player.stop()
