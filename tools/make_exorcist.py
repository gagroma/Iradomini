# MAKE_EXORCIST - the exorcist who came before you, dead in the gap of his
# unfinished circle (assets/models/dead_exorcist.glb), and the claw gouges in
# the floor next to him (assets/models/claw_marks.glb).
#
# Run from the project folder (Blender 4.2 or newer, tested on 5.2):
#   blender --background --factory-startup --python tools/make_exorcist.py
#
# The pose is the one level.gd expects (same as the old splat model): he lies
# on his front along +X, feet at -X, head at +X turned on its cheek, the right
# arm reaching out to where his chalk line ends, his last piece of chalk in
# the hand. Coordinates below are written Godot-style (x along the body,
# y up, z to his right) and turned into Blender's Z-up.
#
# The body: a skeleton with a man's proportions (1.78 m) - shoulders, chest,
# pelvis, arms with elbows and wrists, hands with jointed fingers, legs,
# shoes - grown into one smooth surface by Blender's Skin modifier, then
# shaped: a broad flat chest, shoulder blades, buttocks, flat hands, all
# pressed against the floor. The head is sculpted from a sphere (skull, jaw,
# chin, nose, brows, eye sockets, ears, hair).
# The cassock skirt and the purple stole are real cloth: Blender's cloth
# simulation drops them onto the body and the floor, so the folds are where
# fabric would really fold. Then:
#   - three claw slashes tear across his back;
#   - a white Roman collar, black shoes, livid skin with the blood settled
#     on the floor side;
#   - blood under his head, his ritual book thrown open, a broken rosary.
# Colours are vertex colours; shadows are baked in with Cycles (ambient
# occlusion). Vertex alpha = gloss (blood, shoes, beads shine).

import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_BODY = os.path.normpath(os.path.join(HERE, "..", "assets", "models", "dead_exorcist.glb"))
OUT_CLAWS = os.path.normpath(os.path.join(HERE, "..", "assets", "models", "claw_marks.glb"))

rng = random.Random(13)
GODOT_TO_BLENDER = Matrix.Rotation(math.radians(90.0), 4, "X")   # (x, y, z) -> (x, -z, y)

CASSOCK = (0.055, 0.05, 0.058)
SKIN = (0.6, 0.52, 0.48)          # dead and pale
HAIR = (0.16, 0.13, 0.11)
COLLAR = (0.86, 0.86, 0.82)
STOLE = (0.26, 0.07, 0.3)
STOLE_GOLD = (0.7, 0.52, 0.18)
BLOOD = (0.2, 0.015, 0.02)
LEATHER = (0.03, 0.028, 0.03)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(lerp(c1[k], c2[k], t) for k in range(3))


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def apply_all(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length, t


def paint(obj, fn):
    """fn(godot_position, godot_normal) -> (r, g, b, gloss)"""
    mesh = obj.data
    attr = mesh.color_attributes.get("Base") or mesh.color_attributes.new("Base", "FLOAT_COLOR", "POINT")
    for v in mesh.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))
        n = Vector((v.normal.x, v.normal.z, -v.normal.y))
        attr.data[v.index].color = fn(g, n)


# ------------------------------------------------------------------ the body

# The skeleton: point -> ((x, y, z) Godot space, radius). A man of 1.78 m
# lying on his front. Torso points are round here and made broad and flat
# afterwards (a chest is wider than it is deep).
P = {
    "pelvis": ((-0.02, 0.1, 0.0), 0.115),
    "waist": ((0.14, 0.1, 0.0), 0.1),
    "chest": ((0.31, 0.11, 0.0), 0.12),
    "upper": ((0.43, 0.11, 0.0), 0.1),
    "neck": ((0.54, 0.1, 0.012), 0.05),
    "neck_top": ((0.6, 0.092, 0.022), 0.043),
    # right arm, reaching out along the floor
    "sh_r": ((0.45, 0.12, 0.17), 0.058),
    "el_r": ((0.72, 0.072, 0.31), 0.043),
    "wr_r": ((0.975, 0.042, 0.41), 0.029),
    "palm_r": ((1.035, 0.03, 0.435), 0.03),
    # left arm down along his side
    "sh_l": ((0.45, 0.12, -0.17), 0.058),
    "el_l": ((0.24, 0.068, -0.31), 0.043),
    "wr_l": ((0.02, 0.045, -0.305), 0.029),
    "palm_l": ((-0.04, 0.036, -0.3), 0.032),
    # legs (under the cassock), one a little bent
    "hip_r": ((-0.07, 0.09, 0.09), 0.08),
    "knee_r": ((-0.5, 0.062, 0.11), 0.052),
    "calf_r": ((-0.68, 0.068, 0.115), 0.05),
    "ankle_r": ((-0.9, 0.056, 0.12), 0.032),
    "hip_l": ((-0.07, 0.09, -0.09), 0.08),
    "knee_l": ((-0.47, 0.062, -0.17), 0.052),
    "calf_l": ((-0.65, 0.066, -0.2), 0.05),
    "ankle_l": ((-0.86, 0.053, -0.23), 0.032),
    # shoes: toes point back, soles up
    "foot_r": ((-0.97, 0.046, 0.125), 0.042),
    "toe_r": ((-1.06, 0.032, 0.13), 0.034),
    "foot_l": ((-0.93, 0.043, -0.24), 0.042),
    "toe_l": ((-1.02, 0.03, -0.25), 0.034),
}
EDGES = [
    ("pelvis", "waist", "torso"), ("waist", "chest", "torso"), ("chest", "upper", "torso"),
    ("upper", "neck", "collar"), ("neck", "neck_top", "neck"),
    ("upper", "sh_r", "torso"), ("sh_r", "el_r", "sleeve"), ("el_r", "wr_r", "sleeve"), ("wr_r", "palm_r", "skin"),
    ("upper", "sh_l", "torso"), ("sh_l", "el_l", "sleeve"), ("el_l", "wr_l", "sleeve"), ("wr_l", "palm_l", "skin"),
    ("pelvis", "hip_r", "leg"), ("hip_r", "knee_r", "leg"), ("knee_r", "calf_r", "leg"), ("calf_r", "ankle_r", "leg"),
    ("ankle_r", "foot_r", "shoe"), ("foot_r", "toe_r", "shoe"),
    ("pelvis", "hip_l", "leg"), ("hip_l", "knee_l", "leg"), ("knee_l", "calf_l", "leg"), ("calf_l", "ankle_l", "leg"),
    ("ankle_l", "foot_l", "shoe"), ("foot_l", "toe_l", "shoe"),
]
# fingers: (from point name, [joints...], radius) - the right hand spread
# towards the end of the chalk line, the left curled into a loose fist
FINGERS = [
    ("palm_r", [(1.088, 0.02, 0.425), (1.128, 0.012, 0.423)], 0.0095),
    ("palm_r", [(1.092, 0.02, 0.443), (1.137, 0.012, 0.448)], 0.0098),
    ("palm_r", [(1.085, 0.02, 0.46), (1.126, 0.012, 0.47)], 0.0094),
    ("palm_r", [(1.074, 0.021, 0.474), (1.104, 0.013, 0.49)], 0.0085),
    ("wr_r", [(1.03, 0.028, 0.412), (1.062, 0.018, 0.397), (1.085, 0.014, 0.395)], 0.0105),
    ("palm_l", [(-0.085, 0.04, -0.29), (-0.09, 0.022, -0.276)], 0.012),
    ("palm_l", [(-0.083, 0.04, -0.305), (-0.088, 0.022, -0.293)], 0.012),
    ("palm_l", [(-0.078, 0.04, -0.318), (-0.083, 0.022, -0.308)], 0.011),
    ("wr_l", [(-0.02, 0.05, -0.282), (-0.055, 0.048, -0.272)], 0.011),
]


def build_body():
    names = list(P.keys())
    verts = [Vector(P[n][0]) for n in names]
    radii = [P[n][1] for n in names]
    edges = [(names.index(a), names.index(b)) for a, b, _ in EDGES]
    labels = [(Vector(P[a][0]), Vector(P[b][0]), lab) for a, b, lab in EDGES]
    for start, joints, r in FINGERS:
        prev = names.index(start)
        prev_p = Vector(P[start][0])
        for j, jp in enumerate(joints):
            verts.append(Vector(jp))
            radii.append(r * (1.0 - 0.15 * j))
            edges.append((prev, len(verts) - 1))
            labels.append((prev_p, Vector(jp), "skin"))
            prev = len(verts) - 1
            prev_p = Vector(jp)
    mesh = bpy.data.meshes.new("Body")
    mesh.from_pydata([GODOT_TO_BLENDER @ v for v in verts], edges, [])
    obj = link(bpy.data.objects.new("Body", mesh))
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    sv = obj.data.skin_vertices[0].data
    for i, r in enumerate(radii):
        sv[i].radius = (r, r)
    sv[names.index("chest")].use_root = True
    sub = obj.modifiers.new("Sub", "SUBSURF")
    sub.levels = 2
    apply_all(obj)

    def nearest(g):
        best = None
        for a, b, lab in labels:
            d, t = seg_dist(g, a, b)
            if best is None or d < best[0]:
                best = (d, t, lab, a, b)
        return best

    # shape the flesh
    for v in obj.data.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))
        d, t, lab, a, b = nearest(g)
        axis = a.lerp(b, t)
        if lab in ("torso", "collar"):
            # broad and flat; shoulder blades and buttocks stand up a little
            g.y = axis.y + (g.y - axis.y) * 0.74
            g.z = axis.z + (g.z - axis.z) * 1.22
            if g.y > axis.y:
                blade = math.exp(-(((g.x - 0.37) / 0.08) ** 2 + ((abs(g.z) - 0.09) / 0.06) ** 2))
                butt = math.exp(-(((g.x + 0.04) / 0.09) ** 2 + ((abs(g.z) - 0.06) / 0.07) ** 2))
                spine = math.exp(-((g.z / 0.025) ** 2)) * (1.0 if 0.0 < g.x < 0.42 else 0.0)
                g.y += 0.018 * blade + 0.03 * butt - 0.008 * spine
        elif lab == "skin" and min((b - Vector(P["palm_r"][0])).length, (b - Vector(P["palm_l"][0])).length) < 1e-6:
            g.y = axis.y + (g.y - axis.y) * 0.5             # a hand is flat
        elif lab == "shoe":
            g.y = axis.y + (g.y - axis.y) * 0.8
        g.y = max(g.y, 0.004)                               # pressed against the floor
        v.co = Vector((g.x, -g.z, g.y))
    obj.data.update()

    def colour(g, n):
        d, t, lab, a, b = nearest(g)
        gloss = 0.0
        if lab == "skin" or lab == "neck":
            c = SKIN
            c = mix(c, (0.45, 0.42, 0.48), 0.25 * max(0.0, noise.noise(g * 25.0)))   # livid, bluish
            if n.y < -0.3:
                c = mix(c, (0.5, 0.25, 0.28), 0.5)        # blood settles in the lowest side
        elif lab == "collar":
            c = COLLAR if (g - Vector(P["neck"][0])).length < 0.065 else CASSOCK
        elif lab == "leg":
            c = (0.035, 0.033, 0.036)
        elif lab == "shoe":
            c = LEATHER
            gloss = 0.55
        else:
            c = CASSOCK
            # buttons down the back? no - down the front, under him. Dust and wear:
            c = mix(c, (0.13, 0.12, 0.11), 0.4 * max(0.0, noise.noise(g * 14.0)))
            # cuffs are worn shiny at the edges
            if lab == "sleeve" and t > 0.92:
                c = mix(c, (0.1, 0.1, 0.11), 0.6)
            # three claw slashes across the back
            if n.y > 0.25 and lab == "torso" and -0.06 < g.x < 0.44:
                for k in range(3):
                    s = (g.x - 0.16) * 0.55 + g.z * 0.9 - (k - 1) * 0.075
                    w = 0.013 + 0.006 * noise.noise(g * 30.0)
                    if abs(s) < w:
                        c = BLOOD
                        gloss = 0.25
                    elif abs(s) < w + 0.014:
                        c = mix(SKIN, BLOOD, 0.55)            # torn cloth, raw skin
        return (c[0], c[1], c[2], gloss)
    paint(obj, colour)
    return obj


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def gauss(x, w):
    return math.exp(-((x / w) ** 2))


def build_head():
    """A head sculpted from a sphere: skull, jaw, chin, nose, brows, eye
    sockets, ears. It lies on its left cheek, face turned to his right."""
    centre = Vector((0.69, 0.083, 0.035))
    F = Vector((0.12, 0.0, 1.0)).normalized()           # where the face looks
    U = Vector((1.0, 0.08, -0.12))
    U = (U - F * U.dot(F)).normalized()                 # crown
    S = F.cross(U).normalized()                         # out of his left ear
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=22, radius=1.0)
    # sphere's own axes: x = front, z = up, y = side
    for v in bm.verts:
        a, c, b = v.co.x, v.co.y, v.co.z              # a front, b up, c side
        depth = 0.1 * (1.05 if a < 0.0 and b > -0.1 else 1.0)
        height = 0.118
        width = 0.077 * (1.0 - 0.22 * max(0.0, -b) ** 1.5)   # the jaw is narrower
        if a > 0.5:
            depth -= 0.014 * (a - 0.5)                   # a face is flatter than a ball
        if a < 0.2 and b < -0.35:
            depth *= 0.75                                # behind the jaw: the neck
        p = F * (a * depth) + U * (b * height) + S * (c * width)
        front = max(0.0, a)
        p += F * (0.024 * gauss(c, 0.09) * gauss(b + 0.12, 0.17) * front ** 4)        # nose
        p += F * (0.007 * gauss(b - 0.24, 0.08) * front ** 3)                         # brow
        p -= F * (0.01 * gauss(abs(c) - 0.36, 0.12) * gauss(b - 0.1, 0.08) * front ** 2)   # eye sockets
        p += F * (0.008 * gauss(c, 0.22) * gauss(b + 0.76, 0.12) * front)             # chin
        p += U * (-0.004 * gauss(c, 0.25) * gauss(b + 0.45, 0.04) * front ** 3)       # mouth line
        ear = gauss(a + 0.08, 0.16) * gauss(b - 0.02, 0.22) * max(0.0, abs(c) - 0.78) * 5.0
        p += S * (0.017 * ear * (1.0 if c > 0 else -1.0))                              # ears
        p = centre + p
        p.y = max(p.y, 0.005)
        v.co = GODOT_TO_BLENDER @ p
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Head")
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Head", mesh))
    for poly in obj.data.polygons:
        poly.use_smooth = True

    def colour(g, n):
        d = g - centre
        a = d.dot(F) / 0.1
        b = d.dot(U) / 0.118
        c = d.dot(S) / 0.077
        col = SKIN
        col = mix(col, (0.45, 0.42, 0.48), 0.3 * max(0.0, noise.noise(g * 30.0)))
        hairline = 0.42 + 0.06 * noise.noise(g * 50.0)
        if (b > hairline or a < -0.2) and not (a > 0.62 and b < 0.55) and b > -0.5:
            col = mix(HAIR, (0.4, 0.38, 0.35), max(0.0, noise.noise(g * 90.0)) * 0.7)   # grey in it
        elif a > 0.6:
            if gauss(abs(c) - 0.36, 0.12) * gauss(b - 0.1, 0.07) > 0.5:
                col = (0.3, 0.22, 0.22)                  # closed eyes in dark sockets
            if abs(b + 0.45) < 0.05 and abs(c) < 0.32:
                col = (0.34, 0.18, 0.19)                 # lips
        if d.y < -0.02 and a > -0.3:
            col = mix(col, BLOOD, 0.6)                   # the cheek on the floor, in blood
        return (col[0], col[1], col[2], 0.0)
    paint(obj, colour)
    return obj


# ------------------------------------------------------------------ cloth

def collider(obj, thickness=0.005):
    m = obj.modifiers.new("Collision", "COLLISION")
    obj.collision.thickness_outer = thickness
    obj.collision.cloth_friction = 8.0
    obj.collision.damping = 0.8
    return m


def simulate(obj, frames, pin_rows_fn, settings):
    """Drop a cloth: pin some vertices, run the frames, keep the last one."""
    vg = obj.vertex_groups.new(name="pin")
    for v in obj.data.vertices:
        w = pin_rows_fn(Vector((v.co.x, v.co.z, -v.co.y)))
        if w > 0.0:
            vg.add([v.index], w, "REPLACE")
    mod = obj.modifiers.new("Cloth", "CLOTH")
    cs = mod.settings
    cs.quality = 10
    cs.mass = settings.get("mass", 0.3)
    cs.air_damping = 1.0
    cs.tension_stiffness = settings.get("stiff", 15.0)
    cs.compression_stiffness = settings.get("stiff", 15.0)
    cs.shear_stiffness = settings.get("shear", 5.0)
    cs.bending_stiffness = settings.get("bend", 0.3)
    cs.vertex_group_mass = "pin"
    mod.collision_settings.distance_min = 0.004
    mod.collision_settings.collision_quality = 4
    mod.point_cache.frame_start = 1
    mod.point_cache.frame_end = frames
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = frames
    for f in range(1, frames + 1):
        scene.frame_set(f)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier="Cloth")
    obj.vertex_groups.clear()


def grid_object(name, rows):
    """rows: list of lists of Godot-space points -> a quad grid object."""
    verts = []
    faces = []
    w = len(rows[0])
    for row in rows:
        for p in row:
            verts.append(GODOT_TO_BLENDER @ p)
    for i in range(len(rows) - 1):
        for j in range(w - 1):
            a = i * w + j
            faces.append((a, a + 1, a + w + 1, a + w))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    return link(bpy.data.objects.new(name, mesh))


def build_skirt(body, ground):
    """The cassock skirt: a sheet arched over the legs, sewn to the waist,
    dropped onto the legs and floor by the cloth simulation."""
    rows = []
    nx, nt = 40, 34
    for i in range(nx + 1):
        k = i / nx
        x = lerp(0.07, -1.0, k)
        ry = lerp(0.105, 0.2, smoothstep(0.0, 0.35, k))
        rz = lerp(0.165, 0.29, smoothstep(0.0, 0.45, k))
        cy = lerp(0.1, 0.07, k)
        cz = lerp(0.0, -0.05, k)
        row = []
        for j in range(nt + 1):
            th = lerp(-1.8, 1.8, j / nt)
            row.append(Vector((x, max(0.012, cy + ry * math.cos(th)), cz + rz * math.sin(th))))
        rows.append(row)
    skirt = grid_object("Skirt", rows)
    collider(body)
    collider(ground)
    simulate(skirt, 70, lambda g: 1.0 if g.x > 0.045 else 0.0,
             {"mass": 0.35, "stiff": 20.0, "shear": 6.0, "bend": 0.4})
    sol = skirt.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.005
    sol.offset = 1.0
    apply_all(skirt)
    for poly in skirt.data.polygons:
        poly.use_smooth = True

    def colour(g, n):
        c = mix(CASSOCK, (0.13, 0.12, 0.11), 0.45 * max(0.0, noise.noise(g * 12.0)))
        if g.x < -0.97:
            c = mix(c, (0.15, 0.14, 0.12), 0.5)           # the hem, dusty from the floor
        return (c[0], c[1], c[2], 0.0)
    paint(skirt, colour)
    return skirt


def build_stole(colliders, ground):
    """The purple stole, slipped over his shoulders in the struggle: a strip
    laid across his back and let fall, its ends spilling onto the floor."""
    rows = []
    for i in range(3):
        x = lerp(0.47, 0.54, i / 2.0)
        rows.append([Vector((x, 0.3, lerp(-0.55, 0.55, j / 60.0))) for j in range(61)])
    stole = grid_object("Stole", rows)
    for c in colliders:
        collider(c)
    simulate(stole, 60, lambda g: 1.0 if abs(g.z) < 0.05 else 0.0,
             {"mass": 0.15, "stiff": 30.0, "shear": 10.0, "bend": 1.0})
    sol = stole.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.004
    sol.offset = 1.0
    apply_all(stole)
    for poly in stole.data.polygons:
        poly.use_smooth = True
    # where the ends lie: for the embroidered crosses
    ends = []
    for v in stole.data.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))
        ends.append(g)

    def colour(g, n):
        c = STOLE
        # gold crosses near both ends (the ends are the points furthest from the middle)
        for e in (end_a, end_b):
            q = g - e
            if (abs(q.x) < 0.008 and abs(q.z) < 0.035) or (abs(q.z) < 0.008 and abs(q.x) < 0.025):
                c = STOLE_GOLD
        return (c[0], c[1], c[2], 0.0)
    end_a = max(ends, key=lambda g: g.z)
    end_b = min(ends, key=lambda g: g.z)
    end_a = end_a + Vector((0.0, 0.0, -0.08))
    end_b = end_b + Vector((0.0, 0.0, 0.08))
    paint(stole, colour)
    return stole


def remove_colliders(objs):
    for o in objs:
        for m in list(o.modifiers):
            if m.type == "COLLISION":
                o.modifiers.remove(m)


def blob(name, centre, size, colour, gloss=0.0, segs=(10, 6)):
    """A small squashed sphere (beads, his chalk)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs[0], v_segments=segs[1], radius=1.0)
    for v in bm.verts:
        p = Vector((v.co.x * size.x, v.co.y * size.y, v.co.z * size.z)) + centre
        v.co = GODOT_TO_BLENDER @ p
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    for p in obj.data.polygons:
        p.use_smooth = True
    paint(obj, lambda g, n: (colour[0], colour[1], colour[2], gloss))
    return obj


def build_blood():
    bm = bmesh.new()
    centre = Vector((0.71, 0.004, 0.03))
    ring = []
    n = 28
    for i in range(n):
        a = math.tau * i / n
        r = 0.2 * (1.0 + 0.35 * noise.noise(Vector((math.cos(a) * 2.0, math.sin(a) * 2.0, 0.5))))
        r *= 1.0 + 0.25 * max(0.0, math.cos(a - 0.4))           # it ran a little towards the reaching arm
        ring.append(bm.verts.new(GODOT_TO_BLENDER @ (centre + Vector((math.cos(a) * r * 1.2, 0.0, math.sin(a) * r)))))
    c = bm.verts.new(GODOT_TO_BLENDER @ centre)
    for i in range(n):
        bm.faces.new((c, ring[i], ring[(i + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    mesh = bpy.data.meshes.new("Blood")
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Blood", mesh))

    def colour(g, n):
        d = (g - centre).length
        c = mix(BLOOD, (0.09, 0.01, 0.012), smoothstep(0.0, 0.25, d))   # darker, dried at the edge
        return (c[0], c[1], c[2], 1.0)
    paint(obj, colour)
    return obj


def build_book():
    # the Rituale, thrown open, a little away from his left hand
    objs = []
    base = Vector((0.12, 0.0, -0.56))
    turn = Matrix.Rotation(0.5, 3, "Y")
    parts = [
        (Vector((-0.07, 0.004, 0.0)), Vector((0.07, 0.004, 0.1)), (0.22, 0.04, 0.05), 0.0),     # covers
        (Vector((0.07, 0.004, 0.0)), Vector((0.07, 0.004, 0.1)), (0.22, 0.04, 0.05), 0.0),
        (Vector((-0.065, 0.014, 0.0)), Vector((0.064, 0.008, 0.094)), (0.72, 0.68, 0.58), 0.0),  # pages
        (Vector((0.065, 0.014, 0.0)), Vector((0.064, 0.008, 0.094)), (0.72, 0.68, 0.58), 0.0),
        (Vector((0.0, 0.01, 0.0)), Vector((0.008, 0.012, 0.1)), (0.18, 0.03, 0.04), 0.0),        # spine
        (Vector((0.05, 0.023, 0.01)), Vector((0.004, 0.001, 0.08)), (0.5, 0.05, 0.06), 0.0),    # red ribbon
    ]
    for off, half, col, gl in parts:
        bm = bmesh.new()
        geo = bmesh.ops.create_cube(bm, size=2.0)
        for v in geo["verts"]:
            p = Vector((v.co.x * half.x, v.co.y * half.y, v.co.z * half.z)) + off
            v.co = GODOT_TO_BLENDER @ (base + turn @ p)
        mesh = bpy.data.meshes.new("Book")
        bm.to_mesh(mesh)
        bm.free()
        obj = link(bpy.data.objects.new("Book", mesh))

        def colour(g, n, col=col):
            c = col
            if col[0] > 0.6 and n.y > 0.5:
                # lines of print, and a red initial
                lp = turn.transposed() @ (g - base)
                if abs((lp.z * 160.0) % 2.0 - 1.0) < 0.35 and abs(abs(lp.x) - 0.065) < 0.048:
                    c = (0.25, 0.22, 0.2)
            return (c[0], c[1], c[2], 0.0)
        paint(obj, colour)
        objs.append(obj)
    return objs


def build_rosary():
    # the cord snapped: beads strewn in a loose curve, the crucifix apart
    objs = []
    start = Vector((0.02, 0.0, -0.3))
    for i in range(34):
        t = i / 33.0
        p = start + Vector((-0.28 * t + 0.05 * math.sin(t * 9.0), 0.0, -0.18 * math.sin(t * 3.0) - 0.05 * t))
        p += Vector((rng.uniform(-0.01, 0.01), 0.0, rng.uniform(-0.01, 0.01)))
        if i in (12, 23):
            p += Vector((rng.uniform(-0.06, 0.06), 0.0, rng.uniform(-0.06, 0.06)))   # rolled away
        objs.append(blob("Bead", p + Vector((0, 0.0075, 0)), Vector((0.0075, 0.0075, 0.0075)), (0.18, 0.09, 0.05), 0.7, (6, 4)))
    cx = start + Vector((-0.36, 0.0, -0.02))
    for off, half in ((Vector((0, 0.005, 0)), Vector((0.042, 0.004, 0.007))), (Vector((0.016, 0.005, 0)), Vector((0.007, 0.004, 0.026)))):
        bm = bmesh.new()
        geo = bmesh.ops.create_cube(bm, size=2.0)
        for v in geo["verts"]:
            v.co = GODOT_TO_BLENDER @ (cx + off + Vector((v.co.x * half.x, v.co.y * half.y, v.co.z * half.z)))
        mesh = bpy.data.meshes.new("Crucifix")
        bm.to_mesh(mesh)
        bm.free()
        obj = link(bpy.data.objects.new("Crucifix", mesh))
        paint(obj, lambda g, n: (0.36, 0.35, 0.34, 0.45))   # old, tarnished silver
        objs.append(obj)
    return objs


def build_chalk():
    # his last piece of chalk, under the reaching fingers
    return blob("Chalk", Vector((1.14, 0.009, 0.47)), Vector((0.03, 0.009, 0.009)), (0.9, 0.88, 0.8), 0.0, (8, 4))


# ------------------------------------------------------------------ bake and export

def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    return obj


def bake_and_finish(obj):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.3
    mat = bpy.data.materials.new("Body")
    mat.use_nodes = True
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    mesh = obj.data
    ao = mesh.color_attributes.new("AO", "FLOAT_COLOR", "CORNER")
    mesh.color_attributes.active_color = ao
    bpy.ops.mesh.primitive_plane_add(size=6.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    scene.render.bake.target = "VERTEX_COLORS"
    bpy.ops.object.bake(type="AO")
    bpy.data.objects.remove(ground)
    base = mesh.color_attributes["Base"]
    col = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for loop in mesh.loops:
        b = base.data[loop.vertex_index].color
        a = ao.data[loop.index].color[0]
        k = 0.3 + 0.7 * a
        col.data[loop.index].color = (b[0] * k, b[1] * k, b[2] * k, b[3])
    mesh.color_attributes.remove(mesh.color_attributes["AO"])
    mesh.color_attributes.remove(mesh.color_attributes["Base"])
    mesh.color_attributes.active_color = mesh.color_attributes["Col"]
    mesh.color_attributes.render_color_index = 0


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kwargs = dict(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                  use_selection=True, export_normals=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kwargs)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("make_exorcist: wrote", path, "triangles:", tris)


def build_claws():
    """Three gouges torn into the stone: dark grooves with pale crushed stone
    along their lips and a smear of blood."""
    objs = []
    for k in range(3):
        z = (k - 1) * 0.14
        pts = []
        for i in range(25):
            t = i / 24.0
            x = lerp(-0.42, 0.42, t)
            pts.append((Vector((x, 0.0, z + 0.1 * t + 0.02 * math.sin(t * 5.0 + k))), t))
        for layer, (w_scale, col, lift) in enumerate([(2.6, (0.5, 0.48, 0.46), 0.002), (1.0, (0.035, 0.03, 0.035), 0.004)]):
            bm = bmesh.new()
            rows = []
            for i, (p, t) in enumerate(pts):
                a = pts[max(i - 1, 0)][0]
                b = pts[min(i + 1, len(pts) - 1)][0]
                side = (b - a).normalized().cross(Vector((0, 1, 0))).normalized()
                w = 0.013 * math.sin(math.pi * min(1.0, t * 1.15)) ** 0.6 * w_scale
                w *= 1.0 + 0.3 * noise.noise(Vector((t * 9.0, k, layer)))
                lift_v = Vector((0, lift, 0))
                rows.append([bm.verts.new(GODOT_TO_BLENDER @ (p + side * w + lift_v)),
                             bm.verts.new(GODOT_TO_BLENDER @ (p - side * w + lift_v))])
            for i in range(len(rows) - 1):
                bm.faces.new((rows[i][0], rows[i + 1][0], rows[i + 1][1], rows[i][1]))
            for f in bm.faces:
                if f.normal.z < 0:
                    f.normal_flip()
            mesh = bpy.data.meshes.new("Claw")
            bm.to_mesh(mesh)
            bm.free()
            obj = link(bpy.data.objects.new("Claw", mesh))

            def colour(g, n, col=col, layer=layer):
                c = col
                if layer == 0 and noise.noise(g * 40.0) > 0.25:
                    c = mix(col, BLOOD, 0.7)             # blood dragged along
                return (c[0], c[1], c[2], 0.3 if layer == 1 else 0.0)
            paint(obj, colour)
            objs.append(obj)
    claws = join(objs, "ClawMarks")
    mesh = claws.data
    base = mesh.color_attributes["Base"]
    col = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for loop in mesh.loops:
        col.data[loop.index].color = base.data[loop.vertex_index].color
    mesh.color_attributes.remove(base)
    mesh.color_attributes.active_color = mesh.color_attributes["Col"]
    return claws


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    body = build_body()
    head = build_head()
    skirt = build_skirt(body, ground)
    stole = build_stole([head, skirt], ground)
    remove_colliders([body, head, skirt, ground])
    bpy.data.objects.remove(ground)
    parts = [body, head, skirt, stole, build_blood(), build_chalk()]
    parts += build_book() + build_rosary()
    dead = join(parts, "DeadExorcist")
    bake_and_finish(dead)
    export(dead, OUT_BODY)
    dead.hide_set(True)
    claws = build_claws()
    export(claws, OUT_CLAWS)


main()
