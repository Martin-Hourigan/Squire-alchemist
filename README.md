# Squire (alchemist)

The hero fights by themselves. You're their alchemist squire: you never
fight, you brew potions from a bag of ingredients and hand them over. (The
older turn-based slot/tile version is in ../Squire, untouched.)

One fight: the Knight vs a brute. Placeholder rectangles named after the asset
and frame (idle / attack). The menu picks the mode.

## Brewing (both modes)

- Put 1-3 ingredients in the flask, then HAND OVER, or put it in the LOW-HP
  SLOT (used by itself when HP drops to 30%).
- Every potion is for the hero and their gear:
  - heal: HP back
  - shield ward: an enchantment on the shield that soaks up that much damage
  - venom: the blade is coated for that many hits; each hit adds 3 poison.
    Poison: the brute loses its poison in HP every tick (2 s, or once a
    turn), then the poison goes down by 1.
- Three ingredients that match a RECIPE brew that named potion (much
  stronger). Anything else - one ingredient alone, or a mix that isn't a
  recipe - is an UNNAMED potion: the ingredients' own effects added up.
- The RECIPE BOOK (BOOK button) shows what you know. You start with Healing
  Draught and Shield Oil. Brewing a recipe you didn't know still works and
  puts it in the book; winning a fight teaches one more. The book is saved
  on the device; FORGET RECIPES on the menu resets it.
- Ingredients: Redcap (heal 4), Ironbark (ward 4), Nightshade (venom 1 hit),
  Honey (heal 2). Recipes: Healing Draught, Shield Oil, Venom Oil, Iron Tonic,
  Bitter Edge (see data/fight.json).

## REAL-TIME

- The Knight attacks on a timer. Their sword's SPECIAL (Big Slash) fires when
  the power meter is full; power builds when they're hit and slowly over time.
- The brute attacks on a timer; every 4th attack is a telegraphed Big Swing.
- No ingredients arrive on their own: you start with a full hand of 5, and the
  REDRAW meter (15 s) lets you replace your hand if you want to.
- Handed-over potions are used the next time the Knight is free.

## TURN-BASED

- Your turn first: brew and hand over (one potion a turn; the Knight uses it
  straight away), then END TURN.
- The Knight attacks. A brute that showed BLOCK stops the first hit; a full
  special adds Big Slash as a second hit.
- Poison ticks, then the brute does what it showed: ATTACK, BLOCK, or every
  4th turn a BIG SWING. The Knight always blocks, taking half.
- Then 2 more ingredients are drawn and power goes up a little. REDRAW every
  3 turns.

Every number is a PLACEHOLDER in `data/fight.json` (shared, then "realtime"
and "turns").

## Direction (2026-11-23, not built)

- The hero wears equipment in Diablo-style slots that you fill (not a
  Backpack Battles grid).

## Controls

Tap/click an ingredient to put it in the flask, a flask ingredient to take it
back, then HAND OVER / LOW-HP SLOT / REDRAW / END TURN / BOOK. Keys: 1-5, Q
(hand over), W (low-HP slot), R (redraw), Space (end turn), B (book),
Backspace (empty flask), Esc or phone back (menu). After a fight: tap for
another, or MENU.

## Phone

Public repo github.com/Martin-Hourigan/Squire-alchemist; the APK is on the
release page and the menu's update button installs new versions.
`build_apk.bat` builds `build/Squire-alchemist.apk`;
`python tools/release.py X.Y "notes"` publishes a new version.

## Files

- `data/fight.json` - all numbers, ingredients, recipes, the bag
- `scripts/fight.gd` - the rules (no drawing)
- `scripts/fight_view.gd` - the menu, the screen and input, the book
- `scripts/update.gd` - checking GitHub for a newer release
- `tests/sim_test.gd` - headless bots in both modes:
  `godot --headless --path . --script res://tests/sim_test.gd`
