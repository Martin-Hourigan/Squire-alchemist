extends Node2D
## Shows one real-time fight (rules in fight.gd). Dungeon-crawler window: the
## enemy facing you, the hero's back in the foreground. Hero and enemy are
## PLACEHOLDER rectangles named after their asset and frame (idle / attack).
## Left: the hero (HP, special power, potions handed over, low-HP slot).
## Right: your bag (draw pile, discard, trickle, REDRAW).
## Bottom: your hand of ingredients and the flask.
## Mouse: click an ingredient to put it in the flask, click a flask ingredient
## to take it back, then HAND OVER or LOW-HP SLOT. Keys: 1-5, Q, W, R.
## Dev args: --seed <n>

const WIN := Rect2(212, 12, 536, 300)
const BACK := Rect2(400, 92, 160, 96)
const LEFT := Rect2(12, 12, 186, 300)
const RIGHT := Rect2(762, 12, 186, 300)
const CARD := Vector2(96, 150)
const HAND_POS := Vector2(12, 360)
const FLASK := Rect2(548, 330, 400, 198)
const STONE := Color("#3a3631")
const INK := Color("#f2ead6")
const DIM := Color("#8a8478")
const GOLD := Color("#c8a040")

var fight: Fight
var data: Dictionary
var _font: Font
var _floaters: Array = []    # {text, pos, t, col}
var _seed := 1


func _ready() -> void:
	_font = ThemeDB.fallback_font
	data = Fight.load_data()
	var args := OS.get_cmdline_args()
	var i := args.find("--seed")
	if i >= 0 and i + 1 < args.size():
		_seed = int(args[i + 1])
	_new_fight()


func _new_fight() -> void:
	fight = Fight.new()
	fight.setup(data, _seed)
	_seed += 1
	_floaters.clear()


func _process(dt: float) -> void:
	fight.step(dt)
	for ev in fight.events:
		_on_event(ev)
	fight.events.clear()
	for f in _floaters:
		f["t"] += dt
		f["pos"].y -= 22.0 * dt
	_floaters = _floaters.filter(func(f): return f["t"] < 1.3)
	queue_redraw()


func _on_event(ev: Dictionary) -> void:
	var enemy_at := _enemy_rect().get_center()
	var hero_at := _hero_rect().get_center() + Vector2(0, -40)
	match ev["kind"]:
		"enemy_hit":
			var txt := "-%d" % int(ev["amount"])
			if ev["text"] != "":
				txt = ev["text"] + " " + txt
			_float(txt, enemy_at + Vector2(randf_range(-30, 30), -20), Color("#ffd0a0"))
		"hero_hit":
			var txt2 := "-%d" % int(ev["amount"])
			if ev["text"] != "":
				txt2 = ev["text"] + " " + txt2
			_float(txt2, hero_at, Color("#ff7a6a"))
		"heal":
			var txt3 := "+%d HP" % int(ev["amount"])
			if ev["wasted"] > 0.0:
				txt3 += "  (%d wasted)" % int(ev["wasted"])
			_float(txt3, _side_at(ev["on"]) + Vector2(0, -18), Color("#8ae08a"))
		"power":
			var txt4 := "+%d power" % int(ev["amount"])
			if ev["on"] == "enemy":
				txt4 = "power: no effect"
			_float(txt4, _side_at(ev["on"]) + Vector2(0, -36), GOLD)
		"slow":
			_float("slowed %ds" % int(ev["amount"]), _side_at(ev["on"]) + Vector2(0, -54), Color("#7aa8ff"))
		"use":
			_float("the knight " + ev["text"], hero_at + Vector2(0, 20), INK)
		"windup":
			_float(ev["text"] + "!", enemy_at + Vector2(0, -30), Color("#ff9a50"))


func _side_at(side: String) -> Vector2:
	if side == "enemy":
		return _enemy_rect().get_center()
	return _hero_rect().get_center() + Vector2(0, -40)


func _float(text: String, pos: Vector2, col: Color) -> void:
	_floaters.append({"text": text, "pos": pos, "t": 0.0, "col": col})


# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_click(ev.position)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.keycode
		if fight.outcome != "":
			if k == KEY_R or k == KEY_SPACE or k == KEY_ENTER:
				_new_fight()
			return
		if k >= KEY_1 and k <= KEY_9:
			fight.add_to_flask(k - KEY_1)
		elif k == KEY_Q:
			fight.hand_over()
		elif k == KEY_W:
			fight.to_low_slot()
		elif k == KEY_R:
			fight.redraw()
		elif k == KEY_BACKSPACE:
			while not fight.flask.is_empty():
				fight.take_from_flask(0)


func _click(p: Vector2) -> void:
	if fight.outcome != "":
		_new_fight()
		return
	for i in fight.hand.size():
		if _card_rect(i).has_point(p):
			fight.add_to_flask(i)
			return
	for i in fight.flask.size():
		if _flask_slot(i).has_point(p):
			fight.take_from_flask(i)
			return
	if _btn_hand_over().has_point(p):
		fight.hand_over()
	elif _btn_low().has_point(p):
		fight.to_low_slot()
	elif _btn_redraw().has_point(p):
		fight.redraw()


# ── Layout ───────────────────────────────────────────────────────────────────

func _card_rect(i: int) -> Rect2:
	return Rect2(HAND_POS + Vector2(i * (CARD.x + 8), 0), CARD)


func _flask_slot(i: int) -> Rect2:
	return Rect2(FLASK.position + Vector2(16 + i * 66, 34), Vector2(58, 58))


func _btn_hand_over() -> Rect2:
	return Rect2(FLASK.position + Vector2(14, 140), Vector2(180, 44))


func _btn_low() -> Rect2:
	return Rect2(FLASK.position + Vector2(206, 140), Vector2(180, 44))


func _btn_redraw() -> Rect2:
	return Rect2(RIGHT.position + Vector2(12, 236), Vector2(RIGHT.size.x - 24, 44))


func _enemy_rect() -> Rect2:
	var r := Rect2(WIN.get_center().x + 10, 84, 130, 160)
	if fight.enemy["frame"] == "attack":
		r = r.grow(14)
		r.position.y += 16
	return r


func _hero_rect() -> Rect2:
	var r := Rect2(WIN.get_center().x - 190, WIN.end.y - 112, 150, 124)
	if fight.hero["frame"] == "attack":
		r.position.y -= 22
	return r


# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(960, 540)), Color("#17161a"))
	_draw_corridor()
	_draw_enemy()
	_draw_hero()
	_draw_frame()
	_draw_left()
	_draw_right()
	_draw_hand()
	_draw_flask()
	for f in _floaters:
		var a: float = clampf(1.3 - f["t"], 0.0, 1.0)
		_text_c(f["pos"], f["text"], 15, Color(f["col"], a))
	if fight.outcome != "":
		_draw_outcome()


func _draw_corridor() -> void:
	var w := WIN
	var b := BACK
	var tl := w.position
	var tr := Vector2(w.end.x, w.position.y)
	var bl := Vector2(w.position.x, w.end.y)
	var br := w.end
	var btl := b.position
	var btr := Vector2(b.end.x, b.position.y)
	var bbl := Vector2(b.position.x, b.end.y)
	var bbr := b.end
	draw_colored_polygon(PackedVector2Array([tl, tr, btr, btl]), Color("#1d1c1f"))
	draw_colored_polygon(PackedVector2Array([bl, bbl, bbr, br]), Color("#2a2724"))
	draw_colored_polygon(PackedVector2Array([tl, btl, bbl, bl]), Color("#34312d"))
	draw_colored_polygon(PackedVector2Array([tr, br, bbr, btr]), Color("#302d29"))
	draw_rect(b, Color("#0c0c0e"))
	var line := Color("#56504a")
	for k in range(1, 7):
		var u := float(k) / 7.0
		draw_line(tl.lerp(btl, u), bl.lerp(bbl, u), Color(line, 0.55 - u * 0.4), 1.0)
		draw_line(tr.lerp(btr, u), br.lerp(bbr, u), Color(line, 0.55 - u * 0.4), 1.0)
	for k in range(1, 6):
		var v := float(k) / 6.0
		draw_line(tl.lerp(bl, v), btl.lerp(bbl, v), Color(line, 0.35), 1.0)
		draw_line(tr.lerp(br, v), btr.lerp(bbr, v), Color(line, 0.35), 1.0)
	draw_line(tl, btl, line, 1.5)
	draw_line(tr, btr, line, 1.5)
	draw_line(bl, bbl, line, 1.5)
	draw_line(br, bbr, line, 1.5)
	draw_rect(b, line, false, 1.5)


func _draw_frame() -> void:
	var f := 8.0
	var o := WIN.grow(f)
	draw_rect(Rect2(o.position, Vector2(o.size.x, f)), STONE)
	draw_rect(Rect2(Vector2(o.position.x, WIN.end.y), Vector2(o.size.x, f)), STONE)
	draw_rect(Rect2(o.position, Vector2(f, o.size.y)), STONE)
	draw_rect(Rect2(Vector2(WIN.end.x, o.position.y), Vector2(f, o.size.y)), STONE)
	draw_rect(o, Color("#6a645a"), false, 1.5)


## Placeholder art: a rectangle with the asset's name in it.
func _placeholder(r: Rect2, asset: String, col: Color) -> void:
	draw_rect(r, col.darkened(0.55))
	draw_rect(r, col, false, 2.0)
	draw_line(r.position, r.end, Color(col, 0.25), 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(col, 0.25), 1.0)
	var w := _font.get_string_size(asset, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_rect(Rect2(r.get_center() - Vector2(w * 0.5 + 5, 11), Vector2(w + 10, 18)), Color(0.06, 0.06, 0.08, 0.85))
	_text_c(r.get_center() + Vector2(0, 3), asset, 13, INK)


func _draw_enemy() -> void:
	var e: Dictionary = fight.enemy
	var r := _enemy_rect()
	if e["hp"] <= 0.0:
		draw_rect(Rect2(r.position.x, r.end.y - 10, r.size.x, 10), Color("#7a5a8a").darkened(0.6))
		return
	_placeholder(r, "%s_%s" % [data["enemy"]["asset"], e["frame"]], Color("#9a7ab0"))
	var bar := Rect2(WIN.get_center().x - 90, 34, 180, 12)
	_bar(bar, e["hp"] / e["max"], Color("#c04a40"))
	_text_c(bar.get_center() + Vector2(0, 4), "%d / %d" % [int(e["hp"]), int(e["max"])], 11, INK)
	_text_c(Vector2(bar.get_center().x, bar.position.y - 6), data["enemy"]["asset"].to_upper(), 12, DIM)
	if e["winding"]:
		var wd: float = float(data["enemy"]["big_windup"])
		var wr := Rect2(WIN.get_center().x - 90, 54, 180, 10)
		_bar(wr, 1.0 - e["wind_t"] / wd, Color("#ff9a50"))
		_text_c(Vector2(wr.get_center().x, wr.end.y + 15), "%s  %d dmg  in %.1fs" % [
			data["enemy"]["big_name"], int(data["enemy"]["big_dmg"]), maxf(0.0, e["wind_t"])], 12, Color("#ffb070"))


func _draw_hero() -> void:
	var r := _hero_rect()
	if fight.hero["hp"] <= 0.0:
		draw_rect(Rect2(r.position.x, r.end.y - 14, r.size.x, 14), Color("#5a7ab0").darkened(0.6))
		return
	_placeholder(r, "%s_%s" % [data["hero"]["asset"], fight.hero["frame"]], Color("#5a8ac8"))


func _draw_left() -> void:
	_panel(LEFT)
	var x := LEFT.position.x + 12
	var w := LEFT.size.x - 24
	var y := LEFT.position.y + 22
	var h: Dictionary = fight.hero
	_text(Vector2(x, y), "THE KNIGHT", 14, INK)
	y += 18
	_text(Vector2(x, y), "HP", 11, DIM)
	_bar(Rect2(x, y + 4, w, 14), h["hp"] / h["max"], Color("#4aa050"))
	var low: float = h["max"] * float(data["low_hp_at"])
	var lx: float = x + w * float(data["low_hp_at"])
	draw_line(Vector2(lx, y + 2), Vector2(lx, y + 20), Color("#ffd060"), 1.5)
	_text_c(Vector2(x + w * 0.5, y + 15), "%d / %d" % [int(ceil(h["hp"])), int(h["max"])], 11, INK)
	y += 34
	var w_data: Dictionary = data["weapons"][data["hero"]["weapon"]]
	var pmax: float = float(data["special_power"]["max"])
	_text(Vector2(x, y), "SPECIAL: %s (%d)" % [w_data["special"], int(w_data["special_dmg"])], 11, DIM)
	_bar(Rect2(x, y + 4, w, 12), h["power"] / pmax, GOLD)
	y += 30
	_text(Vector2(x, y), "Attacks every %.1fs for %d" % [float(data["hero"]["attack_every"]), int(data["hero"]["attack_dmg"])], 11, DIM)
	y += 24
	_text(Vector2(x, y), "HANDED OVER (next chance)", 11, DIM)
	y += 6
	if fight.handed.is_empty():
		_text(Vector2(x, y + 16), "-", 12, DIM)
	for i in mini(fight.handed.size(), 4):
		_potion_row(Vector2(x, y + 4 + i * 20), fight.handed[i])
	y = LEFT.position.y + 214
	_text(Vector2(x, y), "LOW-HP SLOT (at %d HP)" % int(low), 11, Color("#ffd060"))
	var slot := Rect2(x, y + 6, w, 44)
	draw_rect(slot, Color("#24222a"))
	draw_rect(slot, Color("#ffd060", 0.6), false, 1.5)
	if fight.low_slot == null:
		_text_c(slot.get_center() + Vector2(0, 4), "empty", 12, DIM)
	else:
		_potion_row(slot.position + Vector2(6, 12), fight.low_slot)


func _potion_row(p: Vector2, pot: Dictionary) -> void:
	var cx := p.x + 6
	for id in pot["ings"]:
		draw_circle(Vector2(cx, p.y + 7), 6, Color(data["ingredients"][id]["col"]))
		cx += 14
	_text(Vector2(p.x + 46, p.y + 12), _fx_text(pot["fx"]), 10, _side_col(pot["target"]))


## "heal 14, special +40" from {effect: amount}.
func _fx_text(fx: Dictionary) -> String:
	var parts: Array = []
	for e in Fight.EFFECTS:
		if fx[e] > 0.0:
			parts.append(_fx_one(e, fx[e]))
	return ", ".join(parts)


func _fx_one(e: String, amount: float) -> String:
	return String(data["effects"][e]["fmt"]) % int(amount)


func _side_col(side: String) -> Color:
	if side == "enemy":
		return Color("#ffa060")
	return Color("#8ae08a")


func _draw_right() -> void:
	_panel(RIGHT)
	var x := RIGHT.position.x + 12
	var w := RIGHT.size.x - 24
	var y := RIGHT.position.y + 22
	_text(Vector2(x, y), "YOUR BAG", 14, INK)
	y += 22
	_text(Vector2(x, y), "Draw pile: %d" % fight.draw_pile.size(), 12, DIM)
	y += 18
	_text(Vector2(x, y), "Used (reshuffles): %d" % fight.discard.size(), 12, DIM)
	y += 18
	_text(Vector2(x, y), "Holding: %d / %d" % [fight.held(), int(data["hand_cap"])], 12, DIM)
	y += 30
	_text(Vector2(x, y), "NEXT INGREDIENT", 11, DIM)
	var full := fight.held() >= int(data["hand_cap"])
	_bar(Rect2(x, y + 4, w, 10), fight.trickle_t / float(data["trickle_every"]), Color("#7ab0d0"))
	if full:
		_text(Vector2(x, y + 30), "hand full - paused", 11, DIM)
	y += 62
	_text(Vector2(x, y), "REDRAW METER", 11, DIM)
	_bar(Rect2(x, y + 4, w, 10), fight.redraw_t / float(data["redraw_fill"]), Color("#b07ad0"))
	var ready := fight.redraw_ready()
	_button(_btn_redraw(), "REDRAW HAND  [R]", ready)


func _draw_hand() -> void:
	_text(HAND_POS + Vector2(0, -10), "INGREDIENTS - click to add to the flask  [1-5]", 12, DIM)
	for i in int(data["hand_cap"]):
		var r := _card_rect(i)
		if i >= fight.hand.size():
			draw_rect(r, Color("#ffffff", 0.04))
			draw_rect(r, Color("#ffffff", 0.1), false, 1.0)
			continue
		var ing: Dictionary = data["ingredients"][fight.hand[i]]
		var col := Color(ing["col"])
		draw_rect(r, Color("#24222a"))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), col)
		draw_circle(r.position + Vector2(r.size.x * 0.5, 54), 24, col)
		draw_arc(r.position + Vector2(r.size.x * 0.5, 54), 24, 0, TAU, 32, col.lightened(0.3), 1.5)
		_text_c(r.position + Vector2(r.size.x * 0.5, 100), ing["name"], 14, INK)
		_text_c(r.position + Vector2(r.size.x * 0.5, 120), _fx_one(ing["main"][0], ing["main"][1]), 11,
			_side_col(data["effects"][ing["main"][0]]["side"]))
		_text_c(r.position + Vector2(r.size.x * 0.5, 138), "2nd: " + _fx_one(ing["second"][0], ing["second"][1]), 10, DIM)
		var dim := not fight.can_add(i)
		draw_rect(r, Color(col, 0.35 if dim else 0.9), false, 1.5)
		if dim:
			draw_rect(r, Color(0, 0, 0, 0.35))
		_text(r.position + Vector2(5, 20), str(i + 1), 11, DIM)


func _draw_flask() -> void:
	_panel(FLASK)
	_text(FLASK.position + Vector2(14, 22), "FLASK  (%d-%d ingredients, click one to take it back)" % [
		int(data["flask_min"]), int(data["flask_max"])], 12, DIM)
	for i in int(data["flask_max"]):
		var r := _flask_slot(i)
		draw_rect(r, Color("#24222a"))
		draw_rect(r, Color("#ffffff", 0.18), false, 1.0)
		if i < fight.flask.size():
			var col := Color(data["ingredients"][fight.flask[i]]["col"])
			draw_circle(r.get_center(), 20, col)
	var brew := fight.flask_effects()
	# second effects under each slot: lit when another ingredient matches
	for i in fight.flask.size():
		var ing: Dictionary = data["ingredients"][fight.flask[i]]
		var on: bool = brew["second_on"][i]
		var lbl := "2nd off"
		if on:
			lbl = "2nd ON"
		_text_c(_flask_slot(i).get_center() + Vector2(0, 44), lbl, 10, Color("#8ae08a") if on else DIM)
	var x := FLASK.position.x + 216
	var y := FLASK.position.y + 46
	if brew["target"] == "":
		_text(Vector2(x, y), "empty", 13, DIM)
	else:
		var who := "drinks it  (the knight)"
		if brew["target"] == "enemy":
			who = "throws it  (at the brute)"
		_text(Vector2(x, y), "-> " + who, 12, _side_col(brew["target"]))
		y += 20
		for e in Fight.EFFECTS:
			if brew["fx"][e] > 0.0:
				_text(Vector2(x, y), _fx_one(e, brew["fx"][e]), 13, INK)
				y += 17
	_text(FLASK.position + Vector2(14, 130), "The FIRST ingredient decides who it's for; every effect lands there.", 10, DIM)
	_button(_btn_hand_over(), "HAND OVER  [Q]", fight.flask_ready())
	var slot_txt := "LOW-HP SLOT  [W]"
	if fight.low_slot != null:
		slot_txt = "SLOT IS FULL"
	_button(_btn_low(), slot_txt, fight.can_slot())


func _draw_outcome() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color(0, 0, 0, 0.6))
	var won := fight.outcome == "won"
	var title := "THE KNIGHT LOST"
	if won:
		title = "THE KNIGHT WON"
	_text_c(Vector2(480, 240), title, 32, GOLD if won else Color("#ff7a6a"))
	var sub := "%.0f seconds" % fight.t
	if won:
		sub += "  ·  %d / %d HP left" % [int(ceil(fight.hero["hp"])), int(fight.hero["max"])]
	_text_c(Vector2(480, 276), sub, 16, INK)
	_text_c(Vector2(480, 310), "click or R for another fight", 13, DIM)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _panel(r: Rect2) -> void:
	draw_rect(r, Color("#201e24"))
	draw_rect(r, Color("#4a4540"), false, 1.5)


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color("#0e0d10"))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Color("#ffffff", 0.15), false, 1.0)


func _button(r: Rect2, label: String, on: bool) -> void:
	draw_rect(r, Color("#3a3428") if on else Color("#24222a"))
	draw_rect(r, GOLD if on else Color("#ffffff", 0.12), false, 2.0 if on else 1.0)
	_text_c(r.get_center() + Vector2(0, 5), label, 13, INK if on else DIM)


func _text(p: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_c(p: Vector2, s: String, size: int, col: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
