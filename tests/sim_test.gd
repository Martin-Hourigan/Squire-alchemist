extends SceneTree
## Headless: runs the fight many times with simple squire bots.
##   godot --headless --path . --script res://tests/sim_test.gd
## idle = never brews; single = hands over every ingredient alone the moment
## it arrives; mix = throws whatever it holds into one flask (random order) -
## shows what careless mixing costs; paired = brews matching pairs (red+gold
## for the knight, black+blue at the brute), keeps red+gold+red in the low-HP
## slot, redraws when it can.

const RUNS := 300
const DT := 0.05


func _init() -> void:
	var data := Fight.load_data()
	var errors := 0
	for bot in ["idle", "single", "mix", "paired"]:
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
	if bot == "single":
		while not f.hand.is_empty():
			f.add_to_flask(0)
			f.hand_over()
		return
	if bot == "mix":
		if f.hand.size() >= 3:
			f.hand.shuffle()
			while f.add_to_flask(0):
				pass
			f.hand_over()
		return
	if f.redraw_ready() and f.hand.size() >= 3:
		f.redraw()
	if f.low_slot == null and _brew(f, ["red", "gold", "red"]):
		f.to_low_slot()
	if _brew(f, ["black", "blue"]):
		f.hand_over()
	if f.hero["hp"] < f.hero["max"] * 0.75 and _brew(f, ["red", "gold"]):
		f.hand_over()


## Put exactly these ingredients in the flask (in order) if the hand has them.
func _brew(f: Fight, ids: Array) -> bool:
	if not f.flask.is_empty():
		return false
	var need := {}
	for id in ids:
		need[id] = int(need.get(id, 0)) + 1
	for id in need:
		if f.hand.count(id) < need[id]:
			return false
	for id in ids:
		f.add_to_flask(f.hand.find(id))
	return true
