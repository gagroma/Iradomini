import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "models", "demon_body.glb"))

rng = random.Random(7)
G2B = Matrix.Rotation(math.radians(90.0), 4, "X")

W_HIP = Vector((0, 1.05, 0))
W_NECK = Vector((0, 1.95, 0.4))
W_SHOULDER = Vector((0.24, 1.84, 0.24))
W_ELBOW = Vector((0.42, 1.28, 0.36))
W_WRIST = Vector((0.33, 0.6, 0.58))
W_LEG = Vector((0.12, 1.0, 0.0))
W_KNEE = Vector((0.21, 0.55, 0.2))
W_ANKLE = Vector((0.17, 0.09, -0.04))

SKIN = (0.035, 0.03, 0.038)
SKIN_PALE = (0.11, 0.09, 0.095)
EMBER_CRACK = (1.0, 0.32, 0.05)
VEIN = (0.22, 0.05, 0.035)
BONE = (0.46, 0.4, 0.31)
BONE_DARK = (0.16, 0.12, 0.1)
RAG = (0.03, 0.025, 0.035)
GUM = (0.2, 0.03, 0.03)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(lerp(c1[k], c2[k], t) for k in range(3))


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def gauss(x, w):
    return math.exp(-(x * x) / (w * w))


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_all(obj):
    select_only(obj)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length, t


def to_g(co):
    return Vector((co.x, co.z, -co.y))


def to_b(g):
    return G2B @ g


def skin_part(name, points, edges, subdiv=2):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([to_b(Vector(p[0])) for p in points], edges, [])
    obj = link(bpy.data.objects.new(name, mesh))
    mod = obj.modifiers.new("Skin", "SKIN")
    mod.use_smooth_shade = True
    mod.branch_smoothing = 0.6
    sv = obj.data.skin_vertices[0].data
    for i, p in enumerate(points):
        r = p[1]
        sv[i].radius = (r, r) if isinstance(r, float) else r
    sv[0].use_root = True
    sub = obj.modifiers.new("Sub", "SUBSURF")
    sub.levels = subdiv
    sub.render_levels = subdiv
    apply_all(obj)
    return obj


def shape(obj, fn):
    obj.data.update()
    for v in obj.data.vertices:
        g = to_g(v.co)
        n = to_g(v.normal)
        v.co = to_b(fn(g, n))
    obj.data.update()


def paint(obj, fn):
    mesh = obj.data
    attr = mesh.color_attributes.get("Base") or mesh.color_attributes.new("Base", "FLOAT_COLOR", "POINT")
    for v in mesh.vertices:
        attr.data[v.index].color = fn(to_g(v.co), to_g(v.normal))


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


def wrinkle(g, n, amount=0.006, freq=34.0):
    w = noise.noise(g * freq) * 0.6 + noise.noise(g * freq * 2.7) * 0.4
    ridge = 1.0 - abs(noise.noise(g * freq * 0.6 + Vector((3.1, 0.0, 0.0))))
    return g + n * (w * amount + (ridge - 0.7) * amount * 0.6)


def skin_colour(g, n, pale=0.0):
    m = noise.noise(g * 9.0) * 0.5 + 0.5
    col = mix(SKIN, SKIN_PALE, m * 0.55 + pale)
    vein = 1.0 - abs(noise.noise(g * 14.0 + Vector((7.0, 1.0, 2.0))))
    col = mix(col, VEIN, smoothstep(0.86, 0.97, vein) * 0.55)
    up = max(0.0, n.y)
    col = mix(col, SKIN_PALE, up * 0.15)
    return col


def finish(g, col, a=0.0, amount=1.0):
    crack = 1.0 - abs(noise.noise(g * 6.5 + Vector((1.3, 7.1, 2.2))))
    mask = smoothstep(0.05, 0.35, noise.noise(g * 2.2 + Vector((4.0, 0.0, 9.0))))
    if amount > 0.0 and crack > 0.982 and mask * amount > 0.3:
        return (*EMBER_CRACK, 1.0)
    if amount > 0.0 and crack > 0.95 and mask * amount > 0.3:
        return (*mix(col, (0.3, 0.06, 0.02), 0.7), min(a, 0.8))
    return (*col, min(a, 0.8))


def bone_colour(g, root_t):
    m = noise.noise(g * 30.0) * 0.5 + 0.5
    col = mix(BONE_DARK, BONE, root_t)
    return mix(col, mix(col, (0.62, 0.56, 0.45), 0.5), m * 0.4)



def build_hips():
    pts = [
        ((0, 1.08, 0.0), (0.15, 0.12)),
        ((0, 1.18, 0.02), 0.12),
        ((0.13, 1.0, 0.0), 0.085),
        ((-0.13, 1.0, 0.0), 0.085),
        ((0, 0.96, 0.05), 0.08),
    ]
    body = skin_part("hips_body", pts, [(0, 1), (0, 2), (0, 3), (0, 4)])
    shape(body, lambda g, n: wrinkle(g, n))
    paint(body, lambda g, n: finish(g, skin_colour(g, n)))
    rags = [body]
    for k in range(11):
        a = -2.6 + 5.2 * k / 10.0 + rng.uniform(-0.12, 0.12)
        rags.append(build_rag(a, k))
    return join(rags, "hips")


def build_rag(angle, k):
    top_r = 0.17
    length = rng.uniform(0.35, 0.7)
    width = rng.uniform(0.07, 0.12)
    rows, cols = 12, 4
    centre = Vector((math.sin(angle) * top_r, 1.04, -math.cos(angle) * top_r * 0.85))
    out = Vector((math.sin(angle), 0.0, -math.cos(angle) * 0.85)).normalized()
    side = Vector((0, 1, 0)).cross(out).normalized()
    bm = bmesh.new()
    grid = []
    for i in range(rows + 1):
        t = i / rows
        row = []
        for j in range(cols + 1):
            u = j / cols - 0.5
            w = width * (1.0 - 0.35 * t)
            p = centre + side * (u * w) - Vector((0, 1, 0)) * (t * length) + out * (t * t * 0.06)
            p += out * (0.02 * math.sin(t * 7.0 + k + u * 3.0)) + side * (0.015 * math.sin(t * 5.0 + k * 1.7))
            row.append(bm.verts.new(to_b(p)))
        grid.append(row)
    for i in range(rows):
        for j in range(cols):
            if i > rows * 0.55 and rng.random() < 0.18 * (i / rows):
                continue
            bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    mesh = bpy.data.meshes.new("rag")
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("rag", mesh))
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.006
    apply_all(obj)
    for poly in obj.data.polygons:
        poly.use_smooth = True

    def colour(g, n):
        m = noise.noise(g * 25.0) * 0.5 + 0.5
        col = mix(RAG, (0.07, 0.055, 0.06), m)
        stain = smoothstep(0.3, 0.7, noise.noise(g * 6.0 + Vector((2.0, 5.0, 1.0))))
        return (*mix(col, (0.06, 0.02, 0.015), stain * 0.6), 0.0)
    paint(obj, colour)
    return obj


TORSO = [
    ((0, 1.08, 0.0), 0.12),
    ((0, 1.28, 0.03), (0.105, 0.085)),
    ((0, 1.46, 0.08), (0.15, 0.12)),
    ((0, 1.64, 0.15), (0.17, 0.13)),
    ((0, 1.8, 0.25), (0.15, 0.12)),
    ((0, 1.92, 0.36), 0.08),
]


def build_spine():
    pts = list(TORSO)
    pts += [((0.2, 1.84, 0.25), 0.075), ((0.27, 1.84, 0.24), 0.07)]
    pts += [((-0.2, 1.84, 0.25), 0.075), ((-0.27, 1.84, 0.24), 0.07)]
    edges = [(i, i + 1) for i in range(5)] + [(4, 6), (6, 7), (4, 8), (8, 9)]
    obj = skin_part("spine_body", pts, edges)
    axis = [Vector(p[0]) for p in TORSO]

    def where(g):
        best = None
        for i in range(len(axis) - 1):
            d, t = seg_dist(g, axis[i], axis[i + 1])
            if best is None or d < best[0]:
                best = (d, (i + t) / (len(axis) - 1), axis[i].lerp(axis[i + 1], t), (axis[i + 1] - axis[i]).normalized())
        return best

    def sculpt(g, n):
        d, s, c, tang = where(g)
        radial = g - c
        radial -= tang * radial.dot(tang)
        if radial.length < 1e-6:
            return g
        rd = radial.normalized()
        back = Vector((0, 0.35, -1.0)).normalized()
        front = -back
        fr = rd.dot(front)
        bk = rd.dot(back)
        out = 0.0
        rib_zone = smoothstep(0.32, 0.45, s) * (1.0 - smoothstep(0.8, 0.92, s))
        rib = max(0.0, math.sin(s * 58.0 - 0.7)) ** 3
        out += 0.03 * rib * rib_zone * (1.0 - max(0.0, bk) * 0.5) - 0.012 * rib_zone * (1.0 - rib)
        out -= 0.045 * smoothstep(0.08, 0.3, s) * (1.0 - smoothstep(0.3, 0.42, s)) * max(0.0, fr)
        out += 0.012 * gauss(rd.x, 0.12) * max(0.0, fr) * rib_zone
        vert = max(0.0, math.sin(s * 70.0)) ** 5
        out += 0.045 * vert * gauss(abs(rd.dot(Vector((1, 0, 0)))), 0.18) * max(0.0, bk) ** 2
        hipbone = gauss(abs(rd.x) - 0.75, 0.2) * gauss(s - 0.05, 0.08)
        out += 0.025 * hipbone
        blade = gauss(abs(rd.x) - 0.6, 0.2) * gauss(s - 0.78, 0.08) * max(0.0, bk)
        out += 0.02 * blade
        clav = gauss(s - 0.88, 0.04) * max(0.0, fr) * gauss(abs(rd.x) - 0.5, 0.3)
        out += 0.014 * clav
        g = g + rd * out
        return wrinkle(g, n, 0.003)

    shape(obj, sculpt)

    def colour(g, n):
        d, s, c, tang = where(g)
        rib = max(0.0, math.sin(s * 58.0 - 0.7)) ** 3
        zone = smoothstep(0.32, 0.45, s) * (1.0 - smoothstep(0.8, 0.92, s))
        vert = max(0.0, math.sin(s * 70.0)) ** 5
        col = skin_colour(g, n, 0.3 * rib * zone)
        col = mix(col, (0.26, 0.22, 0.2), vert * 0.5 * max(0.0, n.y - n.z))
        return finish(g, col)
    paint(obj, colour)
    return join([obj] + build_back_spikes(), "spine")


SKULL_C = Vector((0.0, 2.07, 0.72))
SKULL_R = Vector((0.125, 0.25, 0.165))
MOUTH_Y = -0.3


def mouth_r(ux, uy):
    return math.sqrt((ux / 0.4) ** 2 + ((uy - MOUTH_Y) / 0.66) ** 2)


def brow_y(ux):
    return 0.5 + 0.28 * min(1.0, abs(ux) / 0.6)


def build_skull():
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=72, v_segments=52, radius=1.0)
    for v in bm.verts:
        u = Vector((v.co.x, v.co.z, v.co.y))
        front = max(0.0, u.z)
        low = max(0.0, -u.y)
        rx = SKULL_R.x * (1.0 - 0.5 * low ** 1.2) * (1.0 + 0.12 * max(0.0, u.y))
        rz = SKULL_R.z * (1.0 - 0.3 * low ** 1.5)
        p = Vector((u.x * rx, u.y * SKULL_R.y, u.z * rz))
        p.y -= 0.03 * low ** 2
        ang = math.atan2(u.y - MOUTH_Y, u.x)
        mr = mouth_r(u.x, u.y) + noise.noise(Vector((ang * 3.0, 0.0, 5.0))) * 0.16
        cavity = smoothstep(1.0, 0.7, mr) * front ** 1.5
        lip = gauss(mr - 1.06, 0.1) * front ** 2
        p.z -= 0.085 * cavity
        p.z += 0.01 * lip
        for sx in (-1.0, 1.0):
            sock = gauss(math.hypot((u.x - sx * 0.44) * 1.1, u.y - 0.4), 0.2) * front ** 1.5
            p.z -= 0.06 * sock
            by = brow_y(u.x)
            brow = gauss(u.y - by, 0.07) * gauss(abs(u.x) - 0.42, 0.32) * front
            p.z += 0.03 * brow
            cheek = gauss(u.y - 0.08, 0.07) * gauss(abs(u.x) - 0.7, 0.18) * front
            p.x += sx * 0.02 * cheek * (1 if u.x * sx > 0 else 0)
            hollow = gauss(math.hypot(u.x - sx * 0.62, u.y + 0.25), 0.22) * front
            p.x -= sx * 0.02 * hollow * (1 if u.x * sx > 0 else 0)
            p.z -= 0.012 * hollow
        temple = gauss(abs(u.x) - 0.85, 0.15) * gauss(u.y - 0.45, 0.25)
        p.x -= math.copysign(0.016 * temple, u.x)
        crest = gauss(u.x, 0.08) * smoothstep(0.4, 0.95, u.y)
        p.y += 0.02 * crest
        g = SKULL_C + p
        g += (g - SKULL_C).normalized() * (noise.noise(g * 26.0) * 0.004 + noise.noise(g * 70.0) * 0.0018)
        v.co = to_b(g)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("skull")
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("skull", mesh))
    for poly in obj.data.polygons:
        poly.use_smooth = True

    def colour(g, n):
        d = g - SKULL_C
        ux, uy, uz = d.x / SKULL_R.x, d.y / SKULL_R.y, d.z / SKULL_R.z
        front = max(0.0, uz)
        col = skin_colour(g, n, 0.04)
        bony = 0.0
        for sx in (-1.0, 1.0):
            bony += gauss(uy - brow_y(ux), 0.08) * gauss(abs(ux) - 0.42, 0.3) * front
            bony += gauss(uy - 0.08, 0.08) * gauss(abs(ux) - 0.7, 0.2) * front * 0.5
        bony += gauss(ux, 0.08) * smoothstep(0.4, 0.95, uy) * 0.6
        col = mix(col, (0.2, 0.17, 0.16), min(1.0, bony) * 0.6)
        for sx in (-1.0, 1.0):
            sock = gauss(math.hypot((ux - sx * 0.44) * 1.1, uy - 0.4), 0.17) * front ** 1.5
            col = mix(col, (0.0, 0.0, 0.0), smoothstep(0.3, 0.75, sock))
        mr = mouth_r(ux, uy)
        inside = smoothstep(0.95, 0.72, mr) * front
        col = mix(col, (0.12, 0.012, 0.01), inside)
        lip = gauss(mr - 1.0, 0.09) * front
        col = mix(col, (0.08, 0.015, 0.012), lip * 0.7)
        return finish(g, col, inside * 0.8, 1.0 - inside - smoothstep(0.2, 0.6, front))
    paint(obj, colour)
    return obj


def fang(root, tip, r, dark=0.0):
    obj = skin_part("tooth", [((root.x, root.y, root.z), r), ((root.lerp(tip, 0.55).x, root.lerp(tip, 0.55).y + 0.003, root.lerp(tip, 0.55).z), r * 0.6), ((tip.x, tip.y, tip.z), 0.0006)], [(0, 1), (1, 2)], 1)
    length = max((tip - root).length, 1e-4)
    paint(obj, lambda g, n: (*mix(mix((0.3, 0.22, 0.14), (0.4, 0.33, 0.22), dark), (0.78, 0.72, 0.58), smoothstep(0.0, 1.0, (g - root).length / length)), 0.7))
    return obj


def build_teeth():
    teeth = []
    for sx in (-1.0, 1.0):
        for k in range(11):
            uy = MOUTH_Y - 0.58 + k * 0.105 + rng.uniform(-0.02, 0.02)
            span = 1.0 - ((uy - MOUTH_Y) / 0.66) ** 2
            if span <= 0.08:
                continue
            ux = sx * 0.4 * math.sqrt(span) * 0.92
            uz = math.sqrt(max(0.0, 1.0 - ux * ux - uy * uy * 0.85))
            root = SKULL_C + Vector((ux * SKULL_R.x * (1.0 - 0.5 * max(0.0, -uy) ** 1.2), uy * SKULL_R.y, uz * SKULL_R.z * (1.0 - 0.3 * max(0.0, -uy) ** 1.5) - 0.014))
            length = rng.uniform(0.035, 0.065) * (1.25 if k % 3 == 1 else 1.0)
            tip = root + Vector((-sx * length * 0.85, rng.uniform(-0.02, 0.012), 0.012))
            teeth.append(fang(root, tip, rng.uniform(0.006, 0.0095), rng.random()))
    return teeth


def horn_obj(path, radii, ridge=0.009):
    pts = [(p, r) for p, r in zip(path, radii)]
    obj = skin_part("horn", pts, [(i, i + 1) for i in range(len(pts) - 1)], 2)
    axis = [Vector(p) for p in path]

    def along(g):
        best = None
        for i in range(len(axis) - 1):
            d, t = seg_dist(g, axis[i], axis[i + 1])
            if best is None or d < best[0]:
                best = (d, (i + t) / (len(axis) - 1), axis[i].lerp(axis[i + 1], t))
        return best

    def sculpt(g, n):
        d, s, c = along(g)
        ring = max(0.0, math.sin(s * 95.0)) ** 2 * (1.0 - s) ** 0.6 * ridge
        return g + (g - c).normalized() * ring + n * noise.noise(g * 60.0) * 0.0018

    shape(obj, sculpt)
    paint(obj, lambda g, n: (*mix(bone_colour(g, along(g)[1]), (0.02, 0.018, 0.016), smoothstep(0.75, 1.0, along(g)[1])), 0.25))
    return obj


def build_horn(sx):
    path = [(0.07, 2.22, 0.63), (0.13, 2.36, 0.6), (0.21, 2.48, 0.51), (0.31, 2.55, 0.42), (0.41, 2.54, 0.43), (0.48, 2.49, 0.52), (0.51, 2.48, 0.64), (0.5, 2.52, 0.76)]
    path = [(sx * p[0], p[1], p[2]) for p in path]
    radii = [0.068, 0.062, 0.052, 0.042, 0.032, 0.022, 0.012, 0.003]
    return horn_obj(path, radii)


def build_spikes_crown():
    out = []
    for k in range(5):
        th = 0.35 + k * 0.28
        y = SKULL_C.y + SKULL_R.y * 0.93 * math.cos(th)
        z = SKULL_C.z - SKULL_R.z * 0.93 * math.sin(th)
        nrm = Vector((0.0, math.cos(th) / SKULL_R.y, -math.sin(th) / SKULL_R.z)).normalized()
        back = Vector((0.0, -math.sin(th), -math.cos(th)))
        length = 0.07 - k * 0.008
        root = (0.0, y, z)
        tip_v = Vector(root) + (nrm * 0.75 + back * 0.6).normalized() * length
        mid_v = Vector(root).lerp(tip_v, 0.5) + nrm * 0.008
        out.append(horn_obj([root, tuple(mid_v), tuple(tip_v)], [0.02 - k * 0.002, 0.011, 0.0015], 0.004))
    return out


def build_neck():
    pts = [((0, 1.93, 0.38), 0.075), ((0, 2.03, 0.52), 0.06), ((0, 2.06, 0.62), 0.055)]
    obj = skin_part("neck", pts, [(0, 1), (1, 2)])

    def sculpt(g, n):
        cord = gauss(abs(g.x) - 0.04, 0.012) * 0.016 * max(0.0, n.z + 0.3)
        vert = max(0.0, math.sin(g.z * 60.0)) ** 4 * gauss(g.x, 0.02) * max(0.0, n.y) * 0.016
        return wrinkle(g + n * (cord + vert), n, 0.004)
    shape(obj, sculpt)
    paint(obj, lambda g, n: finish(g, skin_colour(g, n)))
    return obj


def build_head():
    parts = [build_skull(), build_neck(), build_horn(-1.0), build_horn(1.0)] + build_spikes_crown() + build_teeth()
    return join(parts, "head")


def build_back_spikes():
    out = []
    for k in range(6):
        s = 0.16 + k * 0.105
        y = lerp(1.15, 1.88, s)
        z = 0.0
        r = 0.12
        for i in range(len(TORSO) - 1):
            y0, y1 = TORSO[i][0][1], TORSO[i + 1][0][1]
            if y0 <= y <= y1:
                t = (y - y0) / (y1 - y0)
                z = lerp(TORSO[i][0][2], TORSO[i + 1][0][2], t)
                r0 = TORSO[i][1] if isinstance(TORSO[i][1], float) else TORSO[i][1][1]
                r1 = TORSO[i + 1][1] if isinstance(TORSO[i + 1][1], float) else TORSO[i + 1][1][1]
                r = lerp(r0, r1, t)
        z -= r * 0.4
        y += r * 0.25
        root = (0.0, y, z)
        length = 0.07 + 0.06 * math.sin(math.pi * s)
        tip = (0.0, y + length * 0.6, z - length * 0.8)
        mid = (0.0, (y + tip[1]) / 2 + 0.008, (z + tip[2]) / 2)
        out.append(horn_obj([root, mid, tip], [0.02, 0.012, 0.0015], 0.003))
    for sx in (-1.0, 1.0):
        for k in range(2):
            root = (sx * (0.25 + k * 0.03), 1.89, 0.22 - k * 0.05)
            tip = (sx * (0.33 + k * 0.03), 1.98 - k * 0.02, 0.15 - k * 0.06)
            mid = ((root[0] + tip[0]) / 2, (root[1] + tip[1]) / 2 + 0.01, (root[2] + tip[2]) / 2)
            out.append(horn_obj([root, mid, tip], [0.018, 0.01, 0.0015], 0.003))
    return out


def limb(name, a, b, ra, rb, knob=0.0, bulge=0.0):
    mid = a.lerp(b, 0.35)
    pts = [((a.x, a.y, a.z), ra), ((mid.x, mid.y, mid.z), lerp(ra, rb, 0.35) + bulge), ((b.x, b.y, b.z), rb)]
    obj = skin_part(name, pts, [(0, 1), (1, 2)])

    axis = (b - a).normalized()
    ref = axis.cross(Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((1, 0, 0))).normalized()

    def sculpt(g, n):
        d, t = seg_dist(g, a, b)
        c = a.lerp(b, t)
        rd = g - c
        rd -= axis * rd.dot(axis)
        ang = math.atan2(rd.dot(axis.cross(ref)), rd.dot(ref))
        out = knob * (gauss(t - 1.0, 0.1) + 0.6 * gauss(t, 0.08))
        strands = max(0.0, math.sin(ang * 4.0 + t * 3.0 + noise.noise(g * 8.0) * 2.0)) ** 3
        out += 0.014 * strands * math.sin(math.pi * t) ** 0.6
        out -= 0.01 * math.sin(math.pi * t) * (1.0 - strands)
        return wrinkle(g + n * out, n, 0.005)
    shape(obj, sculpt)

    def colour(g, n):
        d, t = seg_dist(g, a, b)
        bony = gauss(t - 1.0, 0.12) + gauss(t, 0.1) * 0.6
        return finish(g, mix(skin_colour(g, n), (0.24, 0.2, 0.19), bony * 0.5))
    paint(obj, colour)
    return obj


def build_hand(sx):
    w = Vector((W_WRIST.x * sx, W_WRIST.y, W_WRIST.z))
    palm = w + Vector((sx * 0.01, -0.09, 0.04))
    pts = [((w.x, w.y, w.z), 0.034), ((palm.x, palm.y, palm.z), (0.042, 0.022))]
    edges = [(0, 1)]
    fingers = [[-0.07, 0.1], [0.0, 0.16], [0.07, 0.1], [0.1, -0.02]]
    tips = []
    for f in fingers:
        knuck = palm + Vector((sx * f[0] * 0.35, -0.04, f[1] * 0.25))
        j1 = Vector((w.x + sx * f[0] * 0.6, 0.36, w.z + f[1] * 0.7))
        j2 = j1.lerp(Vector((w.x + sx * f[0], 0.12, w.z + f[1])), 0.55)
        tip = Vector((w.x + sx * f[0] * 1.12, 0.02, w.z + f[1] * 1.2 + 0.05))
        chain = [(knuck, 0.017), (j1, 0.013), (j2, 0.01), (tip, 0.0018)]
        prev = 1
        for p, r in chain:
            pts.append(((p.x, p.y, p.z), r))
            edges.append((prev, len(pts) - 1))
            prev = len(pts) - 1
        tips.append((knuck, j1, j2, tip))
    obj = skin_part("hand", pts, edges)

    def finger_t(g):
        best = None
        for knuck, j1, j2, tip in tips:
            for a, b, base in ((knuck, j1, 0.0), (j1, j2, 0.4), (j2, tip, 0.7)):
                d, t = seg_dist(g, a, b)
                s = base + t * (0.4 if base < 0.7 else 0.3)
                if best is None or d < best[0]:
                    best = (d, s, (j1, j2))
        return best

    def sculpt(g, n):
        d, s, joints = finger_t(g)
        out = 0.0
        for j in joints:
            out += 0.01 * gauss((g - j).length, 0.016)
        return wrinkle(g + n * out, n, 0.003, 60.0)
    shape(obj, sculpt)

    def colour(g, n):
        d, s, joints = finger_t(g)
        if g.y > palm.y + 0.02:
            return finish(g, skin_colour(g, n))
        col = mix(skin_colour(g, n), bone_colour(g, 1.0 - s * 0.6), smoothstep(0.05, 0.35, s))
        claw = smoothstep(0.82, 0.95, s)
        col = mix(col, (0.05, 0.04, 0.035), claw)
        return (*col, claw * 0.7)
    paint(obj, colour)
    obj.name = "hand"
    return obj


def build_shin(sx):
    k = Vector((W_KNEE.x * sx, W_KNEE.y, W_KNEE.z))
    a = Vector((W_ANKLE.x * sx, W_ANKLE.y, W_ANKLE.z))
    heel = a + Vector((0, -0.04, -0.04))
    ball = Vector((sx * 0.18, 0.035, 0.17))
    pts = [((k.x, k.y, k.z), 0.058), ((k.lerp(a, 0.3).x, k.lerp(a, 0.3).y, k.lerp(a, 0.3).z), 0.05), ((a.x, a.y, a.z), 0.038),
           ((heel.x, heel.y, heel.z), 0.03), ((ball.x, ball.y, ball.z), (0.045, 0.022))]
    edges = [(0, 1), (1, 2), (2, 3), (2, 4)]
    toes = []
    for dx in (-0.035, 0.0, 0.035):
        mid = ball + Vector((sx * dx, -0.005, 0.07))
        tip = ball + Vector((sx * dx * 1.3, -0.03, 0.14))
        for p, r in ((mid, 0.012), (tip, 0.0015)):
            pts.append(((p.x, p.y, p.z), r))
        edges += [(4, len(pts) - 2), (len(pts) - 2, len(pts) - 1)]
        toes.append(tip)
    obj = skin_part("shin", pts, edges)

    def sculpt(g, n):
        d, t = seg_dist(g, k, a)
        knee = 0.018 * gauss((g - k).length, 0.05) * max(0.0, n.z)
        shinbone = 0.006 * gauss(g.x - k.x, 0.02) * max(0.0, n.z) * (1.0 - t)
        return wrinkle(g + n * (knee + shinbone), n, 0.003)
    shape(obj, sculpt)

    def colour(g, n):
        col = skin_colour(g, n)
        claw = 0.0
        for tip in toes:
            claw = max(claw, 1.0 - smoothstep(0.0, 0.05, (g - tip).length))
        return (*mix(col, (0.05, 0.04, 0.035), claw), claw * 0.7)
    paint(obj, colour)
    obj.name = "shin"
    return obj



def bake(objs):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.25
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    for obj in objs:
        mat = bpy.data.materials.new(obj.name)
        mat.use_nodes = True
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        mesh = obj.data
        ao = mesh.color_attributes.new("AO", "FLOAT_COLOR", "CORNER")
        mesh.color_attributes.active_color = ao
        select_only(obj)
        scene.render.bake.target = "VERTEX_COLORS"
        bpy.ops.object.bake(type="AO")
        base = mesh.color_attributes["Base"]
        col = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        for loop in mesh.loops:
            b = base.data[loop.vertex_index].color
            a = ao.data[loop.index].color[0]
            k = 0.25 + 0.75 * a
            col.data[loop.index].color = (b[0] * k, b[1] * k, b[2] * k, b[3])
        mesh.color_attributes.remove(mesh.color_attributes["AO"])
        mesh.color_attributes.remove(mesh.color_attributes["Base"])
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
        mesh.color_attributes.render_color_index = 0
    bpy.data.objects.remove(ground)


def set_origin(obj, pivot_g):
    pivot = to_b(pivot_g)
    obj.data.transform(Matrix.Translation(-pivot))
    obj.location = pivot


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = {}
    parts["hips"] = (build_hips(), W_HIP)
    parts["spine"] = (build_spine(), W_HIP)
    parts["head"] = (build_head(), W_NECK)
    for sx in (-1.0, 1.0):
        side = "_l" if sx < 0 else "_r"
        m = Vector((sx, 1, 1))
        sh, el, wr = W_SHOULDER * m, W_ELBOW * m, W_WRIST * m
        lg, kn, an = W_LEG * m, W_KNEE * m, W_ANKLE * m
        parts["arm" + side] = (limb("arm", sh, el, 0.062, 0.045, 0.022, 0.01), sh)
        parts["fore" + side] = (limb("fore", el, wr, 0.05, 0.03, 0.018, 0.008), el)
        parts["hand" + side] = (build_hand(sx), wr)
        parts["leg" + side] = (limb("leg", lg, kn, 0.078, 0.055, 0.02, 0.014), lg)
        parts["shin" + side] = (build_shin(sx), kn)
    objs = []
    for name, (obj, pivot) in parts.items():
        obj.name = name
        obj.data.name = name
        objs.append(obj)
    bake(objs)
    for name, (obj, pivot) in parts.items():
        set_origin(obj, pivot)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    kwargs = dict(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True,
                  use_selection=True, export_normals=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kwargs)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    print("make_demon: wrote", OUT, "triangles:", tris)


main()
