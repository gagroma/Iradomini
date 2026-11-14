import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "models", "player_body.glb"))
G2B = Matrix.Rotation(math.radians(90.0), 4, "X")
G2B3 = G2B.to_3x3()
FPS = 30

CASSOCK = (0.05, 0.047, 0.055)
SKIN = (0.72, 0.56, 0.47)
HAIR = (0.12, 0.09, 0.07)
COLLAR = (0.86, 0.86, 0.82)
LEATHER = (0.03, 0.028, 0.03)
STOLE = (0.3, 0.06, 0.32)
GOLD = (0.7, 0.52, 0.18)

BONES = [
    ("hips", None, (0, 0.97, 0), (0, 1.08, 0), 0.095),
    ("spine", "hips", (0, 1.08, 0), (0, 1.3, 0), 0.082),
    ("chest", "spine", (0, 1.3, 0), (0, 1.48, 0), 0.1),
    ("neck", "chest", (0, 1.48, 0), (0, 1.58, -0.01), 0.05),
    ("head", "neck", (0, 1.58, -0.01), (0, 1.8, -0.01), 0.088),
    ("upperarm_l", "chest", (-0.19, 1.44, 0), (-0.21, 1.16, 0), 0.05),
    ("forearm_l", "upperarm_l", (-0.21, 1.16, 0), (-0.22, 0.92, 0), 0.045),
    ("hand_l", "forearm_l", (-0.22, 0.92, 0), (-0.22, 0.8, -0.01), 0.03),
    ("upperarm_r", "chest", (0.19, 1.44, 0), (0.21, 1.16, 0), 0.05),
    ("forearm_r", "upperarm_r", (0.21, 1.16, 0), (0.22, 0.92, 0), 0.045),
    ("hand_r", "forearm_r", (0.22, 0.92, 0), (0.22, 0.8, -0.01), 0.03),
    ("thigh_l", "hips", (-0.1, 0.95, 0), (-0.1, 0.52, 0), 0.08),
    ("shin_l", "thigh_l", (-0.1, 0.52, 0), (-0.1, 0.09, 0.01), 0.055),
    ("foot_l", "shin_l", (-0.1, 0.09, 0.01), (-0.1, 0.03, -0.15), 0.04),
    ("thigh_r", "hips", (0.1, 0.95, 0), (0.1, 0.52, 0), 0.08),
    ("shin_r", "thigh_r", (0.1, 0.52, 0), (0.1, 0.09, 0.01), 0.055),
    ("foot_r", "shin_r", (0.1, 0.09, 0.01), (0.1, 0.03, -0.15), 0.04),
]
BONE = {b[0]: b for b in BONES}

P = {
    "pelvis": ((0, 0.97, 0), 0.125),
    "waist": ((0, 1.1, 0), 0.105),
    "chest": ((0, 1.3, 0), 0.125),
    "upper": ((0, 1.43, 0), 0.105),
    "neck": ((0, 1.5, -0.005), 0.056),
    "neck_top": ((0, 1.585, -0.008), 0.05),
}
EDGES = [("pelvis", "waist", "torso"), ("waist", "chest", "torso"), ("chest", "upper", "torso"),
         ("upper", "neck", "collar"), ("neck", "neck_top", "neck")]
for s, sx in (("l", -1), ("r", 1)):
    P.update({
        "sh_" + s: ((0.19 * sx, 1.445, 0), 0.062),
        "el_" + s: ((0.21 * sx, 1.16, 0), 0.046),
        "wr_" + s: ((0.22 * sx, 0.92, 0), 0.032),
        "palm_" + s: ((0.222 * sx, 0.872, -0.004), 0.031),
        "knuck_" + s: ((0.222 * sx, 0.843, 0.0), 0.029),
        "hip_" + s: ((0.1 * sx, 0.93, 0), 0.085),
        "knee_" + s: ((0.1 * sx, 0.52, 0), 0.055),
        "calf_" + s: ((0.1 * sx, 0.36, 0.012), 0.055),
        "ankle_" + s: ((0.1 * sx, 0.1, 0.01), 0.034),
        "foot_" + s: ((0.1 * sx, 0.055, -0.07), 0.045),
        "toe_" + s: ((0.1 * sx, 0.035, -0.16), 0.035),
    })
    EDGES += [("upper", "sh_" + s, "torso"), ("sh_" + s, "el_" + s, "sleeve"), ("el_" + s, "wr_" + s, "sleeve"),
              ("wr_" + s, "palm_" + s, "palm"), ("palm_" + s, "knuck_" + s, "palm"),
              ("pelvis", "hip_" + s, "leg"), ("hip_" + s, "knee_" + s, "leg"), ("knee_" + s, "calf_" + s, "leg"),
              ("calf_" + s, "ankle_" + s, "leg"), ("ankle_" + s, "foot_" + s, "shoe"), ("foot_" + s, "toe_" + s, "shoe")]

FINGERS = []
for s, sx in (("l", -1), ("r", 1)):
    for z, y0, length, r, curl in ((-0.021, 0.83, 0.074, 0.0088, 1.0), (-0.007, 0.826, 0.082, 0.0091, 1.05),
                                   (0.007, 0.828, 0.077, 0.0087, 1.12), (0.02, 0.834, 0.06, 0.0076, 1.22)):
        pts = [(0.222 * sx, y0, z)]
        ang = 0.0
        for k, part in enumerate((0.45, 0.32, 0.23)):
            ang += (0.22, 0.38, 0.42)[k] * curl
            x, y, zz = pts[-1]
            pts.append((x - sx * math.sin(ang) * length * part, y - math.cos(ang) * length * part, zz + z * 0.12 * part))
        FINGERS.append(("knuck_" + s, pts, r))
    FINGERS.append(("palm_" + s, [(0.216 * sx, 0.878, -0.022), (0.21 * sx, 0.86, -0.04), (0.204 * sx, 0.84, -0.049),
                                  (0.199 * sx, 0.824, -0.049)], 0.0105))


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(lerp(c1[k], c2[k], t) for k in range(3))


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def gauss(x, w):
    return math.exp(-((x / w) ** 2))


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def to_g(co):
    return Vector((co.x, co.z, -co.y))


def to_b(g):
    return Vector((g.x, -g.z, g.y))


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
    mesh = obj.data
    attr = mesh.color_attributes.get("Base") or mesh.color_attributes.new("Base", "FLOAT_COLOR", "POINT")
    for v in mesh.vertices:
        attr.data[v.index].color = fn(to_g(v.co), to_g(v.normal))


LABELS = {}


def cloth(g):
    c = mix(CASSOCK, (0.12, 0.11, 0.1), 0.35 * max(0.0, noise.noise(g * 14.0)))
    c = mix(c, (0.02, 0.02, 0.025), 0.4 * max(0.0, noise.noise(g * Vector((60.0, 6.0, 60.0)))))
    return c


def front_detail(g, n, c, gloss):
    if n.z < -0.3 and abs(g.x) < 0.016:
        c = mix(c, (0.1, 0.1, 0.1), 0.35)
        ph = (g.y / 0.034) % 1.0
        if abs(g.x) < 0.008 and abs(ph - 0.5) < 0.2:
            c = (0.015, 0.012, 0.015)
            gloss = 0.5
    if 1.01 < g.y < 1.06:
        c = (0.035, 0.025, 0.04)
        gloss = 0.2
    return c, gloss


def build_body():
    names = list(P.keys())
    verts = [Vector(P[n][0]) for n in names]
    radii = [P[n][1] for n in names]
    edges = [(names.index(a), names.index(b)) for a, b, _ in EDGES]
    labels = [(Vector(P[a][0]), Vector(P[b][0]), lab, P[a][1], P[b][1]) for a, b, lab in EDGES]
    for start, pts, r in FINGERS:
        prev = names.index(start)
        prev_p, prev_r = Vector(P[start][0]), P[start][1]
        for j, jp in enumerate(pts):
            verts.append(Vector(jp))
            rr = r * (1.08, 1.0, 0.94, 0.86)[min(j, 3)]
            if len(pts) == 4 and start.startswith("palm") and j == 0:
                rr = 0.016
            radii.append(rr)
            edges.append((prev, len(verts) - 1))
            lab = "palm" if j == 0 else ("tip" if j == len(pts) - 1 else "skin")
            labels.append((prev_p, Vector(jp), lab, prev_r if j else r, rr))
            prev = len(verts) - 1
            prev_p, prev_r = Vector(jp), rr
    mesh = bpy.data.meshes.new("Body")
    mesh.from_pydata([to_b(v) for v in verts], edges, [])
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
        for a, b, lab, ra, rb in labels:
            d, t = seg_dist(g, a, b)
            d -= lerp(ra, rb, t)
            if best is None or d < best[0]:
                best = (d, t, lab, a, b)
        return best

    for v in obj.data.vertices:
        g = to_g(v.co)
        d, t, lab, a, b = nearest(g)
        LABELS[v.index] = lab
        axis = a.lerp(b, t)
        if lab in ("torso", "collar"):
            g.z = axis.z + (g.z - axis.z) * 0.74
            g.x = axis.x + (g.x - axis.x) * 1.22
            if g.z > axis.z:
                blade = math.exp(-(((g.y - 1.38) / 0.08) ** 2 + ((abs(g.x) - 0.09) / 0.06) ** 2))
                g.z += 0.016 * blade
            else:
                pec = math.exp(-(((g.y - 1.33) / 0.07) ** 2 + ((abs(g.x) - 0.08) / 0.07) ** 2))
                g.z -= 0.012 * pec
        elif lab == "palm" and 0.815 < g.y < 0.915:
            g.x = axis.x + (g.x - axis.x) * 0.6
        elif lab == "sleeve":
            radial = (g - axis).normalized()
            along = (b - a).normalized()
            el = Vector(P["el_l" if g.x < 0 else "el_r"][0])
            de = (axis - el).length
            elbow = math.exp(-((de / 0.07) ** 2))
            front = max(0.0, -radial.z)
            phase = (g - el).dot(along) * 95.0 + radial.x * 3.0
            fold = 0.0065 * math.sin(phase) * elbow * (0.4 + 0.6 * front)
            fold += 0.0032 * noise.noise(g * Vector((28.0, 9.0, 28.0)))
            if t > 0.8 and (b - Vector(P["wr_l" if g.x < 0 else "wr_r"][0])).length < 1e-6:
                fold += 0.0025 * math.sin((g - axis).length * 0 + g.y * 160.0 + radial.z * 2.0) * smoothstep(0.8, 0.95, t)
                g += (g - axis) * 0.12 * smoothstep(0.8, 0.97, t)
            g += radial * fold
        if lab == "torso":
            radial = Vector((g.x, 0.0, g.z - axis.z)).normalized()
            waist = smoothstep(1.06, 1.1, g.y) * smoothstep(1.2, 1.12, g.y)
            g += radial * (0.0022 * math.sin(g.y * 150.0 + g.x * 18.0) * waist)
            pit = math.exp(-(((abs(g.x) - 0.16) / 0.05) ** 2 + ((g.y - 1.36) / 0.05) ** 2))
            g += radial * (0.003 * math.sin(math.atan2(g.y - 1.36, abs(g.x) - 0.16) * 6.0) * pit)
            g += radial * 0.0015 * noise.noise(g * Vector((12.0, 30.0, 12.0)))
        v.co = to_b(g)
    obj.data.update()

    def colour(g, n):
        d, t, lab, a, b = nearest(g)
        gloss = 0.0
        if lab in ("skin", "neck", "palm", "tip"):
            c = mix(SKIN, (0.62, 0.42, 0.38), 0.3 * max(0.0, noise.noise(g * 25.0)))
            sx = 1.0 if g.x > 0 else -1.0
            back = n.x * sx
            if lab in ("skin", "tip", "palm") and g.y < 0.93:
                if back < -0.2:
                    c = mix(c, (0.82, 0.6, 0.52), 0.35)
                else:
                    c = mix(c, (0.5, 0.45, 0.5), 0.12 * max(0.0, noise.noise(g * Vector((40.0, 140.0, 40.0)))))
                if lab != "tip" and back > 0.3 and (t < 0.12 or t > 0.9):
                    c = mix(c, (0.52, 0.36, 0.32), 0.35)
            if lab == "tip" and back > 0.35 and t > 0.45:
                c = (0.84, 0.7, 0.66)
                gloss = 0.45
            if lab == "tip" and t > 0.85:
                c = mix(c, (0.85, 0.55, 0.5), 0.3)
            if lab == "neck" and g.y < 1.548:
                c = COLLAR if g.y > 1.505 else CASSOCK
        elif lab == "collar":
            c = COLLAR if (g - Vector(P["neck"][0])).length < 0.07 and n.z < 0.3 else CASSOCK
        elif lab == "leg":
            c = (0.06, 0.058, 0.062)
        elif lab == "shoe":
            c = LEATHER
            gloss = 0.6
            if g.y < 0.03:
                c = (0.07, 0.05, 0.04)
                gloss = 0.1
        else:
            c = cloth(g)
            gloss = 0.08
            if lab == "sleeve" and t > 0.86:
                c = mix(c, (0.09, 0.09, 0.1), 0.5)
                if t > 0.97:
                    c = (0.8, 0.79, 0.75)
            if lab == "torso":
                c, gloss = front_detail(g, n, c, gloss)
        return (c[0], c[1], c[2], gloss)
    paint(obj, colour)
    return obj


def build_head():
    centre = Vector((0.0, 1.69, -0.015))
    F = Vector((0.0, 0.0, -1.0))
    U = Vector((0.0, 1.0, 0.0))
    S = F.cross(U).normalized()
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=96, v_segments=72, radius=1.0)
    for v in bm.verts:
        a, c, b = v.co.x, v.co.y, v.co.z
        depth = 0.1 * (1.05 if a < 0.0 and b > -0.1 else 1.0)
        height = 0.118
        width = 0.077 * (1.0 - 0.14 * max(0.0, -b) ** 1.5)
        if a > 0.5:
            depth -= 0.014 * (a - 0.5)
        if a < 0.2 and b < -0.35:
            depth *= 0.75
        p = F * (a * depth) + U * (b * height) + S * (c * width)
        front = max(0.0, a)
        p += F * (0.03 * gauss(c, 0.085) * gauss(b + 0.1, 0.16) * front ** 4)
        p -= F * (0.006 * gauss(c, 0.12) * gauss(b + 0.3, 0.05) * front ** 4)
        p += F * (0.009 * gauss(b - 0.24, 0.07) * gauss(abs(c) - 0.35, 0.3) * front ** 3)
        p -= F * (0.016 * gauss(abs(c) - 0.36, 0.11) * gauss(b - 0.1, 0.075) * front ** 2)
        p += S * (0.006 * gauss(b + 0.62, 0.15) * gauss(a - 0.55, 0.25) * (1.0 if c > 0 else -1.0))
        p += F * (0.008 * gauss(c, 0.22) * gauss(b + 0.76, 0.12) * front)
        p += U * (-0.004 * gauss(c, 0.25) * gauss(b + 0.45, 0.04) * front ** 3)
        ear = gauss(a + 0.08, 0.16) * gauss(b - 0.02, 0.22) * max(0.0, abs(c) - 0.78) * 5.0
        p += S * (0.017 * ear * (1.0 if c > 0 else -1.0))
        p += F * (0.004 * gauss(abs(c) - 0.5, 0.15) * gauss(b + 0.15, 0.1) * front ** 2)
        p -= F * (0.003 * gauss(abs(c) - 0.22, 0.06) * gauss(b + 0.3, 0.12) * front ** 3)
        if b > 0.3 and a < 0.6:
            p += (p.normalized()) * (0.007 + 0.003 * noise.noise(p * 80.0))
        v.co = to_b(centre + p)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
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
        col = mix(SKIN, (0.62, 0.42, 0.38), 0.3 * max(0.0, noise.noise(g * 30.0)))
        hairline = 0.6 - 1.2 * max(0.0, -a) ** 0.8 + 0.05 * noise.noise(g * 50.0)
        side_burn = abs(c) > 0.82 and a > -0.1 and a < 0.35 and b > -0.05
        if (b > hairline or side_burn) and b > -0.62 and not (abs(c) > 0.9 and abs(b) < 0.25 and a < 0.2):
            col = mix(HAIR, (0.25, 0.2, 0.16), max(0.0, noise.noise(g * 90.0)) * 0.6)
        elif a > 0.6:
            eye = gauss(abs(c) - 0.36, 0.12) * gauss(b - 0.1, 0.06)
            if eye > 0.35:
                col = mix(col, (0.45, 0.3, 0.27), 0.3)
            if eye > 0.62:
                col = (0.78, 0.74, 0.7)
                if gauss(abs(c) - 0.36, 0.05) * gauss(b - 0.1, 0.05) > 0.55:
                    col = (0.2, 0.13, 0.08)
                if gauss(abs(c) - 0.36, 0.025) * gauss(b - 0.1, 0.025) > 0.5:
                    col = (0.02, 0.015, 0.015)
            if abs(b - 0.25 + 0.06 * (abs(c) - 0.35)) < 0.028 and 0.14 < abs(c) < 0.62:
                col = mix(col, HAIR, 0.55)
            if b < -0.25 and a > 0.4:
                col = mix(col, (0.32, 0.28, 0.27), 0.28)
            if gauss(c, 0.09) * gauss(b + 0.12, 0.1) > 0.6:
                col = mix(col, (0.8, 0.5, 0.45), 0.25)
            if gauss(abs(c) - 0.5, 0.15) * gauss(b + 0.15, 0.1) > 0.5:
                col = mix(col, (0.8, 0.48, 0.42), 0.2)
            if abs(b + 0.45) < 0.05 and abs(c) < 0.32:
                col = (0.45, 0.24, 0.24)
            if b < -0.25 and a > 0.4:
                col = mix(col, (0.3, 0.25, 0.22), 0.4 * max(0.0, noise.noise(g * 120.0)))
        return (col[0], col[1], col[2], 0.0)
    paint(obj, colour)
    return obj


def build_skirt():
    bm = bmesh.new()
    rings = []
    nr, ns = 30, 56
    for i in range(nr + 1):
        k = i / nr
        y = lerp(1.0, 0.11, k)
        rx = lerp(0.15, 0.27, smoothstep(0.0, 0.6, k))
        rz = lerp(0.1, 0.17, smoothstep(0.0, 0.6, k))
        ring = []
        for j in range(ns):
            th = j / ns * math.tau
            fold = 1.0 + (0.06 * math.sin(th * 7.0 + 1.3 + k * 1.5) + 0.04 * math.sin(th * 11.0 + 0.4 - k * 2.0)
                          + 0.03 * noise.noise(Vector((math.cos(th) * 3.0, math.sin(th) * 3.0, k * 4.0)))) * smoothstep(0.05, 1.0, k)
            x = math.sin(th) * rx * fold
            z = math.cos(th) * rz * fold
            yy = y + 0.012 * math.sin(th * 5.0 + 2.0) * k
            ring.append(bm.verts.new(to_b(Vector((x, yy, z)))))
        rings.append(ring)
    for i in range(nr):
        for j in range(ns):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % ns], rings[i + 1][(j + 1) % ns], rings[i + 1][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Skirt")
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Skirt", mesh))
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.006
    sol.offset = -1.0
    apply_all(obj)
    for poly in obj.data.polygons:
        poly.use_smooth = True

    def colour(g, n):
        c = cloth(g)
        gloss = 0.08
        if g.y < 0.16:
            c = mix(c, (0.15, 0.14, 0.12), 0.5)
        if g.z < -0.05:
            c, gloss = front_detail(g, Vector((0, 0, -1)), c, gloss)
        return (c[0], c[1], c[2], gloss)
    paint(obj, colour)
    def flat(g):
        k = smoothstep(0.98, 0.8, g.y)
        z = g.z
        if z < -0.075:
            z = -0.075
        elif z > 0.05:
            z = 0.05 + (z - 0.05) * 0.3
        return Vector((g.x * (1.0 + 0.18 * k), g.y, lerp(g.z, z, k)))
    flat_key(obj, flat)
    return obj


def flat_key(obj, fn):
    obj.shape_key_add(name="Basis")
    key = obj.shape_key_add(name="flat")
    for v in obj.data.vertices:
        key.data[v.index].co = to_b(fn(to_g(v.co)))


def z_front(y):
    table = [(1.49, 0.07), (1.4, 0.097), (1.3, 0.114), (1.2, 0.102), (1.1, 0.094), (1.04, 0.14), (0.9, 0.152), (0.7, 0.178), (0.6, 0.19)]
    for (y0, z0), (y1, z1) in zip(table, table[1:]):
        if y1 <= y <= y0:
            return lerp(z0, z1, (y0 - y) / (y0 - y1))
    return table[0][1] if y > 1.49 else table[-1][1]


def build_eyes():
    centre = Vector((0.0, 1.69, -0.015))
    objs = []
    for sx in (-1, 1):
        eye_c = centre + Vector((sx * 0.0285, 0.0118, -0.067))
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=12, radius=0.0125)
        for v in bm.verts:
            v.co = to_b(eye_c + Vector((v.co.x, v.co.z, v.co.y)))
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new("Eye")
        bm.to_mesh(mesh)
        bm.free()
        obj = link(bpy.data.objects.new("Eye", mesh))
        for poly in obj.data.polygons:
            poly.use_smooth = True

        def colour(g, n, eye_c=eye_c):
            d = (g - eye_c).normalized()
            f = -d.z
            c = (0.74, 0.7, 0.66)
            if f > 0.82:
                c = (0.22, 0.15, 0.09)
            if f > 0.95:
                c = (0.02, 0.015, 0.015)
            return (c[0], c[1], c[2], 0.35)
        paint(obj, colour)
        objs.append(obj)
    return objs


def build_stole():
    bm = bmesh.new()
    strips = []
    for sx in (-1, 1):
        rows = []
        for i in range(41):
            k = i / 40
            y = lerp(1.5, 0.66, k)
            xc = sx * lerp(0.05, 0.078, smoothstep(0.0, 0.4, k))
            half = lerp(0.026, 0.04, smoothstep(0.0, 0.3, k))
            row = []
            for j in range(5):
                u = (j / 4) * 2 - 1
                x = xc + u * half
                z = -(z_front(y) + 0.009 + 0.004 * (1 - u * u))
                if y > 1.44:
                    z = lerp(z, -0.03, smoothstep(1.44, 1.5, y))
                    x = lerp(x, sx * 0.055 + u * half, smoothstep(1.44, 1.5, y))
                row.append(bm.verts.new(to_b(Vector((x, y, z)))))
            rows.append(row)
        for i in range(40):
            for j in range(4):
                bm.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
    for f in bm.faces:
        if to_g(f.normal).z > 0:
            f.normal_flip()
    mesh = bpy.data.meshes.new("Stole")
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Stole", mesh))
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.004
    sol.offset = 1.0
    apply_all(obj)
    for poly in obj.data.polygons:
        poly.use_smooth = True

    def colour(g, n):
        xc = math.copysign(lerp(0.05, 0.078, smoothstep(1.5, 0.84, g.y)), g.x)
        half = lerp(0.026, 0.04, smoothstep(1.5, 0.93, g.y))
        u = (g.x - xc) / half
        c = mix(STOLE, (0.16, 0.03, 0.18), 0.4 * max(0.0, noise.noise(g * 30.0)))
        gloss = 0.2
        if abs(u) > 0.78:
            c, gloss = GOLD, 0.6
        q = Vector((g.x - xc, g.y - 0.79, 0))
        if (abs(q.x) < 0.006 and abs(q.y) < 0.03) or (abs(q.y + 0.006) < 0.006 and abs(q.x) < 0.02):
            c, gloss = GOLD, 0.6
        if g.y < 0.685:
            c, gloss = mix(GOLD, (0.3, 0.2, 0.08), 0.4), 0.3
        return (c[0], c[1], c[2], gloss)
    paint(obj, colour)
    flat_key(obj, lambda g: Vector((g.x, g.y, max(g.z, -0.085) if g.y < 1.0 else g.z)))
    return obj


def build_cincture():
    bm = bmesh.new()
    rings = []
    for i in range(4):
        y = lerp(1.0, 1.055, i / 3)
        bulge = 1.0 + 0.04 * math.sin(math.pi * i / 3)
        rings.append([bm.verts.new(to_b(Vector((math.sin(j / 40 * math.tau) * 0.158 * bulge, y, math.cos(j / 40 * math.tau) * 0.104 * bulge)))) for j in range(40)])
    for i in range(3):
        for j in range(40):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % 40], rings[i + 1][(j + 1) % 40], rings[i + 1][j]))
    rows = []
    for i in range(16):
        k = i / 15
        y = lerp(1.03, 0.62, k)
        x = -0.16 - lerp(0.0, 0.11, smoothstep(0.0, 1.0, k)) * 0.3
        z = lerp(-0.03, -0.06, k)
        rows.append([bm.verts.new(to_b(Vector((x, y, z + dz)))) for dz in (-0.024, 0.024)])
    for i in range(15):
        bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Cincture")
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Cincture", mesh))
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.004
    apply_all(obj)
    for poly in obj.data.polygons:
        poly.use_smooth = True

    def colour(g, n):
        c = mix((0.04, 0.03, 0.045), (0.09, 0.07, 0.1), max(0.0, noise.noise(g * Vector((200.0, 20.0, 200.0)))))
        if g.y < 0.66:
            c = (0.1, 0.08, 0.1)
        return (c[0], c[1], c[2], 0.25)
    paint(obj, colour)
    flat_key(obj, lambda g: Vector((g.x, g.y, max(g.z, -0.08) if g.y < 1.0 else g.z)))
    return obj


def bone_segment(name):
    b = BONE[name]
    return Vector(b[2]), Vector(b[3])


SETS = {
    "palm": ["forearm_l", "hand_l", "forearm_r", "hand_r"],
    "tip": ["hand_l", "hand_r"],
    "torso": ["hips", "spine", "chest", "neck", "upperarm_l", "upperarm_r", "thigh_l", "thigh_r"],
    "collar": ["chest", "neck", "head"],
    "neck": ["neck", "head", "chest"],
    "sleeve": ["chest", "upperarm_l", "forearm_l", "hand_l", "upperarm_r", "forearm_r", "hand_r"],
    "skin": ["forearm_l", "hand_l", "forearm_r", "hand_r"],
    "leg": ["hips", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"],
    "shoe": ["shin_l", "foot_l", "shin_r", "foot_r"],
}


def weigh_by_distance(obj, candidates, falloff=0.025):
    groups = {n: obj.vertex_groups.get(n) or obj.vertex_groups.new(name=n) for n in candidates}
    segs = {n: bone_segment(n) for n in candidates}
    for v in obj.data.vertices:
        g = to_g(v.co)
        lab = LABELS[v.index]
        cands = [n for n in SETS[lab] if not (lab == "torso" and n.startswith("upperarm") and g.y < 1.37)]
        ds = sorted((seg_dist(g, *segs[n])[0], n) for n in cands)
        top = ds[:3]
        ws = [(math.exp(-(d - top[0][0]) / falloff), n) for d, n in top]
        total = sum(w for w, _ in ws)
        for w, n in ws:
            if w / total > 0.02:
                groups[n].add([v.index], w / total, "REPLACE")


def weigh_drape(obj):
    names = ["hips", "spine", "chest", "thigh_l", "thigh_r", "shin_l", "shin_r"]
    groups = {n: obj.vertex_groups.new(name=n) for n in names}
    for v in obj.data.vertices:
        g = to_g(v.co)
        left = smoothstep(0.03, -0.03, g.x)
        w = {}
        if g.y > 1.04:
            up = smoothstep(1.22, 1.36, g.y)
            mid = smoothstep(1.04, 1.16, g.y)
            w = {"chest": up, "spine": (1 - up) * mid, "hips": (1 - up) * (1 - mid)}
        else:
            top = smoothstep(0.86, 1.0, g.y)
            low = smoothstep(0.62, 0.42, g.y)
            w = {"hips": top, "thigh_l": (1 - top) * left * (1 - low), "thigh_r": (1 - top) * (1 - left) * (1 - low),
                 "shin_l": (1 - top) * left * low, "shin_r": (1 - top) * (1 - left) * low}
        for n, x in w.items():
            if x > 0.01:
                groups[n].add([v.index], x, "REPLACE")


def weigh_skirt(obj):
    names = ["hips", "thigh_l", "thigh_r", "shin_l", "shin_r"]
    groups = {n: obj.vertex_groups.new(name=n) for n in names}
    for v in obj.data.vertices:
        g = to_g(v.co)
        top = smoothstep(0.86, 0.99, g.y)
        left = smoothstep(0.1, -0.1, g.x)
        low = smoothstep(0.62, 0.42, g.y)
        w = {
            "hips": top,
            "thigh_l": (1 - top) * left * (1 - low),
            "thigh_r": (1 - top) * (1 - left) * (1 - low),
            "shin_l": (1 - top) * left * low,
            "shin_r": (1 - top) * (1 - left) * low,
        }
        for n, x in w.items():
            if x > 0.01:
                groups[n].add([v.index], x, "REPLACE")


def bake(obj):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.25
    mat = bpy.data.materials.new("Body")
    mat.use_nodes = True
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    mesh = obj.data
    ao = mesh.color_attributes.new("AO", "FLOAT_COLOR", "CORNER")
    mesh.color_attributes.active_color = ao
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    scene.render.bake.target = "VERTEX_COLORS"
    bpy.ops.object.bake(type="AO")
    base = mesh.color_attributes["Base"]
    col = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for loop in mesh.loops:
        b = base.data[loop.vertex_index].color
        a = ao.data[loop.index].color[0]
        k = 0.35 + 0.65 * a
        col.data[loop.index].color = (b[0] * k, b[1] * k, b[2] * k, b[3])
    mesh.color_attributes.remove(mesh.color_attributes["AO"])
    mesh.color_attributes.remove(mesh.color_attributes["Base"])
    mesh.color_attributes.active_color = mesh.color_attributes["Col"]
    mesh.color_attributes.render_color_index = 0


def build_armature():
    arm_data = bpy.data.armatures.new("Rig")
    arm = link(bpy.data.objects.new("Rig", arm_data))
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, head, tail, _ in BONES:
        eb = arm_data.edit_bones.new(name)
        eb.head = to_b(Vector(head))
        eb.tail = to_b(Vector(tail))
        eb.roll = 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def rot(x=0.0, y=0.0, z=0.0):
    return Euler((math.radians(x), math.radians(y), math.radians(z)), "XYZ").to_matrix()


def solve(pose):
    R = {}
    H = {}
    for name, parent, head, tail, _ in BONES:
        rel = rot(*pose.get(name, (0, 0, 0)))
        if parent is None:
            R[name] = rel
            H[name] = Vector(head)
        else:
            R[name] = R[parent] @ rel
            H[name] = H[parent] + R[parent] @ (Vector(head) - Vector(BONE[parent][2]))
    low = 1e9
    only = pose.get("_ground")
    for name, parent, head, tail, r in BONES:
        if only and name not in only:
            continue
        a = H[name]
        b = a + R[name] @ (Vector(tail) - Vector(head))
        for k in range(4):
            p = a.lerp(b, k / 3.0)
            rr = r * (1.25 if name == "head" else 1.0)
            if name == "head":
                p = a.lerp(b, 0.45)
            low = min(low, p.y - rr)
    kx = (H["shin_l"].x + H["shin_r"].x) * 0.5
    kz = (H["shin_l"].z + H["shin_r"].z) * 0.5
    shift = Vector((-kx, -low + pose.get("_lift", 0.0), -kz)) + Vector(pose.get("_off", (0, 0, 0)))
    for n in H:
        H[n] = H[n] + shift
    return R, H


def key_pose(arm, frame, pose):
    R, H = solve(pose)
    bpy.context.scene.frame_set(frame)
    for name, parent, head, tail, _ in BONES:
        pb = arm.pose.bones[name]
        rest = arm.data.bones[name].matrix_local.to_3x3()
        m = (G2B3 @ R[name] @ G2B3.inverted()) @ rest
        mat = m.to_4x4()
        mat.translation = to_b(H[name])
        pb.matrix = mat
        bpy.context.view_layer.update()
    for name, *_ in BONES:
        pb = arm.pose.bones[name]
        pb.rotation_mode = "QUATERNION"
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


POSES = [
    (0.0, {"spine": (3, 0, 0), "upperarm_l": (40, 0, -8), "forearm_l": (60, 0, 0),
           "upperarm_r": (25, 0, 8), "forearm_r": (45, 0, 0)}),
    (0.18, {"spine": (12, 0, 4), "chest": (8, 0, 2), "neck": (10, 0, 0), "head": (14, 12, 0),
            "upperarm_l": (70, 0, -30), "forearm_l": (35, 0, 0), "upperarm_r": (55, 0, 35), "forearm_r": (25, 0, 0),
            "thigh_l": (10, 0, 0), "shin_l": (-18, 0, 0), "thigh_r": (14, 0, 0), "shin_r": (-24, 0, 0),
            "_off": (0, 0, 0.05)}),
    (0.42, {"spine": (-12, 0, 6), "chest": (-8, 0, 3), "neck": (-10, 0, 0), "head": (-20, 8, 0),
            "upperarm_l": (25, 0, -14), "forearm_l": (20, 0, 0), "upperarm_r": (20, 0, 14), "forearm_r": (18, 0, 0),
            "thigh_l": (35, 0, 0), "shin_l": (-70, 0, 0), "thigh_r": (40, 0, 0), "shin_r": (-78, 0, 0),
            "foot_l": (-20, 0, 0), "foot_r": (-20, 0, 0)}),
    (0.6, {"hips": (4, 0, 0), "spine": (-22, 0, 4), "chest": (-12, 0, 3), "neck": (-12, 0, 0), "head": (-25, 6, 0),
           "upperarm_l": (6, 0, -8), "forearm_l": (12, 0, 0), "upperarm_r": (4, 0, 8), "forearm_r": (14, 0, 0),
           "thigh_l": (8, 0, 0), "shin_l": (-98, 0, 0), "thigh_r": (6, 0, 0), "shin_r": (-96, 0, 0),
           "foot_l": (-55, 0, 0), "foot_r": (-55, 0, 0)}),
    (0.78, {"hips": (2, 0, 0), "spine": (-8, 0, 2), "chest": (-4, 0, 2), "neck": (-8, 0, 0), "head": (-30, 4, 6),
            "upperarm_l": (0, 0, -6), "forearm_l": (8, 0, 0), "upperarm_r": (-2, 0, 6), "forearm_r": (10, 0, 0),
            "thigh_l": (4, 0, 0), "shin_l": (-94, 0, 0), "thigh_r": (3, 0, 0), "shin_r": (-93, 0, 0),
            "foot_l": (-60, 0, 0), "foot_r": (-60, 0, 0), "_lift": 0.0}),
    (1.45, {"hips": (-2, 0, 0), "spine": (-14, 0, 5), "chest": (-7, 0, 4), "neck": (-14, 0, 4), "head": (-42, 12, 10),
            "upperarm_l": (-2, 0, -4), "forearm_l": (6, 0, 0), "upperarm_r": (0, 0, 5), "forearm_r": (8, 0, 0),
            "thigh_l": (2, 0, 0), "shin_l": (-92, 0, 0), "thigh_r": (2, 0, 0), "shin_r": (-92, 0, 0),
            "foot_l": (-60, 0, 0), "foot_r": (-60, 0, 0)}),
    (1.8, {"hips": (-28, 0, 2), "spine": (-14, 0, 4), "chest": (-6, 0, 3), "neck": (-10, 0, 3), "head": (-30, 10, 8),
           "upperarm_l": (18, 0, -10), "forearm_l": (12, 0, 0), "upperarm_r": (22, 0, 10), "forearm_r": (14, 0, 0),
           "thigh_l": (0, 0, 0), "shin_l": (-64, 0, 0), "thigh_r": (0, 0, 0), "shin_r": (-64, 0, 0),
           "foot_l": (-60, 0, 0), "foot_r": (-60, 0, 0)}),
    (2.06, {"hips": (-58, 0, 3), "spine": (-8, 0, 3), "chest": (-4, 0, 2), "neck": (-6, 0, 2), "head": (-12, 20, 6),
            "upperarm_l": (50, 0, -22), "forearm_l": (16, 0, 0), "upperarm_r": (58, 0, 22), "forearm_r": (14, 0, 0),
            "thigh_l": (0, 0, 0), "shin_l": (-34, 0, 0), "thigh_r": (0, 0, 0), "shin_r": (-32, 0, 0),
            "foot_l": (-60, 0, 0), "foot_r": (-60, 0, 0)}),
    (2.22, {"hips": (-86, 0, 3), "spine": (4, 0, 2), "chest": (2, 0, 1), "neck": (4, 0, 0), "head": (6, 8, 0),
            "upperarm_l": (40, 0, -70), "forearm_l": (30, 0, -20), "upperarm_r": (30, 0, 25), "forearm_r": (10, 0, 0),
            "thigh_l": (0, -6, -3), "shin_l": (-8, 0, 0), "thigh_r": (0, 8, 4), "shin_r": (-10, 0, 0),
            "foot_l": (-70, 0, 0), "foot_r": (-70, 0, 0)}),
    (2.34, {"hips": (-93, 0, 4), "spine": (1, 0, 3), "chest": (0, 0, 1), "neck": (2, 0, 0), "head": (-2, 0, 1),
            "upperarm_l": (22, 0, -100), "forearm_l": (12, 0, -45), "hand_l": (15, 0, 0),
            "upperarm_r": (18, 0, 14), "forearm_r": (2, 70, 0),
            "thigh_l": (0, -12, -5), "shin_l": (-4, 0, 0), "thigh_r": (0, 18, 8), "shin_r": (-16, 0, 0),
            "foot_l": (-76, 0, 0), "foot_r": (-70, 0, 0), "_lift": 0.025}),
    (2.55, {"hips": (-90, 0, 4), "spine": (2, 0, 3), "chest": (1, 0, 2), "neck": (2, 0, 0), "head": (-3, 0, 2),
            "upperarm_l": (16, 0, -104), "forearm_l": (10, 0, -52), "hand_l": (18, 0, -8),
            "upperarm_r": (15, 0, 13), "forearm_r": (2, 88, 0), "hand_r": (6, 0, 0),
            "thigh_l": (0, -14, -6), "shin_l": (-5, 0, 0), "thigh_r": (0, 22, 10), "shin_r": (-20, 0, 0),
            "foot_l": (-80, 0, 0), "foot_r": (-72, 0, 0)}),
    (2.9, {"hips": (-90, 0, 4), "spine": (2, 0, 3), "chest": (1, 0, 2), "neck": (2, 0, 0), "head": (-3, 0, 3),
           "upperarm_l": (16, 0, -106), "forearm_l": (11, 0, -55), "hand_l": (20, 0, -12),
           "upperarm_r": (15, 0, 13), "forearm_r": (2, 90, 0), "hand_r": (8, 0, 0),
           "thigh_l": (0, -15, -6), "shin_l": (-5, 0, 0), "thigh_r": (0, 23, 10), "shin_r": (-21, 0, 0),
           "foot_l": (-82, 0, 0), "foot_r": (-74, 0, 0)}),
]


FEET = ["foot_l", "foot_r", "shin_l", "shin_r"]
PEW_POSES = [
    POSES[0],
    POSES[1],
    (0.42, {"hips": (-12, 0, 0), "spine": (-18, 0, 3), "chest": (-10, 0, 2), "neck": (-8, 0, 0), "head": (-18, 6, 0),
            "upperarm_l": (70, 0, -18), "forearm_l": (25, 0, 0), "upperarm_r": (62, 0, 16), "forearm_r": (22, 0, 0),
            "thigh_l": (22, 0, 0), "shin_l": (-30, 0, 0), "thigh_r": (8, 0, 0), "shin_r": (-14, 0, 0),
            "foot_l": (8, 0, 0), "_ground": FEET}),
    (0.62, {"hips": (-62, 0, 2), "spine": (-22, 0, 3), "chest": (-12, 0, 2), "neck": (-10, 0, 0), "head": (-22, 8, 2),
            "upperarm_l": (118, 0, -24), "forearm_l": (30, 0, 0), "upperarm_r": (112, 0, 22), "forearm_r": (28, 0, 0),
            "thigh_l": (60, 0, -2), "shin_l": (-14, 0, 0), "thigh_r": (56, 0, 3), "shin_r": (-10, 0, 0),
            "foot_l": (-10, 0, 0), "foot_r": (-10, 0, 0), "_ground": FEET}),
    (0.8, {"hips": (-94, 0, 3), "spine": (-23, 0, 3), "chest": (-18, 0, 2), "neck": (-5, 0, 0), "head": (-16, 12, 4),
           "upperarm_l": (136, 0, -8), "forearm_l": (80, 0, 0), "hand_l": (-30, 0, 0),
           "upperarm_r": (136, 0, 13), "forearm_r": (76, 0, 0), "hand_r": (-30, 0, 0),
           "thigh_l": (90, 0, -3), "shin_l": (-12, 0, 0), "thigh_r": (86, 0, 4), "shin_r": (-8, 0, 0),
           "foot_l": (-38, 0, 0), "foot_r": (-34, 0, 0), "_ground": FEET}),
    (0.98, {"hips": (-88, 0, 3), "spine": (-20, 0, 3), "chest": (-16, 0, 2), "neck": (-4, 0, 0), "head": (-14, 12, 4),
            "upperarm_l": (132, 0, -8), "forearm_l": (84, 0, 0), "hand_l": (-26, 0, 0),
            "upperarm_r": (132, 0, 13), "forearm_r": (80, 0, 0), "hand_r": (-26, 0, 0),
            "thigh_l": (84, 0, -3), "shin_l": (-12, 0, 0), "thigh_r": (80, 0, 4), "shin_r": (-8, 0, 0),
            "foot_l": (-36, 0, 0), "foot_r": (-32, 0, 0), "_ground": FEET}),
    (1.3, {"hips": (-95, 0, 3), "spine": (-25, 0, 4), "chest": (-20, 0, 3), "neck": (-6, 0, 0), "head": (-19, 16, 7),
           "upperarm_l": (140, 0, -6), "forearm_l": (84, 0, 0), "hand_l": (-38, 0, 0),
           "upperarm_r": (140, 0, 12), "forearm_r": (80, 0, 0), "hand_r": (-38, 0, 0),
           "thigh_l": (91, 0, -3), "shin_l": (-13, 0, 0), "thigh_r": (87, 0, 4), "shin_r": (-9, 0, 0),
           "foot_l": (-40, 0, 0), "foot_r": (-36, 0, 0), "_ground": FEET}),
    (1.8, {"hips": (-95, 0, 3), "spine": (-25, 0, 4), "chest": (-20, 0, 3), "neck": (-6, 0, 0), "head": (-20, 17, 8),
           "upperarm_l": (140, 0, -6), "forearm_l": (84, 0, 0), "hand_l": (-42, 0, 0),
           "upperarm_r": (140, 0, 12), "forearm_r": (80, 0, 0), "hand_r": (-42, 0, 0),
           "thigh_l": (91, 0, -3), "shin_l": (-13, 0, 0), "thigh_r": (87, 0, 4), "shin_r": (-9, 0, 0),
           "foot_l": (-41, 0, 0), "foot_r": (-37, 0, 0), "_ground": FEET}),
]


def animate(arm, name, poses):
    scene = bpy.context.scene
    scene.render.fps = FPS
    arm.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data.action = action
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for t, pose in poses:
        key_pose(arm, int(round(t * FPS)) + 1, pose)
    bpy.ops.object.mode_set(mode="OBJECT")
    scene.frame_start = 1
    scene.frame_end = int(round(poses[-1][0] * FPS)) + 1
    try:
        curves = action.fcurves
    except AttributeError:
        curves = []
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    curves.extend(bag.fcurves)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = build_body()
    head = build_head()
    eyes = build_eyes()
    skirt = build_skirt()
    stole = build_stole()
    cincture = build_cincture()
    weigh_drape(stole)
    weigh_drape(cincture)
    weigh_by_distance(body, [b[0] for b in BONES])
    hg = head.vertex_groups.new(name="head")
    hg.add([v.index for v in head.data.vertices], 1.0, "REPLACE")
    for e in eyes:
        e.vertex_groups.new(name="head").add([v.index for v in e.data.vertices], 1.0, "REPLACE")
    weigh_skirt(skirt)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [body, head, skirt, stole, cincture] + eyes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "PlayerBody"
    bake(body)
    arm = build_armature()
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    body.parent = arm
    animate(arm, "die_pew", PEW_POSES)
    track = arm.animation_data.nla_tracks.new()
    track.strips.new("die_pew", 1, arm.animation_data.action)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    animate(arm, "die", POSES)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm.select_set(True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    kwargs = dict(filepath=OUT, export_format="GLB", export_yup=True, use_selection=True,
                  export_normals=True, export_animations=True, export_skins=True, export_morph=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kwargs)
    print("make_player: wrote", OUT, "triangles:", sum(len(p.vertices) - 2 for p in body.data.polygons))


main()
