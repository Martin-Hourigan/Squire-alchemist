# Squire (alchemist) - real-time combat slice

The hero fights by themselves in real time. You're their alchemist squire:
you never act directly, you brew potions from a bag of ingredients and hand
them over. (The turn-based slot/tile version is in ../Squire, untouched.)

## Two modes (2026-11-23), picked on the menu

- REAL-TIME: as below, except no ingredients arrive on their own. You start
  with a full hand of 5; the REDRAW meter (15 s) lets you replace your hand
  if you want to.
- TURN-BASED: your turn first - brew and hand over (one potion a turn; the
  hero uses it straight away), then END TURN. The Knight attacks (an enemy
  that showed BLOCK stops the first hit; a full special adds Big Slash as a
  second hit), then the brute does what it showed: ATTACK, BLOCK, or every
  4th turn a BIG SWING. The Knight always blocks, taking half. Then 2 more
  ingredients are drawn and power goes up a little. REDRAW every 3 turns.
  Slow = the slowed one hits for half, a turn per 2 s of slow.
  All turn numbers are in `data/fight.json` under "turns" (placeholders).

## Direction (2026-11-23, not built)

- The hero wears equipment in Diablo-style slots that you fill (not a
  Backpack Battles grid).
- Your cards aren't attacks or blocks: they're potions for the hero and their
  gear, e.g. poison for the weapon, an enchantment for the shield, healing.
- How brewing works: undecided.

## Phone

Public repo github.com/Martin-Hourigan/Squire-alchemist; the APK is on the
release page and the menu's update button installs new versions.
`build_apk.bat` builds `build/Squire-alchemist.apk`;
`python tools/release.py X.Y "notes"` publishes a new version.

## The slice (2026-10-18)

- One fight: the Knight vs a brute. Placeholder rectangles named after the
  asset and frame (idle / attack).
- The Knight attacks on a timer. Their sword's SPECIAL (Big Slash) fires when
  the power meter is full; power builds when they're hit and slowly over time.
- The brute attacks on a timer; every 4th attack is a telegraphed Big Swing.
- Your bag of ingredients is a deck (in real time: a full hand to start, no
  trickle any more). A slow REDRAW meter lets you press to swap your hand.
  Used ingredients reshuffle back in.
- Put 1-3 ingredients in the flask (instant brew), then:
  - HAND OVER - the Knight uses it the next time they're free (overhealing
    is wasted), or
  - LOW-HP SLOT - one potion, used when HP drops to 30%.

- Each ingredient has TWO effects (Elder Scrolls style):
  - MAIN - always counts, and copies of the same ingredient stack it.
  - SECOND - only counts if a DIFFERENT ingredient in the flask has the
    same effect.
  Red: heal 8 / 2nd special +15. Gold: special +25 / 2nd heal 6.
  Black: 8 damage / 2nd slow 3s. Blue: slow 4s / 2nd 5 damage.
- The FIRST ingredient's main effect decides who the potion is for: heal and
  special mean the Knight drinks it; damage and slow mean they throw it at
  the brute. Every effect lands on that target - a bad mix heals the brute
  or hurts the Knight.
- Slow: the target's timers run at half speed for that many seconds.

Every number is a PLACEHOLDER in `data/fight.json`.

## Controls

Click an ingredient to put it in the flask, click a flask ingredient to take
it back, click HAND OVER / LOW-HP SLOT / REDRAW. Keys: 1-5, Q (hand over),
W (low-HP slot), R (redraw), Space (end turn), Backspace (empty flask), Esc
or phone back (menu). After a fight: tap for another, or MENU.

## Files

- `data/fight.json` - all numbers, ingredients, the bag
- `scripts/fight.gd` - the rules (no drawing)
- `scripts/fight_view.gd` - the screen and input
- `tests/sim_test.gd` - headless bots:
  `godot --headless --path . --script res://tests/sim_test.gd`

Last run (two effects): idle 0%; single (every ingredient alone, at once)
100% / 30 HP left; mix (whatever's in hand, any order) 78% / 20 HP;
paired (matching pairs, low-HP potion) 99% / 32 HP.
