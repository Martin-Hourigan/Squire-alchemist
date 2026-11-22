class_name Fight
extends RefCounted
## The rules of one fight (no drawing here; fight_view.gd shows it), in one
## of two modes:
##   realtime - the hero fights on their own: attacks on a timer, fires the
##     weapon special when its power is full.
##   turns - your turn (brew, hand over, END TURN), then the hero attacks,
##     then the enemy does what it showed it would (attack, block, or a Big
##     Swing). An enemy that blocks stops the hero's first hit; the hero
##     always blocks the enemy's hit, so it lands at hero_block.
## You, the alchemist, hold ingredients drawn from your bag, put 1-3 in the
## flask and either HAND IT OVER (real time: the hero uses it the next time
## they're free; turns: right away) or put it in the LOW-HP SLOT (used when HP
## drops low). Every potion is for the hero and their gear: heal, a shield
## WARD that soaks up damage, VENOM on the weapon that poisons with each hit.
## Three ingredients that make a RECIPE brew that named potion, much stronger;
## anything else is an unnamed potion, the ingredients' effects added up.
## Brewing a recipe you didn't know puts it in your book.
## You start with a full hand; nothing arrives on its own in real time. A
## meter (seconds, or turns) lets you REDRAW: swap your whole hand. In turns,
## a couple more are drawn each turn. Used ingredients reshuffle back in.
## All numbers come from data/fight.json and are placeholders.

const EFFECTS := ["heal", "ward", "venom"]

var d: Dictionary
var mode := "realtime"
var m: Dictionary  # d[mode]
var rng := RandomNumberGenerator.new()
var t := 0.0
var outcome := ""    # "", "won", "lost"
var known := {}      # recipe id -> true (the book)

var hero := {}
var enemy := {}

var draw_pile: Array = []
var hand: Array = []       # ingredient ids
var flask: Array = []      # ingredient ids (still count toward the hand cap)
var discard: Array = []
var handed: Array = []     # potions waiting for the hero, used in order
var low_slot = null        # one potion or null
var redraw_t := 0.0  # seconds (realtime) or turns since the last redraw
var poison_t := 0.0

# turns
var turn := 1
var phase := "you"  # you, hero (hero just attacked), enemy (enemy just acted)
var phase_t := 0.0
var potions_used := 0  # this turn
var intent := "attack"  # what the enemy will do: attack, big, block

## What happened since the view last looked: {kind, amount, text}.
var events: Array = []


func setup(data: Dictionary, seed_value: int, mode_ := "realtime", book := {}) -> void:
	d = data
	mode = mode_
	m = d[mode]
	known = book
	rng.seed = seed_value
	var h: Dictionary = d["hero"]
	hero = {"hp": float(h["hp"]), "max": float(h["hp"]), "power": 0.0, "ward": 0.0, "venom": 0,
		"cd": float(h["attack_every"]), "busy": 0.0, "frame": "idle", "frame_t": 0.0}
	var e: Dictionary = d["enemy"]
	enemy = {"hp": float(e["hp"]), "max": float(e["hp"]), "cd": float(e["attack_every"]), "poison": 0,
		"count": 0, "winding": false, "wind_t": 0.0, "frame": "idle", "frame_t": 0.0}
	draw_pile = d["bag"].duplicate()
	_shuffle(draw_pile)
	for i in int(m["start_hand"]):
		_draw_one()
	if mode == "turns":
		_pick_intent()


## The recipes at the start (marked known in the data).
static func starting_book(data: Dictionary) -> Dictionary:
	var book := {}
	for id in recipe_ids(data):
		if data["recipes"][id].get("known", false):
			book[id] = true
	return book


static func recipe_ids(data: Dictionary) -> Array:
	return data["recipes"].keys().filter(func(k): return not k.begins_with("_"))


# ── Your actions ─────────────────────────────────────────────────────────────

func held() -> int:
	return hand.size() + flask.size()


func can_add(i: int) -> bool:
	return your_turn() and i >= 0 and i < hand.size() and flask.size() < int(d["flask_max"])


func add_to_flask(i: int) -> bool:
	if not can_add(i):
		return false
	flask.append(hand[i])
	hand.remove_at(i)
	return true


func take_from_flask(i: int) -> void:
	if i >= 0 and i < flask.size():
		hand.append(flask[i])
		flask.remove_at(i)


func flask_ready() -> bool:
	return outcome == "" and flask.size() >= int(d["flask_min"])


## Can you act now? (Always in real time; only on your turn in turns.)
func your_turn() -> bool:
	return outcome == "" and (mode == "realtime" or phase == "you")


func potions_left() -> int:
	return 99 if mode == "realtime" else int(m["potions_per_turn"]) - potions_used


func can_hand_over() -> bool:
	return flask_ready() and your_turn() and potions_left() > 0


## Real time: the hero uses it at their next chance. Turns: right away.
func hand_over() -> bool:
	if not can_hand_over():
		return false
	if mode == "turns":
		potions_used += 1
		_use(_brew())
	else:
		handed.append(_brew())
	return true


func can_slot() -> bool:
	return flask_ready() and low_slot == null and your_turn() and potions_left() > 0


func to_low_slot() -> bool:
	if not can_slot():
		return false
	if mode == "turns":
		potions_used += 1
	low_slot = _brew()
	return true


func redraw_need() -> float:
	return float(m["redraw_fill"]) if mode == "realtime" else float(m["redraw_turns"])


func redraw_ready() -> bool:
	return your_turn() and redraw_t >= redraw_need()


## Discard the hand (not the flask) and draw a full one.
func redraw() -> bool:
	if not redraw_ready():
		return false
	discard.append_array(hand)
	hand.clear()
	while held() < int(d["hand_cap"]) and _draw_one():
		pass
	redraw_t = 0.0
	return true


# ── Brewing ──────────────────────────────────────────────────────────────────

## The recipe these ingredients make (any order), or "".
func recipe_of(ids: Array) -> String:
	var mine := ids.duplicate()
	mine.sort()
	for id in recipe_ids(d):
		var want: Array = d["recipes"][id]["ings"].duplicate()
		want.sort()
		if want == mine:
			return id
	return ""


## What the flask would make right now: {recipe, name, fx: {effect: amount}}.
## A recipe you don't know yet still shows as unnamed until you brew it.
func flask_effects(ids: Array = flask) -> Dictionary:
	var fx := {}
	for e in EFFECTS:
		fx[e] = 0.0
	var r := recipe_of(ids)
	if r != "":
		for e in d["recipes"][r]["fx"]:
			fx[e] += float(d["recipes"][r]["fx"][e])
	else:
		for id in ids:
			for e in d["ingredients"][id]["fx"]:
				fx[e] += float(d["ingredients"][id]["fx"][e])
	var name := "Unnamed potion"
	if r != "" and known.has(r):
		name = String(d["recipes"][r]["name"])
	elif r != "":
		name = "Unknown recipe?"
	return {"recipe": r, "name": name, "fx": fx}


func _brew() -> Dictionary:
	var p := flask_effects()
	p["ings"] = flask.duplicate()
	if p["recipe"] != "" and not known.has(p["recipe"]):
		learn(p["recipe"])
		p["name"] = String(d["recipes"][p["recipe"]]["name"])
	discard.append_array(flask)
	flask.clear()
	return p


func learn(r: String) -> void:
	known[r] = true
	events.append({"kind": "learned", "text": String(d["recipes"][r]["name"])})


# ── Time ─────────────────────────────────────────────────────────────────────

func step(dt: float) -> void:
	if outcome != "":
		return
	t += dt
	for a in [hero, enemy]:
		a["frame_t"] -= dt
		if a["frame_t"] <= 0.0:
			a["frame"] = "idle"
	if mode == "turns":
		_turn_step(dt)
		return
	redraw_t = minf(redraw_need(), redraw_t + dt)
	poison_t += dt
	if poison_t >= float(d["poison_tick"]):
		poison_t = 0.0
		_poison_tick()
	_hero_step(dt)
	if outcome == "":
		_enemy_step(dt)


func _hero_step(dt: float) -> void:
	var sp: Dictionary = d["special_power"]
	hero["power"] = minf(float(sp["max"]), hero["power"] + float(sp["per_second"]) * dt)
	hero["busy"] -= dt
	hero["cd"] -= dt
	if hero["busy"] > 0.0:
		return
	if _check_low_slot():
		return
	if not handed.is_empty():
		_use(handed.pop_front())
		return
	if hero["cd"] <= 0.0:
		hero["cd"] = float(d["hero"]["attack_every"])
		hero["busy"] = float(d["attack_frame_time"])
		_frame(hero, "attack")
		var w: Dictionary = d["weapons"][d["hero"]["weapon"]]
		if hero["power"] >= float(sp["max"]):
			hero["power"] = 0.0
			_hero_hit(float(w["special_dmg"]), String(w["special"]) + "!")
		else:
			_hero_hit(float(d["hero"]["attack_dmg"]), "")


func _check_low_slot() -> bool:
	if low_slot != null and hero["hp"] <= hero["max"] * float(d["low_hp_at"]):
		var p: Dictionary = low_slot
		low_slot = null
		_use(p, "low-HP slot")
		return true
	return false


## The hero drinks it, rubs it on the weapon, or on the shield.
func _use(p: Dictionary, from: String = "") -> void:
	hero["busy"] = float(d["hero"]["drink_time"])
	events.append({"kind": "use", "text": String(p["name"]) + (" (" + from + ")" if from != "" else "")})
	var fx: Dictionary = p["fx"]
	if fx["heal"] > 0.0:
		var before: float = hero["hp"]
		hero["hp"] = minf(hero["max"], hero["hp"] + fx["heal"])
		events.append({"kind": "heal", "amount": hero["hp"] - before, "wasted": fx["heal"] - (hero["hp"] - before)})
	if fx["ward"] > 0.0:
		hero["ward"] += fx["ward"]
		events.append({"kind": "ward", "amount": fx["ward"]})
	if fx["venom"] > 0.0:
		hero["venom"] += int(fx["venom"])
		events.append({"kind": "venom", "amount": fx["venom"]})


func _enemy_step(dt: float) -> void:
	var e: Dictionary = d["enemy"]
	if enemy["winding"]:
		enemy["wind_t"] -= dt
		if enemy["wind_t"] <= 0.0:
			enemy["winding"] = false
			_hurt_hero(float(e["big_dmg"]), String(e["big_name"]))
		return
	enemy["cd"] -= dt
	if enemy["cd"] <= 0.0:
		enemy["cd"] = float(e["attack_every"])
		enemy["count"] += 1
		if enemy["count"] % int(e["big_every"]) == 0:
			enemy["winding"] = true
			enemy["wind_t"] = float(e["big_windup"])
			events.append({"kind": "windup", "text": String(e["big_name"])})
		else:
			_hurt_hero(float(e["attack_dmg"]), "")


# ── Turns ────────────────────────────────────────────────────────────────────

## Done on your turn: the hero attacks now, the enemy a beat later.
func end_turn() -> bool:
	if mode != "turns" or not your_turn():
		return false
	_hero_attacks()
	phase = "hero"
	phase_t = float(m["beat"])
	return true


func _turn_step(dt: float) -> void:
	if phase == "you":
		return
	phase_t -= dt
	if phase_t > 0.0:
		return
	if phase == "hero":
		_poison_tick()
		if outcome == "":
			_enemy_acts()
		phase = "enemy"
		phase_t = float(m["beat"])
	elif outcome == "":
		_new_turn()


## The hero's attack, then the special too if power is full. An enemy that
## chose to block stops the first hit.
func _hero_attacks() -> void:
	_frame(hero, "attack")
	var sp: Dictionary = d["special_power"]
	var w: Dictionary = d["weapons"][d["hero"]["weapon"]]
	var hits: Array = [[float(d["hero"]["attack_dmg"]), ""]]
	if hero["power"] >= float(sp["max"]):
		hero["power"] = 0.0
		hits.append([float(w["special_dmg"]), String(w["special"]) + "!"])
	for i in hits.size():
		if i == 0 and intent == "block":
			events.append({"kind": "enemy_block", "text": "blocked"})
			continue
		_hero_hit(hits[i][0], hits[i][1])
		if outcome != "":
			return


func _enemy_acts() -> void:
	var e: Dictionary = d["enemy"]
	var cut := float(m["hero_block"])
	match intent:
		"attack": _hurt_hero(float(e["attack_dmg"]) * cut, "blocked")
		"big": _hurt_hero(float(e["big_dmg"]) * cut, String(e["big_name"]) + ", blocked")
		"block": events.append({"kind": "windup", "text": "guards"})


func _new_turn() -> void:
	turn += 1
	phase = "you"
	potions_used = 0
	redraw_t = minf(redraw_need(), redraw_t + 1.0)
	var sp: Dictionary = d["special_power"]
	hero["power"] = minf(float(sp["max"]), hero["power"] + float(m["power_per_turn"]))
	for i in int(m["draw_per_turn"]):
		if held() >= int(d["hand_cap"]) or not _draw_one():
			break
	_pick_intent()


## Every big_every-th turn a Big Swing; otherwise attack, or now and then block.
func _pick_intent() -> void:
	enemy["count"] += 1
	if enemy["count"] % int(d["enemy"]["big_every"]) == 0:
		intent = "big"
	elif rng.randf() < float(m["enemy_block_chance"]):
		intent = "block"
	else:
		intent = "attack"


# ── Hits ─────────────────────────────────────────────────────────────────────

## A hit from the hero; a venomed weapon poisons too.
func _hero_hit(n: float, label: String) -> void:
	_hurt_enemy(n, label)
	if hero["venom"] > 0 and outcome == "":
		hero["venom"] -= 1
		enemy["poison"] += int(d["venom_poison"])
		events.append({"kind": "poisoned", "amount": d["venom_poison"]})


func _poison_tick() -> void:
	if enemy["poison"] <= 0:
		return
	_hurt_enemy(float(enemy["poison"]), "poison")
	enemy["poison"] -= 1


func _hurt_enemy(n: float, label: String) -> void:
	enemy["hp"] = maxf(0.0, enemy["hp"] - n)
	events.append({"kind": "enemy_hit", "amount": n, "text": label})
	if enemy["hp"] <= 0.0:
		outcome = "won"


## A hit on the hero: the shield ward soaks it up first.
func _hurt_hero(n: float, label: String) -> void:
	_frame(enemy, "attack")
	var soak := minf(hero["ward"], n)
	if soak > 0.0:
		hero["ward"] -= soak
		n -= soak
		events.append({"kind": "warded", "amount": soak})
	hero["hp"] = maxf(0.0, hero["hp"] - n)
	var sp: Dictionary = d["special_power"]
	hero["power"] = minf(float(sp["max"]), hero["power"] + n * float(sp["per_hp_lost"]))
	events.append({"kind": "hero_hit", "amount": n, "text": label})
	if hero["hp"] <= 0.0:
		outcome = "lost"
	elif mode == "turns" or hero["busy"] <= 0.0:
		_check_low_slot()


func _frame(a: Dictionary, f: String) -> void:
	a["frame"] = f
	a["frame_t"] = float(d["attack_frame_time"])


# ── Bag ──────────────────────────────────────────────────────────────────────

func _draw_one() -> bool:
	if draw_pile.is_empty():
		draw_pile = discard.duplicate()
		discard.clear()
		_shuffle(draw_pile)
	if draw_pile.is_empty():
		return false
	hand.append(draw_pile.pop_back())
	return true


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


static func load_data() -> Dictionary:
	var f := FileAccess.open("res://data/fight.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())
