"""(Ira Domini game version) Generates the 7 cathedral room templates for the level generator, plus the prop groups they are dressed with.

  scenes/groups/<group>.tscn            prop groups (R.E.P.O.-style), spawned into room slots at random
  scenes/rooms/shell/<room>.tscn        kit shell only: walls, floors, ceilings, windows, door slots, lights,
                                        and the empty prop slots (spawner switched off)
  scenes/rooms/dressed/<room>.tscn      the same room + its fixed set pieces + the spawner switched on
  scripts/room_templates.gd             door slots, sizes and kinds of every room, read by room_level.gd

Game rules kept here: floors stay flat (no dais, no carpets: chalk is drawn on the floor), relics are
placed by room_level.gd (the spawner places no artifacts), no shadows on room lights (GL Compatibility).

Coordinates are written Blender-style (x right, y = forward/back, z up, metres) and converted to Godot:
Godot = (bx, bz, -by); a rotation of a degrees about Blender Z = a degrees about Godot Y.
Grid: 2 m cells, walls on cell lines. A room nx x ny cells spans x -nx..nx, y -ny..ny (metres).
Wall segments are named <side><index>: N/S sides counted west->east, W/E sides counted south->north.

Run from the project folder:  python tools/build_rooms.py
Re-running overwrites these generated scenes (hand edits belong in copies).
"""
import math, os, random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT, PROP = "res://assets/kit/", "res://assets/props/"
rnd = random.Random(1234)


# NOTE: Godot writes Transform3D(...) in .tscn files ROW by row:
#   Transform3D(x.x, y.x, z.x,  x.y, y.y, z.y,  x.z, y.z, z.z,  origin)
# (the first three numbers are the first components of the x, y and z axes).
def tf(bx, by, bz=0.0, rot=0.0):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    # rotation about Y by rot: axes x = (c, 0, -s), y = (0, 1, 0), z = (s, 0, c)
    v = [c, 0, s, 0, 1, 0, -s, 0, c, bx, bz, -by]
    return "Transform3D(" + ", ".join(f"{x:.5g}" for x in v) + ")"


def tfs(bx, by, bz=0.0, rot=0.0, sx=1.0):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    # as tf(), with the model's own x axis scaled by sx: x = (c*sx, 0, -s*sx)
    v = [c * sx, 0, s, 0, 1, 0, -s * sx, 0, c, bx, bz, -by]
    return "Transform3D(" + ", ".join(f"{x:.5g}" for x in v) + ")"


def look_tf(pos, target):
    px, py, pz = pos; tx, ty, tz = target
    z = [px - tx, py - ty, pz - tz]; n = math.sqrt(sum(a * a for a in z)); z = [a / n for a in z]
    x = [z[2], 0.0, -z[0]]; n = math.sqrt(sum(a * a for a in x)); x = [a / n for a in x]
    y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
    rows = [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]]
    return "Transform3D(" + ", ".join(f"{a:.5g}" for a in rows + [px, py, pz]) + ")"


def g(bx, by, bz=0.0):          # Blender point -> Godot tuple
    return (bx, bz, -by)


class Scene:
    """Tiny .tscn writer."""
    def __init__(self, root, typ="Node3D", script=None, meta=None):
        self.ext = {}; self.nodes = []
        extra = []
        if script: extra.append(f'script = ExtResource("{self.res(script, "Script")}")')
        for k, v in (meta or {}).items(): extra.append(f"metadata/{k} = {v}")
        self.nodes.append(f'[node name="{root}" type="{typ}"]' + ("\n" + "\n".join(extra) if extra else ""))

    def res(self, path, typ="PackedScene"):
        if path not in self.ext: self.ext[path] = (f"r{len(self.ext) + 1}", typ)
        return self.ext[path][0]

    def node(self, name, typ, parent=".", **props):
        lines = [f'[node name="{name}" type="{typ}" parent="{parent}"]']
        for k, v in props.items():
            if k == "script": v = f'ExtResource("{self.res(v, "Script")}")'
            lines.append(f"{k} = {v}")
        self.nodes.append("\n".join(lines))

    def inst(self, name, path, parent=".", transform=None, **props):
        lines = [f'[node name="{name}" parent="{parent}" instance=ExtResource("{self.res(path)}")]']
        if transform: lines.append(f"transform = {transform}")
        for k, v in props.items(): lines.append(f"{k} = {v}")
        self.nodes.append("\n".join(lines))

    def write(self, path):
        head = f"[gd_scene load_steps={len(self.ext) + 1} format=3]\n\n"
        ext = "\n".join(f'[ext_resource type="{t}" path="{p}" id="{i}"]' for p, (i, t) in self.ext.items())
        full = os.path.join(ROOT, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf8") as f:
            f.write(head + ext + "\n\n" + "\n\n".join(self.nodes) + "\n")


# ======================================================================= prop groups
# Group frame: origin at the slot. For wall/deco/narrow groups the slot sits on the wall face and local -Y
# (Blender) points into the room, so things are placed at negative y. Corner/center groups are centred.
# entries: (asset, x, y, z, rot)       item spots: (x, y, z)
GROUPS = {
    "wall_bookshelf":   ([("bookshelf", 0, -0.22, 0, 0), ("book_stack", 0.68, -0.35, 0, 25)], [(0.25, -0.2, 2.02)]),
    "wall_wardrobe":    ([("wardrobe", 0, -0.33, 0, 0)], []),
    "wall_study":       ([("chalktable", 0, -0.3, 0, 0), ("chair", 0.12, -0.85, 0, 172), ("candles", -0.27, -0.33, 0.74, 0)], [(0.22, -0.3, 0.7575)]),
    "wall_storage":     ([("crates", -0.42, -0.36, 0, 6), ("urns", 0.5, -0.42, 0, 0), ("saltsack", 0.1, -1.0, 0, 35)], [(0.45, -0.98, 0)]),
    "wall_lectern":     ([("lectern", 0, -0.45, 0, 0), ("candelabrum", 0.62, -0.3, 0, 0)], []),
    "wall_statue":      ([("statue", 0, -0.42, 0, 0)], []),
    "wall_shrine":      ([("cross", 0, -0.06, 3.3, 0), ("candle_single", 0.45, -0.25, 0, 0), ("skull", -0.4, -0.3, 0, 20)], [(0.0, -0.3, 0)]),
    "narrow_urns":      ([("urns", 0, -0.35, 0, 0)], []),
    "narrow_sack":      ([("saltsack", 0, -0.35, 0, 20)], []),
    "narrow_candelabrum": ([("candelabrum", 0, -0.3, 0, 0)], []),
    "narrow_bones":     ([("bones", 0, -0.25, 0, 0), ("skull", 0.35, -0.2, 0, 40), ("lantern", -0.35, -0.2, 0, 10)], []),
    "deco_sconce":      ([("sconce", 0, -0.02, 2.1, 0)], []),
    "deco_banner":      ([("banner", 0, -0.13, 3.85, 0)], []),
    "corner_crates":    ([("crates", 0, 0, 0, 0)], [(0.0, 0.0, 1.06)]),
    "corner_candelabrum": ([("candelabrum", 0, 0, 0, 0)], []),
    "corner_urns":      ([("urns", 0, 0, 0, 0)], []),
    "corner_sack":      ([("saltsack", 0, 0, 0, 0), ("bottle_round", 0.35, 0.25, 0, 0)], []),
    "center_rug":       ([("lantern", 0.55, 0.35, 0, 20), ("book_stack", -0.5, -0.3, 0, 10), ("pages", 0.0, 0.0, 0, 0), ("candle_single", 0.3, -0.4, 0, 0)], [(-0.1, 0.25, 0.0)]),
    "center_tomb":      ([("tomb", 0, 0, 0, 0)], []),
    "center_font":      ([("font", 0, 0, 0, 0)], []),
    "center_candles":   ([("candles", 0, 0, 0, 0), ("bones", 0.45, 0.3, 0, 40), ("skull", -0.4, 0.25, 0, 200), ("pages", 0.2, -0.45, 0, 0)], [(0.0, -0.3, 0)]),
    "center_statue":    ([("statue", 0, 0, 0, 0)], []),
}
NO_COLLIDE = {"banner", "chandelier", "pages", "carpet_rug", "carpet_runner"}

for name, (entries, spots) in GROUPS.items():
    sc = Scene(name)
    for k, (asset, x, y, z, r) in enumerate(entries):
        nm = ("NoCollide_" if asset in NO_COLLIDE else "") + f"{asset}_{k}"
        sc.inst(nm, PROP + asset + ".glb", ".", tf(x, y, z, r))
    for k, (x, y, z) in enumerate(spots):
        sc.node(f"ItemSpot_{k}", "Marker3D", ".", transform=tf(x, y, z))
    sc.write(f"scenes/groups/{name}.tscn")

# ======================================================================= rooms
SIDES = {  # side: (rot, inward direction)
    "N": (0, (0, -1)), "S": (180, (0, 1)), "W": (90, (1, 0)), "E": (-90, (-1, 0)),
}


def segments(nx, ny):
    out = []
    for i in range(nx):
        x = -nx + 1 + 2 * i
        out.append((f"N{i}", "N", x, ny)); out.append((f"S{i}", "S", x, -ny))
    for i in range(ny):
        y = -ny + 1 + 2 * i
        out.append((f"W{i}", "W", -nx, y)); out.append((f"E{i}", "E", nx, y))
    return out


ROOMS = [
    dict(name="room1_normal", kind="normal", label="1 Normal room (artifacts)", nx=3, ny=3, doors=["S1", "E1", "W1"], windows=["N1"], damaged=["N0"],
         center=[(0, 0)], chandeliers=[(0, 0)]),
    dict(name="room5_normal_wide", kind="normal", label="5 Normal wide room (artifacts)", nx=4, ny=2, doors=["W0", "E1", "S1"], windows=["N0", "N3"], damaged=["S3"],
         center=[(-1.2, 0), (1.8, 0)], chandeliers=[(-1, 1), (3, -1)]),
    dict(name="room4_big_hall", kind="big", label="4 Big hall (nave)", nx=5, ny=3, doors=["W1", "E1", "N4"], windows=["N1", "N2", "N3", "S1", "S2", "S3"],
         damaged=["S0"], no_slots=["N0", "S0", "N1", "S1"], chandeliers=[(-2, 0), (2, 0)],
         # three rows of shortened pews: a 1 m centre aisle, side aisles and 1.4 m between rows,
         # so the demon (and you) can get round them; two columns in the open east end
         fixed=[("pew", x, s * 1.35, 0, 90, 0.75) for x in (-3.6, -1.6, 0.4) for s in (-1, 1)]
               + [("column_full", 2.6, s * 2.25, 0, 0) for s in (-1, 1)]),
    dict(name="room2_end", kind="end", label="2 END (altar)", nx=3, ny=3, doors=["S1", "E1"], windows=["N0", "N2"],
         no_slots=["N0", "N1", "N2", "W0", "W1", "W2", "E0", "E2"], skip_corners=["NW", "NE"], chandeliers=[(0, -1.6)],
         fixed=[("altar", 0, 0.3, 0, 0), ("cross", 0, 2.72, 3.65, 0), ("candelabrum", -1.9, 2.2, 0, 0), ("candelabrum", 1.9, 2.2, 0, 0)],
         items=[]),
    dict(name="room3_start", kind="start", label="3 START (entrance)", nx=3, ny=2, doors=["N1", "S1"], windows=["W1", "E1"], no_slots=["W0"],
         chandeliers=[(0, -1)], fixed=[("font", -1.9, -0.6, 0, 0), ("lantern", 0.9, -1.5, 0, 30)]),
    dict(name="room6_corridor_long", kind="corridor", label="6 Corridor (long)", nx=1, ny=3, doors=["N0", "S0", "E1"], windows=["W1"], corridor=True,
         items=[(-0.45, -1.6, 0), (0.45, 1.6, 0)]),
    dict(name="room7_corridor_short", kind="corridor", label="7 Corridor (short)", nx=1, ny=2, doors=["N0", "S0", "W0"], damaged=["E1"], corridor=True,
         items=[(0.4, 0.5, 0)]),
]


def build_room(spec, dressed):
    nx, ny = spec["nx"], spec["ny"]
    corridor = spec.get("corridor", False)
    sc = Scene(spec["name"], script="res://scripts/room_runtime.gd",
               meta={"size_m": f"Vector2({nx * 2}, {ny * 2})", "room_label": f'"{spec["label"]}"', "kind": f'"{spec["kind"]}"'})
    sc.node("Shell", "Node3D")
    dais = set(spec.get("dais", []))
    r = random.Random(sum(map(ord, spec["name"])))
    for i in range(nx):
        for j in range(ny):
            x, y = -nx + 1 + 2 * i, -ny + 1 + 2 * j
            if (x, y) in dais:
                sc.inst(f"Dais_{i}_{j}", KIT + "dais_2m.glb", "Shell", tf(x, y))
            else:
                broken = r.random() < 0.15
                sc.inst(f"Floor_{i}_{j}", KIT + ("floor_2m_broken.glb" if broken else "floor_2m.glb"), "Shell", tf(x, y))
            sc.inst(f"Ceiling_{i}_{j}", KIT + "ceiling_2m.glb", "Shell", tf(x, y))
    # pilasters on every perimeter grid point
    pts = {(x, y) for x in range(-nx, nx + 1, 2) for y in (-ny, ny)} | {(x, y) for y in range(-ny, ny + 1, 2) for x in (-nx, nx)}
    for k, (x, y) in enumerate(sorted(pts)):
        sc.inst(f"Pilaster_{k}", KIT + "pilaster.glb", "Shell", tf(x, y))

    sc.node("Lights", "Node3D")
    sc.node("Slots", "Node3D", script="res://scripts/prop_spawner.gd", enabled="true" if dressed else "false", artifacts="Vector2i(0, 0)")
    doors, windows, damaged = set(spec.get("doors", [])), set(spec.get("windows", [])), set(spec.get("damaged", []))
    no_slots = set(spec.get("no_slots", []))
    for key, side, x, y in segments(nx, ny):
        rot, (dx, dy) = SIDES[side]
        if key in doors:
            sc.node(f"DoorSlot_{key}", "Node3D", ".", transform=tf(x, y, 0, rot))
            sc.inst("Wall", KIT + "wall_2m.glb", f"DoorSlot_{key}")
            sc.node("Doorway", "Node3D", f"DoorSlot_{key}")
            sc.inst("Frame", KIT + "wall_2m_door.glb", f"DoorSlot_{key}/Doorway")
            sc.inst("Door", PROP + "door.glb", f"DoorSlot_{key}/Doorway")
            continue
        if key in windows:
            sc.inst(f"Wall_{key}", KIT + "wall_2m_window.glb", "Shell", tf(x, y, 0, rot))
            sc.inst(f"Window_{key}", PROP + "window.glb", "Shell", tf(x, y, 1.0, rot))
            mx, my = x - dx * 4.5, y - dy * 4.5
            sc.node(f"Moon_{key}", "SpotLight3D", "Lights", transform=look_tf(g(mx, my, 4.6), g(x + dx * 2.6, y + dy * 2.6, 0.0)),
                    light_color="Color(0.55, 0.42, 1.0, 1)", light_energy="2.5", light_volumetric_fog_energy="2.5",
                    shadow_enabled="false", spot_range="14.0", spot_angle="22.0", spot_attenuation="0.6")
            continue
        sc.inst(f"Wall_{key}", KIT + ("wall_2m_damaged.glb" if key in damaged else "wall_2m.glb"), "Shell", tf(x, y, 0, rot))
        if key in no_slots:
            continue
        sx, sy = x + dx * 0.25, y + dy * 0.25
        sc.node(f"{'narrow' if corridor else 'wall'}_{key}", "Marker3D", "Slots", transform=tf(sx, sy, 0, rot))
        sc.node(f"deco_{key}", "Marker3D", "Slots", transform=tf(sx, sy, 0, rot))
    # corners (rooms only)
    corner_ok = lambda name, keys: name not in spec.get("skip_corners", []) and not (set(keys) & doors)
    if not corridor:
        for name, (cx, cy), keys in (("SW", (-nx, -ny), ("S0", "W0")), ("SE", (nx, -ny), (f"S{nx - 1}", "E0")),
                                     ("NW", (-nx, ny), ("N0", f"W{ny - 1}")), ("NE", (nx, ny), (f"N{nx - 1}", f"E{ny - 1}"))):
            if not corner_ok(name, keys): continue
            ix, iy = (1 if cx < 0 else -1), (1 if cy < 0 else -1)
            px, py = cx + ix * 0.65, cy + iy * 0.65
            rot = math.degrees(math.atan2(-ix, iy)) if False else math.degrees(math.atan2(ix, -iy))
            sc.node(f"corner_{name}", "Marker3D", "Slots", transform=tf(px, py, 0, rot))
            sc.node(f"clutter_{name}", "Marker3D", "Slots", transform=tf(cx + ix * 1.5, cy + iy * 0.7, 0, 0))
    else:
        sc.node("clutter_a", "Marker3D", "Slots", transform=tf(0.5, -ny + 1.2, 0, 0))
        sc.node("clutter_b", "Marker3D", "Slots", transform=tf(-0.5, ny - 1.2, 0, 0))
    for k, (x, y) in enumerate(spec.get("center", [])):
        sc.node(f"center_{k}", "Marker3D", "Slots", transform=tf(x, y))
    items = spec.get("items")
    if items is None: items = [(-nx + 1.2, -ny + 1.2, 0), (nx - 1.2, ny - 1.2, 0)]
    for k, (x, y, z) in enumerate(items):
        sc.node(f"item_{k}", "Marker3D", "Slots", transform=tf(x, y, z))
    # purple fill

    if dressed:
        sc.node("Fixed", "Node3D")
        for k, (x, y) in enumerate(spec.get("chandeliers", [])):
            sc.inst(f"NoCollide_Chandelier_{k}", PROP + "chandelier.glb", "Fixed", tf(x, y, 4.2))
        for k, entry in enumerate(spec.get("fixed", [])):
            asset, x, y, z, rot = entry[:5]
            sx = entry[5] if len(entry) > 5 else 1.0
            nc = asset.startswith("NoCollide:")
            asset = asset.split(":")[-1]
            sc.inst(f"{'NoCollide_' if nc else ''}{asset}_{k}", PROP + asset + ".glb", "Fixed", tfs(x, y, z, rot, sx))
    folder = "dressed" if dressed else "shell"
    sc.write(f"scenes/rooms/{folder}/{spec['name']}.tscn")
    return f"res://scenes/rooms/{folder}/{spec['name']}.tscn"


paths = []
for spec in ROOMS:
    paths.append(build_room(spec, False))
    paths.append(build_room(spec, True))

# ======================================================================= templates data for room_level.gd
OUTWARD = {"N": (0, -1), "S": (0, 1), "W": (-1, 0), "E": (1, 0)}     # Godot (x, z) pointing out of the room
lines = ["extends RefCounted", "# GENERATED by tools/build_rooms.py - do not edit by hand.",
         "# Godot coordinates (x, z). door: [key, position, outward direction]", "", "const TEMPLATES := {"]
for spec in ROOMS:
    nx, ny = spec["nx"], spec["ny"]
    doors = []
    for key, side, x, y in segments(nx, ny):
        if key in spec.get("doors", []):
            ox, oz = OUTWARD[side]
            doors.append(f'["{key}", Vector2({x}, {-y}), Vector2({ox}, {oz})]')
    lines.append(f'    "{spec["name"]}": {{"kind": "{spec["kind"]}", "half": Vector2({nx}, {ny}), '
                 f'"scene": "res://scenes/rooms/dressed/{spec["name"]}.tscn", "doors": [{", ".join(doors)}]}},')
lines.append("}")
with open(os.path.join(ROOT, "scripts/room_templates.gd"), "w", encoding="utf8") as f:
    f.write(chr(10).join(lines) + chr(10))
print(f"{len(GROUPS)} groups, {len(paths)} room scenes, room_templates.gd written")
