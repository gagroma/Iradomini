# MAKE_CANDLE - builds the candle you carry (assets/models/candle.glb).
#
# Run from the project folder (Blender 4.2 or newer, tested on 5.2):
#   blender --background --factory-startup --python tools/make_candle.py
#
# Everything is built from numbers below, so the model can be changed and
# rebuilt at any time. Sizes are in metres. Blender is Z-up; the glTF export
# turns that into Godot's Y-up.
#
# Parts (object names become node names in Godot):
#   Holder - brass chamberstick: a dish, a socket for the candle, a finger ring
#   Spill  - old wax that dripped into the dish (it never burns away)
#   Wax    - the candle body with drips. Godot hides everything above the
#            current burn height, so the drips lower down stay as it burns
#   Cap    - the melted top: a soft rim and the pool of liquid wax around the
#            wick. Godot moves it down as the candle burns
#   Wick   - charred, bent wick with a glowing tip; moves with the Cap
#
# Vertex colours carry the colour. Alpha in the wax colours is "wetness":
# 1 = liquid wax in the pool (glossy), 0 = hard wax.

import math
import os
import random
import sys

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "models", "candle.glb"))
PREVIEW = None
if "--" in sys.argv:
    extra = sys.argv[sys.argv.index("--") + 1:]
    if extra:
        PREVIEW = extra[0]   # optional: path of a PNG preview render

WAX_RADIUS = 0.0118      # the candle is 2.4 cm thick
WAX_BOTTOM = 0.013       # sits inside the socket
WAX_TOP = 0.160          # height of a fresh candle above the dish bottom
SEGMENTS = 32

rng = random.Random(7)


# ------------------------------------------------------------------ helpers

def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def angle_noise(seed, harmonics=4):
    """A smooth random function of the angle around the candle."""
    r = random.Random(seed)
    waves = [(k, r.uniform(0, math.tau), r.uniform(0.3, 1.0) / k) for k in range(1, harmonics + 1)]
    total = sum(w[2] for w in waves)

    def f(a):
        return sum(math.sin(k * a + p) * amp for k, p, amp in waves) / total
    return f


def lathe(name, profile, segments=SEGMENTS, shape=None, colour=None):
    """Spin a (radius, height) profile around Z.
    shape(angle, r, z, i) -> (r, z) lets each point move (drips, uneven rims).
    colour(angle, r, z, i) -> (r, g, b, a) paints each point."""
    bm = bmesh.new()
    rings = []
    for i, (r0, z0) in enumerate(profile):
        if r0 <= 1e-7:
            r, z = (r0, z0) if shape is None else shape(0.0, r0, z0, i)
            v = bm.verts.new((0.0, 0.0, z))
            rings.append([v] * segments)
            continue
        ring = []
        for s in range(segments):
            a = math.tau * s / segments
            r, z = (r0, z0) if shape is None else shape(a, r0, z0, i)
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        a_ring, b_ring = rings[i], rings[i + 1]
        for s in range(segments):
            t = (s + 1) % segments
            quad = [a_ring[s], a_ring[t], b_ring[t], b_ring[s]]
            uniq = []
            for v in quad:
                if v not in uniq:
                    uniq.append(v)
            if len(uniq) >= 3:
                try:
                    bm.faces.new(uniq)
                except ValueError:
                    pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if colour is not None:
        paint(obj, lambda co: colour(math.atan2(co.y, co.x) % math.tau, math.hypot(co.x, co.y), co.z, 0))
    return obj


def paint(obj, fn):
    """Per-corner colour attribute named Col (exported as glTF COLOR_0)."""
    mesh = obj.data
    attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for loop in mesh.loops:
        co = mesh.vertices[loop.vertex_index].co
        attr.data[loop.index].color = fn(co)
    mesh.color_attributes.active_color = attr
    mesh.color_attributes.render_color_index = 0


def smooth(obj, sharp_angle=None):
    mesh = obj.data
    for p in mesh.polygons:
        p.use_smooth = True
    if sharp_angle is not None and hasattr(mesh, "set_sharp_from_angle"):
        mesh.set_sharp_from_angle(angle=sharp_angle)


def material(name):
    """A plain material so the parts arrive in Godot as separate surfaces.
    Godot replaces it with its own shaders anyway."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return m


def hash_noise(x, y, z, scale):
    """Cheap 3D value noise (0..1) for mottling the colours."""
    def h(ix, iy, iz):
        n = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791)
        n = (n << 13) ^ n
        return ((n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff) / 0x7fffffff
    x, y, z = x * scale, y * scale, z * scale
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = [t * t * (3 - 2 * t) for t in (fx, fy, fz)]

    def lerp(a, b, t):
        return a + (b - a) * t
    c = [[[h(ix + i, iy + j, iz + k) for k in (0, 1)] for j in (0, 1)] for i in (0, 1)]
    return lerp(
        lerp(lerp(c[0][0][0], c[0][0][1], fz), lerp(c[0][1][0], c[0][1][1], fz), fy),
        lerp(lerp(c[1][0][0], c[1][0][1], fz), lerp(c[1][1][0], c[1][1][1], fz), fy),
        fx)


# ------------------------------------------------------------------ holder

def build_holder():
    profile = [
        (0.0, 0.0), (0.030, 0.0), (0.046, 0.0006), (0.053, 0.0025),   # underside
        (0.0565, 0.0080), (0.0575, 0.0125),                            # outer wall
        (0.0568, 0.0138), (0.0550, 0.0134),                            # rolled rim
        (0.0525, 0.0075), (0.0470, 0.0040),                            # inner wall
        (0.0300, 0.0032), (0.0195, 0.0034),                            # dish floor
        (0.0172, 0.0052), (0.0158, 0.0120), (0.0152, 0.0270),          # socket, outside
        (0.0168, 0.0318), (0.0170, 0.0342),                            # socket lip
        (0.0150, 0.0352), (0.0125, 0.0330),                            # lip top
        (0.0123, 0.0130), (0.0060, 0.0122), (0.0, 0.0121),             # socket inside
    ]
    tarnish = angle_noise(11)

    def colour(a, r, z, _i):
        n = hash_noise(math.cos(a) * r, math.sin(a) * r, z, 260.0)
        base = (0.70, 0.50, 0.24)
        dark = 0.62 + 0.38 * n + 0.08 * tarnish(a)
        if r < 0.050 and z < 0.006:          # grime collects on the dish floor
            dark *= 0.72
        if 0.0128 < r < 0.0175 and z < 0.006:
            dark *= 0.6                      # dirty corner around the socket
        return (base[0] * dark, base[1] * dark, base[2] * dark, 1.0)

    obj = lathe("Holder", profile, segments=40, colour=colour)

    # finger ring on the side of the dish
    bm = bmesh.new()
    bmesh.ops.create_circle  # (keeps older Blender versions happy if create_torus is missing)
    major, minor = 0.0115, 0.0026
    ring_c = (0.0655, 0.0, 0.0085)
    seg_u, seg_v = 20, 8
    verts = []
    for i in range(seg_u):
        u = math.tau * i / seg_u
        row = []
        for j in range(seg_v):
            v = math.tau * j / seg_v
            rr = major + minor * math.cos(v)
            # the ring stands upright, in the X-Z plane
            x = ring_c[0] + rr * math.cos(u)
            z = ring_c[2] + rr * math.sin(u)
            y = ring_c[1] + minor * math.sin(v)
            row.append(bm.verts.new((x, y, z)))
        verts.append(row)
    for i in range(seg_u):
        for j in range(seg_v):
            a = verts[i][j]
            b = verts[(i + 1) % seg_u][j]
            c = verts[(i + 1) % seg_u][(j + 1) % seg_v]
            d = verts[i][(j + 1) % seg_v]
            bm.faces.new((a, b, c, d))
    # a thumb tab where the ring meets the rim
    tab = bmesh.ops.create_cube(bm, size=1.0)["verts"]
    bmesh.ops.scale(bm, verts=tab, vec=(0.014, 0.010, 0.0024))
    bmesh.ops.translate(bm, verts=tab, vec=(0.0585, 0.0, 0.0128))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ring_mesh = bpy.data.meshes.new("Ring")
    bm.to_mesh(ring_mesh)
    bm.free()
    ring = bpy.data.objects.new("Ring", ring_mesh)
    bpy.context.collection.objects.link(ring)

    def ring_colour(co):
        n = hash_noise(co.x, co.y, co.z, 300.0)
        d = 0.75 + 0.3 * n
        return (0.70 * d, 0.50 * d, 0.24 * d, 1.0)
    paint(ring, ring_colour)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    ring.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    smooth(obj, sharp_angle=math.radians(50))
    obj.data.materials.append(material("Brass"))
    return obj


# ------------------------------------------------------------------ spilled wax

def build_spill():
    bm = bmesh.new()
    blobs = [((0.030, 0.012), 0.010, 0.0065), ((0.024, -0.020), 0.0075, 0.0055), ((-0.016, 0.024), 0.0055, 0.004)]
    for (x, y), rx, ry in blobs:
        geo = bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=7, radius=1.0)
        vs = geo["verts"]
        ang = rng.uniform(0, math.tau)
        for v in vs:
            vx, vy, vz = v.co
            vz = max(vz, -0.2)   # flat bottom
            px = vx * rx
            py = vy * ry
            v.co = (x + px * math.cos(ang) - py * math.sin(ang),
                    y + px * math.sin(ang) + py * math.cos(ang),
                    0.0036 + (vz + 0.2) * 0.0011)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Spill")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Spill", mesh)
    bpy.context.collection.objects.link(obj)

    def col(co):
        n = hash_noise(co.x, co.y, co.z, 400.0)
        d = 0.86 + 0.14 * n
        return (0.86 * d, 0.79 * d, 0.64 * d, 0.0)
    paint(obj, col)
    smooth(obj)
    obj.data.materials.append(material("Wax"))
    return obj


# ------------------------------------------------------------------ wax body

def build_wax():
    # drips: (angle, length, width, amplitude)
    drips = []
    for k in range(6):
        drips.append((
            rng.uniform(0, math.tau),
            rng.uniform(0.018, 0.105),
            rng.uniform(0.11, 0.20),
            rng.uniform(0.0014, 0.0026),
        ))
    rows = int((WAX_TOP - WAX_BOTTOM) / 0.0015)
    profile = [(0.0, WAX_BOTTOM), (WAX_RADIUS * 0.9, WAX_BOTTOM)]
    for i in range(rows + 1):
        profile.append((WAX_RADIUS, WAX_BOTTOM + (WAX_TOP - WAX_BOTTOM) * i / rows))

    def drip_amount(a, z):
        total = 0.0
        for da, length, width, amp in drips:
            top = WAX_TOP - 0.001
            s = (top - z) / length          # 0 at the top of the drip, 1 at its end
            if s < -0.05 or s > 1.25:
                continue
            w = width * (1.0 - 0.45 * max(0.0, min(1.0, s)))
            d = (a - da + math.pi) % math.tau - math.pi
            across = math.exp(-(d / w) ** 2)
            along = (0.55 + 0.25 * s) * smoothstep(-0.05, 0.08, s) * (1.0 - smoothstep(0.92, 1.0, s))
            bulb = 1.1 * math.exp(-((s - 0.96) / 0.08) ** 2)      # the drop at the end
            total += amp * across * (along + bulb)
        return total

    def shape(a, r, z, i):
        if i < 2:
            return r, z
        # hand-dipped wax is never perfectly round
        lump = hash_noise(math.cos(a) * 0.012, math.sin(a) * 0.012, z * 0.4, 260.0) - 0.5
        return r + drip_amount(a, z) + 0.00022 * lump, z

    def colour(a, r, z, _i):
        n = hash_noise(math.cos(a) * 0.012, math.sin(a) * 0.012, z, 500.0)
        drip = min(1.0, drip_amount(a, z) / 0.0015)
        base = (0.93, 0.88, 0.76)
        dripc = (0.96, 0.91, 0.74)
        c = [base[k] * (1 - drip) + dripc[k] * drip for k in range(3)]
        d = 0.94 + 0.06 * n
        if z < WAX_BOTTOM + 0.025:          # shadowed inside the socket
            d *= 0.75 + 0.25 * smoothstep(WAX_BOTTOM + 0.012, WAX_BOTTOM + 0.025, z)
        return (c[0] * d, c[1] * d, c[2] * d, 0.0)

    obj = lathe("Wax", profile, segments=SEGMENTS, shape=shape, colour=colour)
    smooth(obj)
    obj.data.materials.append(material("Wax"))
    return obj


# ------------------------------------------------------------------ melted top

def build_cap():
    rim = angle_noise(41, 5)
    profile = [
        (WAX_RADIUS + 0.00025, -0.0060),
        (WAX_RADIUS + 0.00035, -0.0012),
        (WAX_RADIUS + 0.00010, 0.0000),
        (WAX_RADIUS - 0.0007, 0.0005),     # top of the soft rim
        (WAX_RADIUS - 0.0019, -0.0004),
        (0.0080, -0.0022),
        (0.0050, -0.0031),
        (0.0022, -0.0035),
        (0.0, -0.0036),
    ]

    def shape(a, r, z, i):
        if 1 <= i <= 4:
            z += 0.0011 * rim(a) - 0.0005
            # one low notch where the drips run over
            d = (a - 1.1 + math.pi) % math.tau - math.pi
            z -= 0.0018 * math.exp(-(d / 0.25) ** 2)
        return r, z

    def colour(a, r, z, _i):
        wet = 1.0 - smoothstep(0.0075, 0.0100, r)
        hard = (0.93, 0.88, 0.76)
        pool = (0.98, 0.86, 0.62)
        c = [hard[k] * (1 - wet) + pool[k] * wet for k in range(3)]
        return (c[0], c[1], c[2], wet)

    obj = lathe("Cap", profile, segments=SEGMENTS, shape=shape, colour=colour)
    smooth(obj)
    obj.data.materials.append(material("Wax"))
    obj.location.z = WAX_TOP
    return obj


# ------------------------------------------------------------------ wick

def build_wick():
    bm = bmesh.new()
    sides = 6
    rows = 14
    rings = []
    for i in range(rows + 1):
        t = i / rows
        z = -0.0030 + t * 0.0150
        bend = 0.0030 * t ** 2.2                      # a charred wick curls over
        x = bend
        z -= 0.0012 * t ** 3
        rad = 0.00075 * (1.0 - 0.35 * t ** 2)
        ring = []
        for s in range(sides):
            a = math.tau * s / sides
            ring.append(bm.verts.new((x + math.cos(a) * rad, math.sin(a) * rad, z)))
        rings.append(ring)
    for i in range(rows):
        for s in range(sides):
            t = (s + 1) % sides
            bm.faces.new((rings[i][s], rings[i][t], rings[i + 1][t], rings[i + 1][s]))
    tip = bm.verts.new((0.0030 + 0.00035, 0.0, -0.0030 + 0.0150 - 0.0012 + 0.0003))
    for s in range(sides):
        bm.faces.new((rings[-1][s], rings[-1][(s + 1) % sides], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Wick")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Wick", mesh)
    bpy.context.collection.objects.link(obj)

    def col(co):
        glow = smoothstep(0.0075, 0.0105, co.z)
        char = (0.035, 0.03, 0.028)
        ember = (1.0, 0.33, 0.06)
        # alpha = how much it glows (the shader uses it)
        return (char[0] + (ember[0] - char[0]) * glow,
                char[1] + (ember[1] - char[1]) * glow,
                char[2] + (ember[2] - char[2]) * glow, glow)
    paint(obj, col)
    smooth(obj)
    obj.data.materials.append(material("Wick"))
    obj.location.z = WAX_TOP
    return obj


# ------------------------------------------------------------------ main

def preview(path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 85
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.33, -0.33, 0.24)
    target = (0.0, 0.0, 0.07)
    d = [target[k] - cam.location[k] for k in range(3)]
    cam.rotation_euler = (math.atan2(math.hypot(d[0], d[1]), -d[2]), 0.0, math.atan2(d[1], d[0]) - math.pi / 2)
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_holder()
    build_spill()
    build_wax()
    build_cap()
    build_wick()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    kwargs = dict(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True,
                  use_selection=False, export_normals=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kwargs)
    print("make_candle: wrote", OUT)
    if PREVIEW:
        preview(PREVIEW)
        print("make_candle: preview", PREVIEW)


main()
