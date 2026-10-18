# Squire (alchemist) - real-time combat slice

The hero fights by themselves in real time. You're their alchemist squire:
you never act directly, you brew potions from a bag of ingredients and hand
them over. (The turn-based slot/tile version is in ../Squire, untouched.)

## The slice (2026-10-18)

- One fight: the Knight vs a brute. Placeholder rectangles named after the
  asset and frame (idle / attack).
- The Knight attacks on a timer. Their sword's SPECIAL (Big Slash) fires when
  the power meter is full; power builds when they're hit and slowly over time.
- The brute attacks on a timer; every 4th attack is a telegraphed Big Swing.
- Your bag of ingredients is a deck. One ingredient trickles in every few seconds while you
  hold fewer than 5. A slow REDRAW meter lets you press to swap your hand.
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
W (low-HP slot), R (redraw), Backspace (empty flask). After a fight: click
or R for another.

## Files

- `data/fight.json` - all numbers, ingredients, the bag
- `scripts/fight.gd` - the rules (no drawing)
- `scripts/fight_view.gd` - the screen and input
- `tests/sim_test.gd` - headless bots:
  `godot --headless --path . --script res://tests/sim_test.gd`

Last run (two effects): idle 0%; single (every ingredient alone, at once)
100% / 30 HP left; mix (whatever's in hand, any order) 78% / 20 HP;
paired (matching pairs, low-HP potion) 99% / 32 HP.
