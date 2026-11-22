class_name Fight
extends RefCounted
## The rules of one fight (no drawing here; fight_view.gd shows it), in one
## of two modes:
##   realtime - the hero fights on their own: attacks on a timer, fires the
##     weapon special when its power is full.
##   turns - your turn (brew, hand over, END TURN), then the hero attacks,
##     then the enemy does what it showed it would (attack, block, or a Big
##     Swing). An enemy that blocks stops the hero's first hit; the hero
##     always blocks the enemy's hit, so it lands at hero_block. You, the alchemist, hold ingredients drawn from your
## bag, put 1-3 in the flask and either HAND IT OVER (the hero uses it the next
## time they're free) or put it in the LOW-HP SLOT (used when HP drops low).
## Each ingredient has a MAIN effect (always counts, stacks with copies) and a
## SECOND effect (only counts if a different ingredient in the flask has the
## same effect). The FIRST effect in the flask decides the target: hero-side
## effects mean the hero drinks it, enemy-side ones mean they throw it - and
## every effect lands on that target, so a bad mix can heal the enemy.
## You start with a full hand; nothing arrives on its own in real time. A
## meter (seconds, or turns) lets you REDRAW: swap your whole hand. In turns,
## a couple more are drawn each turn. Used ingredients reshuffle back in.
## All numbers come from data/fight.json and are placeholders.

var d: Dictionary
var mode := "realtime"
var m: Dictionary  # d[mode]
var rng := RandomNumberGenerator.new()
var t := 0.0
var outcome := ""    # "", "won", "lost"

var hero := {}
var enemy := {}

var draw_pile: Array = []
var hand: Array = []       # ingredient ids
var flask: Array = []      # ingredient ids (still count toward the hand cap)
var discard: Array = []
var handed: Array = []     # potions waiting for the hero, used in order
var low_slot = null        # one potion or null
var redraw_t := 0.0  # seconds (realtime) or turns since the last redraw

# turns
var turn := 1
var phase := "you"  # you, hero (hero just attacked), enemy (enemy just acted)
var phase_t := 0.0
var potions_used := 0  # this turn
var intent := "attack"  # what the enemy will do: attack, big, block

## What happened since the view last looked: {kind, amount, text}.
var events: Array = []


func setup(data: Dictionary, seed_value: int, mode_ := "realtime") -> void:
	d = data
	mode = mode_
	m = d[mode]
	rng.seed = seed_value
	var h: Dictionary = d["hero"]
	hero = {"hp": float(h["hp"]), "max": float(h["hp"]), "power": 0.0, "slow": 0.0,
		"cd": float(h["attack_every"]), "busy": 0.0, "frame": "idle", "frame_t": 0.0}
	var e: Dictionary = d["enemy"]
	enemy = {"hp": float(e["hp"]), "max": float(e["hp"]), "cd": float(e["attack_every"]),
		"count": 0, "slow": 0.0, "winding": false, "wind_t": 0.0, "frame": "idle", "frame_t": 0.0}
	draw_pile = d["bag"].duplicate()
	_shuffle(draw_pile)
	for i in int(m["start_hand"]):
		_draw_one()
	if mode == "turns":
		_pick_intent()


# ── Your actions ─────────────────────────────────────────────────────────────

func held() -> int:
	return hand.size() + flask.size()


func can_add(i: int) -> bool:
	return outcome == "" and i >= 0 and i < hand.size() and flask.size() < int(d["flask_max"])


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


const EFFECTS := ["heal", "power", "damage", "slow"]


## What the flask would make right now: {target: "hero"/"enemy"/"", fx:
## {effect: amount}, second_on: [bool per flask ingredient]}.
func flask_effects(ids: Array = flask) -> Dictionary:
	var fx := {}
	for e in EFFECTS:
		fx[e] = 0.0
	var second_on: Array = []
	for i in ids.size():
		var ing: Dictionary = d["ingredients"][ids[i]]
		fx[ing["main"][0]] += float(ing["main"][1])
		var on := _second_matches(ids, i)
		second_on.append(on)
		if on:
			fx[ing["second"][0]] += float(ing["second"][1])
	var target := ""
	if not ids.is_empty():
		target = String(d["effects"][d["ingredients"][ids[0]]["main"][0]]["side"])
	return {"target": target, "fx": fx, "second_on": second_on}


## Does another, different ingredient in the flask share ids[i]'s second effect?
func _second_matches(ids: Array, i: int) -> bool:
	var want: String = d["ingredients"][ids[i]]["second"][0]
	for j in ids.size():
		if ids[j] == ids[i]:
			continue
		var other: Dictionary = d["ingredients"][ids[j]]
		if other["main"][0] == want or other["second"][0] == want:
			return true
	return false


func _brew() -> Dictionary:
	var p := flask_effects()
	p["ings"] = flask.duplicate()
	p["second_on"] = p["second_on"].duplicate()
	discard.append_array(flask)
	flask.clear()
	return p


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
	_hero_step(dt)
	if outcome == "":
		_enemy_step(dt)


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
		_hurt_enemy(hits[i][0] * _weak(hero), hits[i][1])
		if outcome != "":
			return


func _enemy_acts() -> void:
	var e: Dictionary = d["enemy"]
	var cut := float(m["hero_block"]) * _weak(enemy)
	match intent:
		"attack": _hurt_hero(float(e["attack_dmg"]) * cut, "blocked")
		"big": _hurt_hero(float(e["big_dmg"]) * cut, String(e["big_name"]) + ", blocked")
		"block": events.append({"kind": "windup", "text": "guards"})


func _new_turn() -> void:
	turn += 1
	phase = "you"
	potions_used = 0
	redraw_t = minf(redraw_need(), redraw_t + 1.0)
	for a in [hero, enemy]:
		a["slow"] = maxf(0.0, a["slow"] - 1.0)
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


## Turns: a slowed actor hits for slow_factor.
func _weak(a: Dictionary) -> float:
	return float(d["slow_factor"]) if a["slow"] > 0.0 else 1.0


func _hero_step(dt: float) -> void:
	var sp: Dictionary = d["special_power"]
	hero["power"] = minf(float(sp["max"]), hero["power"] + float(sp["per_second"]) * dt)
	hero["busy"] -= dt
	hero["cd"] -= dt * _speed(hero, dt)
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
			_hurt_enemy(float(w["special_dmg"]), String(w["special"]) + "!")
		else:
			_hurt_enemy(float(d["hero"]["attack_dmg"]), "")


func _check_low_slot() -> bool:
	if low_slot != null and hero["hp"] <= hero["max"] * float(d["low_hp_at"]):
		var p: Dictionary = low_slot
		low_slot = null
		_use(p, "low-HP slot")
		return true
	return false


## The hero uses a potion: drinks it if its target is the hero, throws it if
## it's the enemy. Every effect lands on that target.
func _use(p: Dictionary, from: String = "") -> void:
	hero["busy"] = float(d["hero"]["drink_time"])
	var on_hero: bool = p["target"] == "hero"
	var verb := "throws it"
	if on_hero:
		verb = "drinks"
	events.append({"kind": "use", "text": verb + (" (" + from + ")" if from != "" else ""), "on": p["target"]})
	var who: Dictionary = enemy
	if on_hero:
		who = hero
	var fx: Dictionary = p["fx"]
	if fx["heal"] > 0.0:
		var before: float = who["hp"]
		who["hp"] = minf(who["max"], who["hp"] + fx["heal"])
		events.append({"kind": "heal", "on": p["target"], "amount": who["hp"] - before, "wasted": fx["heal"] - (who["hp"] - before)})
	if fx["power"] > 0.0:
		if on_hero:
			hero["power"] = minf(float(d["special_power"]["max"]), hero["power"] + fx["power"])
		# PLACEHOLDER: the enemy has no special, so power thrown at it does nothing
		events.append({"kind": "power", "on": p["target"], "amount": fx["power"]})
	if fx["slow"] > 0.0:
		# turns: slow lasts a turn per slow_turn_secs of it
		who["slow"] += fx["slow"] if mode == "realtime" else ceilf(fx["slow"] / float(m["slow_turn_secs"]))
		events.append({"kind": "slow", "on": p["target"], "amount": fx["slow"]})
	if fx["damage"] > 0.0:
		if on_hero:
			_hurt_hero(fx["damage"], "own potion", false)
		else:
			_hurt_enemy(fx["damage"], "")


## Time multiplier for a slowed actor (slow counts down in real time).
func _speed(a: Dictionary, dt: float) -> float:
	if a["slow"] <= 0.0:
		return 1.0
	a["slow"] = maxf(0.0, a["slow"] - dt)
	return float(d["slow_factor"])


func _enemy_step(dt: float) -> void:
	var e: Dictionary = d["enemy"]
	dt *= _speed(enemy, dt)
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


func _hurt_enemy(n: float, label: String) -> void:
	enemy["hp"] = maxf(0.0, enemy["hp"] - n)
	events.append({"kind": "enemy_hit", "amount": n, "text": label})
	if enemy["hp"] <= 0.0:
		outcome = "won"


func _hurt_hero(n: float, label: String, by_enemy: bool = true) -> void:
	if by_enemy:
		_frame(enemy, "attack")
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
