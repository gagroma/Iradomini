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
| Ctrl or C | crouch; next to a pew, column or altar you are hidden |
| Left mouse (hold) | draw chalk where you look on the floor |
| Right mouse (hold) | erase the circle you look at and get its chalk back |
| E | take a relic; at the altar, put the next relic in its place; with all four placed, read the prayer |
| R | restart with a new level |
| F3 | debug numbers (demon state, chalk, timers) |
| F4 | lights on and fog off, to inspect the level |
| F11 | toggle fullscreen |
| Esc | pause or resume |

## What is in

- **Church art:** stained-glass lancets in every nave bay throwing coloured moonlight, walls of dressed stone blocks with damp, water stains and soot and a plinth along their foot, old wall painting on plaster (painted curtain, zigzag band, starry frieze, flaking off to the plaster), the fourteen Stations of the Cross, floors made in code (`shaders/psx_floor.gdshader`): limestone flags with a marble runner down the nave, grave slabs with carved crosses and worn inscriptions in the side aisles, a marble chequer round a Cosmatesque roundel in the crossing, red and grey marble lozenges in the apse, worn terracotta in the chapels - every slab settled a little, so candlelight skips across them, the walked path polished, grime in the joints, chipped corners and cracks, gold Byzantine-style mosaics in the apse that glitter in candlelight, and real old-master paintings in carved gilt frames: van Eyck's Crucifixion and Last Judgment in the crossing, Saint Michael casting down the devil on the altar, an altarpiece in every chapel. The paintings are public domain (The Met Open Access, CC0), listed in `assets/art/CREDITS.md`.
- **Chalk look:** lines are drawn like real chalk on stone (`shaders/chalk_line.gdshader`): smoothed hand curve, pressure and tremor, tapered ends, ragged edges, dry broken grain that belongs to the floor, streaks along the stroke, loose dust. Erasing smears it thinner.
- **Chalk:** 10 m supply, 2.5 m reach, silent. A line closes when it returns to its start or crosses itself. An unclosed line burns away. Erasing returns all of a circle's chalk. The chalk stick in your hand shortens instead of a meter.
- **The rule:** the demon never crosses a closed line. It is checked on every step it takes.
- **Demon:** Patrol, Investigate (waits 3 s), Chase (within 4 m or in its view cone), Blocked (leans on the line and screams, then leaves). Its red eye light shows where it looks. Candles go out as it passes.
- **Banishing:** close a circle round the demon (you outside it) and it comes apart at once. The circle stays on the floor, blazing gold for a moment; chalk in your hand slowly grows back by itself (empty to full in 90 s), but only up to what is not lying on the floor - rub circles out (right mouse) to get theirs back at once. The demon returns after a cooldown, far away and out of sight.
- **Stamina:** 5 s of running from full breath, won back while you walk or stand; run out and you cannot run again until it is back to 40%. A thin bar under the eye at the top shows it (red while winded), and you breathe harder.
- **Health:** first hit wounds you for 20 s, second hit kills and rebuilds the level with a new seed.
- **Level:** narthex with a salt threshold, nave with pews, side aisles with columns, four chapels, pulpit with the prayer book, open crossing, altar with the unfinished circle and the body. The seed changes nave length, chapel positions, pulpit side.
- **Feel:** head bob, breathing, turn inertia, FOV 62 to 50, vignette, grain and colour fringing by demon distance, candle flicker, heartbeat, low hum, reversed choir in the crossing.
- **The demon's body:** cut at its joints (pelvis, spine, head, upper arm, forearm, clawed hand, thigh, shin) and animated in code: a heavy stalking walk with bending knees and swaying hips, a hunched run with claws out, three attacks (left claw, right claw, both overhead) with a wind-up and a lunge, a scream with the head thrown back and arms flung wide, leaning on a chalk line with its claws scraping the air, looking round when it searches, a roar after it strikes, breathing and sudden twitches of the head. Every frame it measures where its claws, mouth, horns, elbows and feet really are and keeps that whole body off chalk lines. Its scream shakes your camera (hard up close), and so do its blows and its running steps.
- **Stealth you can see:** a pixel eye at the top of the screen is the demon's attention (closed: no idea; amber, half open: it heard something; red, wide open: it sees you, with a red throbbing edge round the screen). Sound arcs either side show each footstep (crouch 1, walk 2, run 4, more with relics) and flash red when the demon heard it. Crouching says "присел · рядом нет укрытия" or "СКРЫТ"; hidden, the view narrows and goes darker and colder. (`scripts/stealth_hud.gd`)
- **Hands:** your own hands in cassock sleeves (`tools/make_hands.py`): the left holds the chamberstick by its ring, the right pinches the chalk. Drawing, the right arm stretches out to the spot on the floor, chalk tip-first, trembling as it scrapes; rubbing a circle out, it scrubs from side to side. Both trail a little behind the turning head.
- **Hand candle:** a brass chamberstick modelled in Blender. The candle burns down over about 6.5 minutes (faster while running) and lifts higher as it gets shorter; at the end it sputters, goes out and smokes. Its flame is a ray-marched glowing gas that leans away from your movement on a spring, shrinks, tears and sheds sparks and soot when you run or turn fast, and shudders when the demon is near. Its light follows the flame.
- **Style:** 480x270 render, vertex snapping, tiny code-made textures, fog, dithered colour banding. The demon (the Wailer) and the relics are pixel-splat models built in code. The dead exorcist by the altar is a Blender model (`tools/make_exorcist.py`): a priest with a man's proportions in a cloth-simulated cassock, lying on his front with his back torn by claws, purple stole draped by cloth simulation, his last chalk in his reaching hand, blood under his head, his ritual book thrown open and a broken rosary; next to him three claw gouges in the stone. Candles on shelves, chapel tables and the altar are the same Blender chamberstick and flame as the hand candle, at different heights; they sway in a slow draft, shudder as the demon comes near and go out with a wisp of smoke.
- **Opening:** every level (room levels and the cathedral scenario alike, whose narthex now has a real arched front door) starts on a wet cobblestone road through a churchyard at night, leading to the stone west front of the church with lanterns either side of the open entrance door. In first person you walk up the road and in, turn, reach for the ring handle and push the door shut with a creak and a slam the demon hears. In the dark you go to a stack of crates in the corner, take your candle from it, pull a flip-lid lighter from your pocket, flick it open and light the wick, snap it shut and put it away, pick up the chalk lying next to it and turn to the way on; then you get control (`scripts/door_intro.gd`, outside in `scripts/exterior.gd` and `shaders/exterior_ground.gdshader`, creak and lighter sounds from `tools/make_scene_audio.py`, lighter in `scripts/lighter.gd`).
- **Cathedral scenario:** the cathedral is built in the same style as the rooms (kit stone block walls, flagstone floors, wall candles, the rooms' violet night). Its apse holds a statue on a stepped stone plinth; the altar with the old exorcist's circle is in its own room (`room2_end`), attached at random to the side wings, as far from the cathedral as it fits. Each placed relic still brightens the altar and draws the demon closer.
- **Altar ending:** each E at the altar plays a short first-person scene: you step up and set the next relic in its own fixed place (cross at the back, chalice left, censer right, prayer book in front). With all four placed, the next E makes you take the prayer book, open it and read the prayer to Saint Michael in Latin, line by line under the picture, muttered under your breath. On the second-to-last line the demon screams from the doorway and charges; you turn to it still reading, it rears up with its claws over you and is torn apart on "Amen" in a flash while the old chalk circle closes. You turn back, close the book, lower it and sigh, and a "You Win" panel in the pause-menu style offers Play Again or Quit to Title (`scripts/altar_scene.gd`, `scripts/prayer_book.gd`, `scripts/win_screen.gd`).
- **Levels:** five levels, set in `scripts/tuning.gd` (`LEVELS`, `LEVEL_DEMONS`, `LEVEL_EXTRA_ROOMS`). Each one adds rooms (2 more per level), adds a demon (1 up to 5, each starting at a different point on the patrol), places the relics further from the start and makes their glow dimmer. Finishing levels 1-4 opens a "Level N Cleared" screen with three random blessing cards (`scripts/blessing_screen.gd`, `scripts/blessing_card.gd`); picking one (click, or keys 1/2/3, or arrows and Enter) goes straight into the next level. From level 2 on, every cutscene (the opening, placing a relic, the prayer, the death sequence) shows "Enter · Skip" in the corner and Enter skips it (`scripts/skip_hint.gd`). Blessings last for the whole run and stack up to three times each (`scripts/boons.gd`): Blessed Medallion (the first blow in each church only staggers you), Deep Pockets (+3 m chalk), Chalk Dust (chalk regrows faster), Iron Lungs (+2 s running), Second Wind (breath returns faster), Soft Soles (quieter steps), Beeswax Candle (candle lasts longer), Fleet Foot (+10% speed), Quick Mending (wounds heal twice as fast), Long Arm (draw further away). After level 5 it is "You Win" with Play Again, which starts a fresh run at level 1. Dying or Restart Seed replays the same level and keeps your blessings; Quit to Title starts over with none.
- **Performance:** while a level loads, every material is drawn once behind a black screen under each lighting combination (`scripts/warmup.gd`), so nothing freezes the first time it appears. The outside area is freed once the entrance door shuts, each cathedral wall is one batched draw, models switch to lower detail sooner, and the view distance matches the fog.
- **Death:** once the demon starts a swing next to you, you cannot walk away; the blow lands. The killing blow plays in first person: you stagger, drop to your knees, slump and fall face down on the stone, while your candle clatters away still burning. The picture fades to black for half a second, then you see yourself from outside, face down with one hand reaching for the candle, on the side away from the demon. The camera slowly pulls back as the church sinks into darkness and "You Are Dead" is written over it in dripping red strokes. Killed right behind the backrest of a pew block, you instead stumble forward and fold over the backrest, legs behind on the floor, elbows on the seat and forearms lying forward along it (animation "die_pew"). The body is a rigged Blender model (`tools/make_player.py`): a priest in a cassock with stole, cincture, buttons and Roman collar, jointed fingers with nails, eyes, folds at the elbows, cuffs and waist, and a skirt that drapes flat once he lies down. Once the words are finished, everything but the lettering sinks into darkness and a Try Again button appears that starts a new level (`scripts/death_scene.gd`, `scripts/death_text.gd`).

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
- The "close the gap with E" action: the altar gap closes by itself when the prayer is finished.
- Real animation: the demon's limbs swing in code.

## Files

- `scripts/tuning.gd` - every number. Start here.
- `scripts/chalk.gd` - drawing, closing, the rule.
- `scripts/demon.gd` - the state machine.
- `scripts/level.gd`, `nav.gd` - rooms and path finding.
- `scripts/models.gd`, `splat_builder.gd` - pixel-splat models.
- `shaders/` - PSX surface, splat, screen effect.
- `audio/` - synthesized placeholder sounds; `tools/make_audio.py` regenerates them.
- `assets/art/` - paintings as small PS1-style textures, made by `tools/prepare_art.gd` from the originals in `tools/art_src/` (Met Open Access, CC0; sources and titles in `assets/art/CREDITS.md`). Frames, glass, mosaics and wall painting are made in code (`scripts/church_art.gd`, `shaders/`).
- `assets/models/` - models made in Blender, each rebuilt by its script: `blender --background --factory-startup --python tools/make_candle.py` (hand candle), `tools/make_pew.py` (oak pew with Gothic ends, book shelf and kneeler; shadows baked with Cycles into vertex colours). Models use `shaders/psx_model.gdshader`: the same vertex wobble as the walls, UV-mapped code-made textures (`textures.gd` `oak()`).
