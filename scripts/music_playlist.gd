class_name MusicPlaylist
extends RefCounted

var count: int
var remaining: Array[int] = []
var last := -1
var rng := RandomNumberGenerator.new()

func _init(track_count: int = 0, seed_value: int = -1) -> void:
	count = maxi(0,track_count)
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value

func next_index() -> int:
	if count == 0:
		return -1
	if remaining.is_empty():
		remaining.assign(range(count))
		for index in range(count - 1,0,-1):
			var other := rng.randi_range(0,index)
			var held := remaining[index]
			remaining[index] = remaining[other]
			remaining[other] = held
		# Each cycle contains every recording once. Prevent a consecutive
		# repeat where the end of one cycle meets the start of another.
		if count > 1 and remaining.back() == last:
			var other := rng.randi_range(0,count - 2)
			remaining[remaining.size() - 1] = remaining[other]
			remaining[other] = last
	last = remaining.pop_back()
	return last
