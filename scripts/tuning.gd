extends RefCounted
# TUNING - every number from the design document (GDD) lives here.
# Change a number, press Play, feel the difference. No other file needs editing.
# Source: "Gnev Gospoden" GDD v6. Lines marked GUESS are values the GDD
# leaves open ("utochnit na testakh"), so they are first guesses to test.

# --- Chalk (GDD: "Mel") ---
const CHALK_MAX := 10.0            # metres of chalk you carry
const CHALK_REACH := 2.5           # how far from your eyes you can draw
const CHALK_REGEN_TIME := 90.0     # GUESS: seconds for an empty hand to fill up again by itself
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
const STAMINA_MAX := 5.0           # GUESS: seconds of running from full breath
const STAMINA_REGEN := 0.7         # GUESS: seconds of running won back per second of not running
const STAMINA_RECOVER := 0.4       # out of breath: no running until stamina is back to 40%
const CROUCH_SPEED := 1.1          # GUESS
const COVER_DISTANCE := 1.3        # GUESS: crouch this close to a pew/column/altar to be hidden
const CRITICAL_TIME := 20.0        # seconds of the "wounded" state
const FOV_NORMAL := 62.0
const FOV_NEAR_DEMON := 50.0
const FEAR_DISTANCE := 12.0        # GUESS: demon closer than this starts the fear effects
const CANDLE_BURN_TIME := 400.0   # GUESS: seconds the candle in your hand lasts in still air
const CANDLE_WIND_BURN := 0.5      # GUESS: running makes it burn this much faster (0.5 = +50%)

# --- Demon ---
const DEMON_ENABLED := true            # false = the demon leaves for good (to look at the level in peace)
const DEMON_PATROL_SPEED := 1.5        # GUESS
const DEMON_INVESTIGATE_SPEED := 2.3   # GUESS
const DEMON_CHASE_SPEED := 4.3         # GUESS (slower than your run, faster than your walk)
const DEMON_CHASE_RADIUS := 4.0        # it chases if you are this close
const DEMON_CHASE_RADIUS_HIDDEN := 1.5 # GUESS: ...or this close while you hide
const DEMON_VISION_RANGE := 11.0       # GUESS (GDD: open question)
const DEMON_VISION_HALF_ANGLE := 35.0  # GUESS, degrees each side (GDD: open question)
const DEMON_INVESTIGATE_WAIT := 3.0    # seconds it waits at a noise
const DEMON_BLOCKED_TIME := 5.0        # GUESS: seconds it screams at a line before leaving
const DEMON_GIVE_UP_TIME := 25.0       # GUESS: after a circle beats it, it leaves and ignores you this long
const DEMON_SHIELD_RANGE := 7.0        # GUESS: sees you in a circle this close: goes straight to the line, no circling
const DEMON_RETREAT_DISTANCE := 14.0    # GUESS: ...and while leaving it keeps to patrol points at least this far from you
const DEMON_RETREAT_NOTICE := 2.0      # GUESS: ...unless you walk this close to it
const DEMON_IGNORE_TIME := 12.0        # GUESS: seconds it leaves you alone after giving up
const DEMON_ATTACK_RANGE := 1.4        # GUESS
const DEMON_ATTACK_WINDUP := 0.35      # GUESS: warning time before a hit lands
const DEMON_ATTACK_COOLDOWN := 3.0     # GUESS
const DEMON_LOSE_TIME := 4.0           # GUESS: seconds without seeing you before it stops chasing
const BANISH_COOLDOWN := 40.0          # GUESS (GDD: open question)
const RESPAWN_MIN_DISTANCE := 15.0     # GUESS: it never comes back closer than this
const DEMON_START_GRACE := 8.0        # GUESS: seconds after you get control in which it cannot see you or hear you walk (running is always heard)
const DOOR_SLAM_DISTANCE := 16.0       # GUESS: the door slam draws it this far down the nave, not to your door

# --- Level ---
const RELICS_NEEDED := 4
const LEVELS := 5
const LEVEL_DEMONS := [1, 2, 3, 4, 5]
const SHOTGUN_STUN := 10.0
const SHOTGUN_STUN_PER_LEVEL := 1.0
const SHOTGUN_RANGE := 14.0
const SHOTGUN_LOUDNESS := 30.0
const LEVEL_EXTRA_ROOMS := [0, 2, 4, 6, 8]
# true = R.E.P.O.-style level from the 7 room templates (room_level.gd);
# false = the original hand-coded cathedral (level.gd)
const ROOM_LEVEL := true
const CATHEDRAL_SCENARIO := true

# --- Passage (the walk between two churches, scripts/passage.gd) ---
const PASSAGE_CELLS := 42                  # length of the first road (before level 2) in 2 m cells (84 m)
const PASSAGE_CELLS_PER_LEVEL := 5         # each later level adds this many cells
const PASSAGE_WALK_SPEED := 1.4            # m/s, W held
const PASSAGE_FIRST_QUIET := 6.0           # seconds before it first comes
const PASSAGE_QUIET_MIN := 5.0             # quiet spell between its visits (seconds)...
const PASSAGE_QUIET_MAX := 10.0
const PASSAGE_QUIET_PER_LEVEL := 1.0       # ...shorter by this much every level (never below 2.5 s)
const PASSAGE_THING_SPEED := 2.6           # how fast it drifts along the passage (m/s)
const PASSAGE_THING_SPEED_PER_LEVEL := 0.35
const PASSAGE_LISTEN_MIN := 2.5            # how long it lingers beside you, listening (seconds)
const PASSAGE_LISTEN_MAX := 4.0
const PASSAGE_LISTEN_PER_LEVEL := 0.4
const PASSAGE_DANGER_DISTANCE := 7.0       # closer than this it can hear you walk
const PASSAGE_NOTICE_TIME := 0.45          # seconds of walking within that distance before it finds you
const PASSAGE_CANDLE_DIM := 0.15            # your candle's brightness (x full) when it is right beside you
const PASSAGE_STAND_CATCH := 2.2           # walk this close to it when it stands on the road and it has you
const PASSAGE_STAND_WAIT := 3.0            # seconds you must stand still before it walks off the road (+ up to 1.5)
const PASSAGE_GUST_MIN := 10.0             # seconds between gusts of wind...
const PASSAGE_GUST_MAX := 22.0
const PASSAGE_GUST_PER_LEVEL := 2.0        # ...shorter by this much every level (never below 8 s)
const PASSAGE_GUST_BLOWOUT := 0.5          # chance a gust takes your light (otherwise it only shakes and dims it)
const PASSAGE_LISTEN_BLOWOUT := 0.7        # chance your light dies when it comes to listen beside you
const PASSAGE_RELIGHT_TIME := 1.3          # seconds to strike a light (F); you cannot walk meanwhile
const PASSAGE_MATCH_HEARING := 14.0        # it hears a light being struck from this far and comes to you
const PASSAGE_RELIGHT_SCARE := 0.5         # chance (once per walk) that it stands in front of you when the flame catches


# The level you are on (1 = the first church). Set by the menu, raised after each altar ritual.
# The passage between levels is played before levels 2, 3, ... (not before the first church).
static func level_number() -> int:
	return int(Engine.get_meta("ira_level", 1))
