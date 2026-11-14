# Ira Domini («Гнев Господень» / «Мел и Соль») - prototype notes

A first playable prototype of GDD v6 as a Godot 4.7 project: one cathedral level, one demon, the full chalk rule set, four relics and the altar ending.

**Status: written and syntax-checked, but never run in Godot.** Expect some errors on the first run. If the Output or Debugger panel shows red text, copy it to Claude and it can be fixed.

## How to run

1. Unzip the folder.
2. Open Godot 4.7, press Import, pick `project.godot` inside the folder.
3. Wait for the import bar to finish (it converts the sounds), then press F5.

## Controls

| Key | Action |
|---|---|
| WASD / Shift | walk / run |
| Ctrl | crouch; next to a pew, column or altar you are hidden |
| Left mouse (hold) | draw chalk where you look on the floor |
| Right mouse (hold) | erase the circle you look at and get its chalk back |
| E | take a relic, put relics on the altar |
| R | restart with a new level |
| F3 | debug numbers (demon state, chalk, timers) |
| F4 | lights on and fog off, to inspect the level |
| F11 / Esc | full screen / free the mouse |

## What is in

- **Chalk:** 10 m supply, 2.5 m reach, silent. A line closes when it returns to its start or crosses itself. An unclosed line burns away. Erasing returns all of a circle's chalk. The chalk stick in your hand shortens instead of a meter.
- **The rule:** the demon never crosses a closed line. It is checked on every step it takes.
- **Demon:** Patrol, Investigate (waits 3 s), Chase (within 4 m or in its view cone), Blocked (leans on the line and screams, then leaves). Its red eye light shows where it looks. Candles go out as it passes.
- **Banishing:** hold it inside a closed circle for 50 s. Your chalk drops to zero and refills over one minute. The demon returns after a cooldown, far away and out of sight.
- **Health:** first hit wounds you for 20 s, second hit kills and rebuilds the level with a new seed.
- **Level:** narthex with a salt threshold, nave with pews, side aisles with columns, four chapels, pulpit with the prayer book, open crossing, altar with the unfinished circle and the body. The seed changes nave length, chapel positions, pulpit side.
- **Feel:** head bob, breathing, turn inertia, FOV 62 to 50, vignette, grain and colour fringing by demon distance, candle flicker, heartbeat, low hum, reversed choir in the crossing.
- **Style:** 480x270 render, vertex snapping, tiny code-made textures, fog, dithered colour banding. The demon (the Wailer), relics, candles and the body are pixel-splat models built in code.

## Choices made where the GDD is open

All numbers are in `scripts/tuning.gd`; the ones marked GUESS are these choices.

- **Scope:** one level, not five. It is the final-level type (with the altar), so the whole loop can be tested.
- **Final items:** the four level relics are the altar items.
- **Vision cone:** 35 degrees each side, 11 m.
- **Banish cooldown:** 40 s.
- **Hiding:** Ctrl only hides you within 1.3 m of cover. Hiding anywhere would make the demon harmless.
- **Erasing:** right mouse, held for 1 s. The GDD names no key.
- **Closing sound:** none, because the GDD says chalk is silent. A closed circle flashes instead.

## Not in the prototype

- Levels 2 to 5 and saving between levels.
- A raised pulpit (the floor is flat everywhere so chalk works the same in every room).
- The "close the gap with E" action: the altar gap closes by itself in the ending.
- Real animation: the demon's limbs swing in code.

## Files

- `scripts/tuning.gd` - every number. Start here.
- `scripts/chalk.gd` - drawing, closing, the rule.
- `scripts/demon.gd` - the state machine.
- `scripts/level.gd`, `nav.gd` - rooms and path finding.
- `scripts/models.gd`, `splat_builder.gd` - pixel-splat models.
- `shaders/` - PSX surface, splat, screen effect.
- `audio/` - synthesized placeholder sounds; `tools/make_audio.py` regenerates them.
