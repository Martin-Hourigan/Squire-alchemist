extends SceneTree
## Headless: runs the fight many times with simple squire bots.
##   godot --headless --path . --script res://tests/sim_test.gd
## idle = never brews; dump = hands over every ingredient the moment it
## arrives; simple = keeps a full flask of reds in the low-HP slot, hands over
## black/gold straight away and reds when the hero is below 60%, redraws when
## it can.

const RUNS := 300
const DT := 0.05


func _init() -> void:
	var data := Fight.load_data()
	var errors := 0
	for bot in ["idle", "dump", "simple"]:
		var won := 0
		var hp_left := 0.0
		var secs := 0.0
		for r in RUNS:
			var f := Fight.new()
			f.setup(data, 1000 + r)
			while f.outcome == "" and f.t < 300.0:
				_bot(f, bot)
				f.step(DT)
				f.events.clear()
			if f.outcome == "":
				errors += 1
			if f.outcome == "won":
				won += 1
				hp_left += f.hero["hp"]
			secs += f.t
		print("%-7s win %3d%%   hp left when won %4.1f/%d   fight length %4.1fs" % [
			bot, 100 * won / RUNS, hp_left / maxi(1, won), int(data["hero"]["hp"]), secs / RUNS])
	print("errors: %d" % errors)
	quit(1 if errors else 0)


func _bot(f: Fight, bot: String) -> void:
	if bot == "idle":
		return
	if bot == "dump":
		while not f.hand.is_empty():
			f.add_to_flask(0)
			f.hand_over()
		return
	if f.redraw_ready():
		f.redraw()
	# black and gold go straight over, one per flask
	for id in ["black", "gold"]:
		var i := f.hand.find(id)
		if i >= 0 and f.flask.is_empty():
			f.add_to_flask(i)
			f.hand_over()
	# a full flask of reds sits in the low-HP slot
	if f.low_slot == null:
		while f.hand.has("red") and f.flask.size() < int(f.d["flask_max"]):
			f.add_to_flask(f.hand.find("red"))
		if f.flask.size() >= int(f.d["flask_max"]):
			f.to_low_slot()
		else:
			while not f.flask.is_empty():
				f.take_from_flask(0)
	elif f.hero["hp"] < f.hero["max"] * 0.6 and f.hand.has("red") and f.flask.is_empty():
		f.add_to_flask(f.hand.find("red"))
		f.hand_over()
