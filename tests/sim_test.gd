extends SceneTree
## Headless: runs the fight many times with simple squire bots, in both
## modes (real time, turns).
##   godot --headless --path . --script res://tests/sim_test.gd
## idle = never brews; single = hands over every ingredient alone the moment
## it arrives; mix = throws whatever it holds into one flask (random order) -
## shows what careless mixing costs; paired = brews recipes when it holds
## them (Healing Draught kept in the low-HP slot), redraws when it holds none.

const RUNS := 300
const DT := 0.05


func _init() -> void:
	var data := Fight.load_data()
	var errors := 0
	for mode in ["realtime", "turns"]:
		for bot in ["idle", "single", "mix", "paired"]:
			errors += _run(data, mode, bot)
	print("errors: %d" % errors)
	quit(1 if errors else 0)


func _run(data: Dictionary, mode: String, bot: String) -> int:
		var errors := 0
		var won := 0
		var hp_left := 0.0
		var secs := 0.0
		var turns := 0
		for r in RUNS:
			var f := Fight.new()
			f.setup(data, 1000 + r, mode)
			while f.outcome == "" and f.t < 600.0:
				if f.your_turn():
					_bot(f, bot)
					f.end_turn()
				f.step(DT)
				f.events.clear()
			turns += f.turn
			if f.outcome == "":
				errors += 1
			if f.outcome == "won":
				won += 1
				hp_left += f.hero["hp"]
			secs += f.t
		var length := "%4.1fs" % (secs / RUNS) if mode == "realtime" else "%4.1f turns" % (float(turns) / RUNS)
		print("%-8s %-7s win %3d%%   hp left when won %4.1f/%d   fight length %s" % [
			mode, bot, 100 * won / RUNS, hp_left / maxi(1, won), int(data["hero"]["hp"]), length])
		return errors


func _bot(f: Fight, bot: String) -> void:
	if bot == "idle":
		return
	if bot == "single":
		while not f.hand.is_empty() and f.add_to_flask(0) and f.hand_over():
			pass
		return
	if bot == "mix":
		if f.hand.size() >= 3 and f.potions_left() > 0:
			f.hand.shuffle()
			while f.add_to_flask(0):
				pass
			f.hand_over()
		return
	if f.redraw_ready() and f.hand.size() >= 3 and f.recipe_ids(f.d).all(func(r): return not _can(f, r)):
		f.redraw()
	if f.low_slot == null and _brew(f, f.d["recipes"]["healing_draught"]["ings"]):
		f.to_low_slot()
	for r in ["iron_tonic", "shield_oil", "venom_oil", "bitter_edge"]:
		if _brew(f, f.d["recipes"][r]["ings"]):
			f.hand_over()
	if f.hero["hp"] < f.hero["max"] * 0.75 and _brew(f, f.d["recipes"]["healing_draught"]["ings"]):
		f.hand_over()


func _can(f: Fight, r: String) -> bool:
	var ids: Array = f.d["recipes"][r]["ings"]
	for id in ids:
		if f.hand.count(id) < ids.count(id):
			return false
	return true


## Put exactly these ingredients in the flask (in order) if the hand has them.
func _brew(f: Fight, ids: Array) -> bool:
	if not f.flask.is_empty() or f.potions_left() <= 0:
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
