extends RefCounted
# TUNING - every number from the design document (GDD) lives here.
# Change a number, press Play, feel the difference. No other file needs editing.
# Source: "Gnev Gospoden" GDD v6. Lines marked GUESS are values the GDD
# leaves open ("utochnit na testakh"), so they are first guesses to test.

# --- Chalk (GDD: "Mel") ---
const CHALK_MAX := 10.0            # metres of chalk you carry
const CHALK_REACH := 2.5           # how far from your eyes you can draw
const CHALK_REGEN_TIME := 60.0     # seconds to refill after a banishing
const CLOSE_DISTANCE := 0.45       # GDD "closeDistance": how near the start the line must return to close
const MIN_LOOP_LENGTH := 2.0       # GDD "minLoopLength": shorter lines never count as a circle
const MIN_LOOP_AREA := 0.12        # GUESS: square metres; stops zero-size "circles"
const MIN_STEP := 0.06             # a new point is added every 6 cm of line
const MAX_STEP := 0.7              # if the aim jumps further than this, the line waits for you
const ERASE_TIME := 1.0            # GUESS: seconds of holding right mouse to wipe a circle
const LINE_WIDTH := 0.07

# --- Noise (GDD: "Vospriyatie") ---
const NOISE_STEP := 2.0            # a walking step is heard this far
const NOISE_RUN := 10.0            # a running step is heard this far
const NOISE_CROUCH := 0.8          # GUESS: crouch-walking is nearly silent
const NOISE_PER_RELIC_STEP := 1.0  # each relic you picked up adds this to walking noise
const NOISE_PER_RELIC_RUN := 2.0   # ...and this to running noise

# --- Player ---
const WALK_SPEED := 2.4            # GUESS
const RUN_SPEED := 5.0             # GUESS
const CROUCH_SPEED := 1.1          # GUESS
const COVER_DISTANCE := 1.3        # GUESS: crouch this close to a pew/column/altar to be hidden
const CRITICAL_TIME := 20.0        # seconds of the "wounded" state
const FOV_NORMAL := 62.0
const FOV_NEAR_DEMON := 50.0
const FEAR_DISTANCE := 12.0        # GUESS: demon closer than this starts the fear effects
const CANDLE_BURN_TIME := 400.0   # GUESS: seconds the candle in your hand lasts in still air
const CANDLE_WIND_BURN := 0.5      # GUESS: running makes it burn this much faster (0.5 = +50%)

# --- Demon ---
const DEMON_ENABLED := true           # false = the demon leaves for good (to look at the level in peace)
const DEMON_PATROL_SPEED := 1.5        # GUESS
const DEMON_INVESTIGATE_SPEED := 2.3   # GUESS
const DEMON_CHASE_SPEED := 4.3         # GUESS (slower than your run, faster than your walk)
const DEMON_CHASE_RADIUS := 4.0        # it chases if you are this close
const DEMON_CHASE_RADIUS_HIDDEN := 1.5 # GUESS: ...or this close while you hide
const DEMON_VISION_RANGE := 11.0       # GUESS (GDD: open question)
const DEMON_VISION_HALF_ANGLE := 35.0  # GUESS, degrees each side (GDD: open question)
const DEMON_INVESTIGATE_WAIT := 3.0    # seconds it waits at a noise
const DEMON_BLOCKED_TIME := 5.0        # GUESS: seconds it screams at a line before leaving
const DEMON_IGNORE_TIME := 12.0        # GUESS: seconds it leaves you alone after giving up
const DEMON_ATTACK_RANGE := 1.4        # GUESS
const DEMON_ATTACK_WINDUP := 0.35      # GUESS: warning time before a hit lands
const DEMON_ATTACK_COOLDOWN := 3.0     # GUESS
const DEMON_LOSE_TIME := 4.0           # GUESS: seconds without seeing you before it stops chasing
const BANISH_TIME := 50.0              # seconds the circle must hold the demon
const BANISH_COOLDOWN := 40.0          # GUESS (GDD: open question)
const RESPAWN_MIN_DISTANCE := 15.0     # GUESS: it never comes back closer than this

# --- Level ---
const RELICS_NEEDED := 4
# true = R.E.P.O.-style level from the 7 room templates (room_level.gd);
# false = the original hand-coded cathedral (level.gd)
const ROOM_LEVEL := true
