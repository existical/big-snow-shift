extends "res://tests/test_game.gd"
## Reuse the existing input-only caretaker route; never edit snow or hazards.

func _initialize() -> void:
	var attempts: Array = []
	for id in ["easy","medium","extreme"]:
		for seed_value in [7,31]:
			var model := GameModel.new(GameSettings.new())
			model.start(seed_value,id)
			for round_index in 3:
				play_round(model)
				attempts.append({"difficulty":id,"seed":seed_value,"round":round_index+1,
					"seconds":snappedf(model.elapsed,.01),"hits":model.round_hits,"state":model.state})
				check(model.state == ("won" if round_index == 2 else "celebrating"),id+" completes round "+str(round_index+1)+" seed "+str(seed_value))
				if model.state == "lost": break
				model.next_round()
			check(model.state == "won" and model.score_category() == "standard",id+" completes all three rounds with preset-eligible rules")
	var result := {"checks":checks,"failures":failures,"playthroughs":attempts}
	FileAccess.open("res://builds/difficulty/playthroughs.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
