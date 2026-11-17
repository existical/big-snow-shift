extends SceneTree

# Sample decoded PCM to choose attenuation without changing the recordings.
func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/soundtrack-v0.19.json"))
	var levels := {}
	var rate := AudioServer.get_mix_rate()
	for item in manifest.music:
		var stream := AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes("res://" + item.path)
		var playback := stream.instantiate_playback()
		var sum := 0.0
		var count := 0
		var peak := 0.0
		for section in 8:
			playback.start(stream.get_length() * (.1 + section * .1))
			for block in ceili(rate * 6.0 / 4096):
				var samples := playback.mix_audio(1.0,4096)
				for frame in range(0,samples.size(),4):
					var value: Vector2 = samples[frame]
					sum += value.length_squared()
					count += 2
					peak = maxf(peak,maxf(absf(value.x),absf(value.y)))
			playback.stop()
		if count == 0 or sum <= 0:
			printerr("FAIL: decoded music is silent: " + item.id)
			quit(1)
			return
		var rms := linear_to_db(sqrt(sum / count))
		var gain := snappedf(minf(0,-22.0 - rms),.1)
		levels[item.id] = {"gain_db":gain,"sampled_rms_dbfs":rms,"sampled_peak_dbfs":linear_to_db(peak),"duration":stream.get_length()}
		print("MUSIC_LEVEL ",item.id," duration=",snappedf(stream.get_length(),.01)," rms=",snappedf(rms,.1)," gain=",gain)
	var report := {"method":"Eight six-second sections at 10%..80%; every fourth decoded stereo frame; attenuation only to sampled RMS -22 dBFS. Not integrated LUFS or true-peak measurement.","mix_rate":rate,"tracks":levels}
	var file := FileAccess.open("res://assets/audio/music/playback_levels.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	quit()
