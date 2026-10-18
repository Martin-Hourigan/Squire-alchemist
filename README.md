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
- Your bag of ingredients is a deck: Red (heal), Black (thrown damage), Gold
  (special power). One ingredient trickles in every few seconds while you
  hold fewer than 5. A slow REDRAW meter lets you press to swap your hand.
  Used ingredients reshuffle back in.
- Put 1-3 ingredients in the flask (instant brew), then:
  - HAND OVER - the Knight uses it the next time they're free (overhealing
    is wasted), or
  - LOW-HP SLOT - one potion, used when HP drops to 30%.

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

Last run: idle (never brews) wins 0%; dump (hands every ingredient over as it
arrives) 100% with 29 HP left; simple (plans a low-HP potion) 100% with 28.
