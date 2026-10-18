class_name Fight
extends RefCounted
## The rules of one real-time fight (no drawing here; fight_view.gd shows it).
## The hero fights on their own: attacks on a timer, fires the weapon special
## when its power is full. You, the alchemist, hold ingredients drawn from your
## bag, put 1-3 in the flask and either HAND IT OVER (the hero uses it the next
## time they're free) or put it in the LOW-HP SLOT (used when HP drops low).
## Ingredients trickle in one at a time; a slowly filling meter lets you press
## REDRAW to swap your whole hand. Used ingredients reshuffle back into the bag.
## All numbers come from data/fight.json and are placeholders.

var d: Dictionary
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
var trickle_t := 0.0
var redraw_t := 0.0

## What happened since the view last looked: {kind, amount, text}.
var events: Array = []


func setup(data: Dictionary, seed_value: int) -> void:
	d = data
	rng.seed = seed_value
	var h: Dictionary = d["hero"]
	hero = {"hp": float(h["hp"]), "max": float(h["hp"]), "power": 0.0,
		"cd": float(h["attack_every"]), "busy": 0.0, "frame": "idle", "frame_t": 0.0}
	var e: Dictionary = d["enemy"]
	enemy = {"hp": float(e["hp"]), "max": float(e["hp"]), "cd": float(e["attack_every"]),
		"count": 0, "winding": false, "wind_t": 0.0, "frame": "idle", "frame_t": 0.0}
	draw_pile = d["bag"].duplicate()
	_shuffle(draw_pile)
	for i in int(d["start_hand"]):
		_draw_one()


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


func hand_over() -> bool:
	if not flask_ready():
		return false
	handed.append(_brew())
	return true


func can_slot() -> bool:
	return flask_ready() and low_slot == null


func to_low_slot() -> bool:
	if not can_slot():
		return false
	low_slot = _brew()
	return true


func redraw_ready() -> bool:
	return outcome == "" and redraw_t >= float(d["redraw_fill"])


## Discard the hand (not the flask) and draw a full one.
func redraw() -> bool:
	if not redraw_ready():
		return false
	discard.append_array(hand)
	hand.clear()
	while held() < int(d["hand_cap"]) and _draw_one():
		pass
	redraw_t = 0.0
	trickle_t = 0.0
	return true


## What the flask would make right now: {heal, damage, power}.
func flask_effects(ids: Array = flask) -> Dictionary:
	var fx := {"heal": 0.0, "damage": 0.0, "power": 0.0}
	for id in ids:
		var ing: Dictionary = d["ingredients"][id]
		fx[ing["effect"]] += float(ing["amount"])
	return fx


func _brew() -> Dictionary:
	var p := flask_effects()
	p["ings"] = flask.duplicate()
	discard.append_array(flask)
	flask.clear()
	return p


# ── Time ─────────────────────────────────────────────────────────────────────

func step(dt: float) -> void:
	if outcome != "":
		return
	t += dt
	# ingredients: trickle while there's room; redraw meter fills
	if held() < int(d["hand_cap"]):
		trickle_t += dt
		if trickle_t >= float(d["trickle_every"]):
			trickle_t = 0.0
			_draw_one()
	else:
		trickle_t = 0.0
	redraw_t = minf(float(d["redraw_fill"]), redraw_t + dt)
	for a in [hero, enemy]:
		a["frame_t"] -= dt
		if a["frame_t"] <= 0.0:
			a["frame"] = "idle"
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


## The hero drinks (or, for a pure damage potion, throws) a potion.
func _use(p: Dictionary, from: String = "") -> void:
	hero["busy"] = float(d["hero"]["drink_time"])
	var verb := "drinks"
	if p["heal"] == 0.0 and p["power"] == 0.0:
		verb = "throws"
	events.append({"kind": "use", "text": verb + (" (" + from + ")" if from != "" else "")})
	if p["heal"] > 0.0:
		var before: float = hero["hp"]
		hero["hp"] = minf(hero["max"], hero["hp"] + p["heal"])
		events.append({"kind": "heal", "amount": hero["hp"] - before, "wasted": p["heal"] - (hero["hp"] - before)})
	if p["power"] > 0.0:
		hero["power"] = minf(float(d["special_power"]["max"]), hero["power"] + p["power"])
		events.append({"kind": "power", "amount": p["power"]})
	if p["damage"] > 0.0:
		_hurt_enemy(p["damage"], "")


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


func _hurt_enemy(n: float, label: String) -> void:
	enemy["hp"] = maxf(0.0, enemy["hp"] - n)
	events.append({"kind": "enemy_hit", "amount": n, "text": label})
	if enemy["hp"] <= 0.0:
		outcome = "won"


func _hurt_hero(n: float, label: String) -> void:
	_frame(enemy, "attack")
	hero["hp"] = maxf(0.0, hero["hp"] - n)
	var sp: Dictionary = d["special_power"]
	hero["power"] = minf(float(sp["max"]), hero["power"] + n * float(sp["per_hp_lost"]))
	events.append({"kind": "hero_hit", "amount": n, "text": label})
	if hero["hp"] <= 0.0:
		outcome = "lost"
	elif hero["busy"] <= 0.0:
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
