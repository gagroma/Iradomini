import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_GUN = os.path.normpath(os.path.join(HERE, "..", "assets", "models", "sawn_off.glb"))
OUT_SHELL = os.path.normpath(os.path.join(HERE, "..", "assets", "models", "shell.glb"))

rng = random.Random(3)
G2B = Matrix.Rotation(math.radians(90.0), 4, "X")

STEEL = (0.045, 0.047, 0.055)
STEEL_WORN = (0.2, 0.2, 0.21)
WALNUT = (0.2, 0.085, 0.035)
WALNUT_DARK = (0.075, 0.03, 0.014)
BRASS = (0.62, 0.42, 0.14)
HULL = (0.42, 0.04, 0.03)

HINGE = Vector((0.0, -0.012, -0.035))
BARREL_LEN = 0.27
BORE = 0.0092
BARREL_R = 0.0118
GAP = 0.0118


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(lerp(c1[k], c2[k], t) for k in range(3))


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def to_b(g):
    return G2B @ g


def to_g(co):
    return Vector((co.x, co.z, -co.y))


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


def finish_mesh(name, bm, bevel=0.0, segments=2, smooth=True):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
        apply_all(obj)
    for p in obj.data.polygons:
        p.use_smooth = smooth
    return obj


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


def tube(name, a, b, r_out, r_in=0.0, segs=32):
    bm = bmesh.new()
    axis = (b - a)
    length = axis.length
    d = axis.normalized()
    ref = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))
    u = d.cross(ref).normalized()
    v = d.cross(u)
    rings = []
    radii = [r_out, r_out] if r_in <= 0.0 else [r_out, r_out, r_in, r_in]
    pos = [0.0, length] if r_in <= 0.0 else [0.0, length, length, 0.0]
    for r, t in zip(radii, pos):
        ring = []
        for k in range(segs):
            ang = math.tau * k / segs
            p = a + d * t + (u * math.cos(ang) + v * math.sin(ang)) * r
            ring.append(bm.verts.new(to_b(p)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k]))
    if r_in > 0.0:
        for k in range(segs):
            bm.faces.new((rings[3][k], rings[3][(k + 1) % segs], rings[0][(k + 1) % segs], rings[0][k]))
    else:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish_mesh(name, bm)


def box(name, centre, size, bevel=0.002, taper=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        p = Vector((v.co.x * size.x, v.co.y * size.y, v.co.z * size.z))
        if taper is not None:
            p = taper(p)
        v.co = to_b(centre + p)
    return finish_mesh(name, bm, bevel, 2)


def profile_solid(name, outline, half_w, bevel=0.003, z_curve=None):
    bm = bmesh.new()
    front = []
    back = []
    for y, z in outline:
        dx = half_w(y, z) if callable(half_w) else half_w
        front.append(bm.verts.new(to_b(Vector((dx, y, z)))))
        back.append(bm.verts.new(to_b(Vector((-dx, y, z)))))
    n = len(outline)
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], back[i], back[j], front[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish_mesh(name, bm, bevel, 3)


def steel_colour(g, n, worn_edges=1.0):
    m = noise.noise(g * 120.0) * 0.5 + 0.5
    col = mix(STEEL, (0.07, 0.07, 0.085), m * 0.6)
    edge = max(0.0, n.y) * 0.3 + smoothstep(0.6, 0.95, noise.noise(g * 40.0 + Vector((2, 7, 1))) * 0.5 + 0.5) * 0.4
    col = mix(col, STEEL_WORN, edge * worn_edges)
    pit = smoothstep(0.7, 0.9, noise.noise(g * 300.0) * 0.5 + 0.5)
    col = mix(col, (0.12, 0.06, 0.03), pit * 0.35)
    return (*col, 0.7)


def case_colour(g, n):
    a = noise.noise(g * 55.0)
    b = noise.noise(g * 23.0 + Vector((5, 1, 3)))
    col = mix((0.22, 0.2, 0.2), (0.08, 0.12, 0.2), smoothstep(-0.3, 0.4, a))
    col = mix(col, (0.3, 0.17, 0.08), smoothstep(0.1, 0.6, b) * 0.6)
    col = mix(col, (0.05, 0.05, 0.06), 0.35)
    return (*col, 0.75)


def wood_colour(g, n):
    grain = math.sin(g.z * 260.0 + noise.noise(g * 18.0) * 9.0 + g.y * 40.0) * 0.5 + 0.5
    fig = noise.noise(g * 9.0) * 0.5 + 0.5
    col = mix(WALNUT_DARK, WALNUT, grain * 0.55 + fig * 0.45)
    worn = max(0.0, n.y) * 0.25
    col = mix(col, (0.34, 0.17, 0.08), worn)
    return (*col, 0.45)


def build_barrels():
    parts = []
    for sx in (-1.0, 1.0):
        a = Vector((sx * GAP, 0.0, 0.0))
        b = Vector((sx * GAP, 0.006, -BARREL_LEN))
        t = tube("barrel", a, b, BARREL_R, BORE)
        paint(t, steel_colour)
        parts.append(t)
        breech = tube("breech", Vector((sx * GAP, 0.0, 0.002)), Vector((sx * GAP, 0.001, -0.06)), BARREL_R + 0.0016, BORE)
        paint(breech, steel_colour)
        parts.append(breech)
        muzzle = tube("muzzle", Vector((sx * GAP, 0.0058, -BARREL_LEN + 0.004)), Vector((sx * GAP, 0.006, -BARREL_LEN - 0.0005)), BARREL_R + 0.0008, BORE)
        paint(muzzle, lambda g, n: steel_colour(g, n, 1.6))
        parts.append(muzzle)
    rib = box("rib", Vector((0.0, BARREL_R * 0.95 + 0.003, -BARREL_LEN * 0.5)), Vector((0.008, 0.004, BARREL_LEN - 0.01)), 0.0012,
              taper=lambda p: Vector((p.x, p.y + 0.0025 * (p.z / BARREL_LEN), p.z)))
    paint(rib, steel_colour)
    parts.append(rib)
    under = box("underrib", Vector((0.0, -BARREL_R * 0.75, -BARREL_LEN * 0.5)), Vector((0.006, 0.005, BARREL_LEN - 0.02)), 0.001)
    paint(under, steel_colour)
    parts.append(under)
    bead = tube("bead", Vector((0, BARREL_R + 0.0062, -BARREL_LEN + 0.012)), Vector((0, BARREL_R + 0.0095, -BARREL_LEN + 0.012)), 0.0018, 0.0, 12)
    paint(bead, lambda g, n: (*BRASS, 0.9))
    parts.append(bead)
    lug = box("lug", Vector((0.0, -BARREL_R - 0.006, -0.02)), Vector((0.012, 0.014, 0.05)), 0.0015)
    paint(lug, steel_colour)
    parts.append(lug)
    fore_outline = [(-0.007, -0.03), (-0.024, -0.035), (-0.03, -0.06), (-0.028, -0.14), (-0.02, -0.155), (-0.008, -0.15)]
    fore = profile_solid("forend", fore_outline, lambda y, z: 0.022 + 0.004 * smoothstep(-0.03, -0.007, y), 0.004)
    paint(fore, wood_colour)
    parts.append(fore)
    for sx in (-1.0, 1.0):
        ext = tube("ejector", Vector((sx * GAP, 0.0, 0.0025)), Vector((sx * GAP, 0.0, 0.0008)), BARREL_R * 0.98, BORE * 1.02, 32)
        paint(ext, lambda g, n: steel_colour(g, n, 2.0))
        parts.append(ext)
    return join(parts, "barrels")


def build_frame():
    parts = []
    recv = box("receiver", Vector((0.0, -0.004, 0.035)), Vector((0.047, 0.04, 0.07)), 0.004,
               taper=lambda p: Vector((p.x * (1.0 - 0.12 * max(0.0, -p.y / 0.02)), p.y, p.z)))
    paint(recv, case_colour)
    parts.append(recv)
    bar = box("bar", Vector((0.0, -0.019, -0.022)), Vector((0.04, 0.011, 0.046)), 0.002)
    paint(bar, case_colour)
    parts.append(bar)
    face = box("standing_breech", Vector((0.0, 0.004, 0.0015)), Vector((0.047, 0.03, 0.003)), 0.001)
    paint(face, case_colour)
    parts.append(face)
    tang = box("tang", Vector((0.0, 0.016, 0.085)), Vector((0.016, 0.004, 0.04)), 0.0015)
    paint(tang, steel_colour)
    parts.append(tang)
    lever = box("lever", Vector((0.0, 0.021, 0.075)), Vector((0.01, 0.005, 0.03)), 0.0018,
                taper=lambda p: Vector((p.x + p.z * 0.25, p.y, p.z)))
    paint(lever, lambda g, n: steel_colour(g, n, 1.4))
    parts.append(lever)
    for sx in (-1.0, 1.0):
        hammer_outline = [(0.0, 0.0), (0.012, 0.004), (0.03, 0.008), (0.036, 0.018), (0.033, 0.024), (0.024, 0.016), (0.012, 0.014), (0.002, 0.016)]
        pts = [(0.01 + y, 0.062 - z) for y, z in hammer_outline]
        hammer = profile_solid("hammer", pts, 0.0035, 0.0012)
        hammer.location = to_b(Vector((sx * 0.016, 0.0, 0.0)))
        apply_loc(hammer)
        paint(hammer, lambda g, n: steel_colour(g, n, 1.5))
        parts.append(hammer)
        trig = profile_solid("trigger", [(-0.028, 0.05 + sx * 0.006), (-0.05, 0.047 + sx * 0.006), (-0.054, 0.052 + sx * 0.006), (-0.032, 0.058 + sx * 0.006)], 0.0022, 0.0008)
        trig.location = to_b(Vector((sx * 0.004, 0.0, 0.0)))
        apply_loc(trig)
        paint(trig, lambda g, n: (*mix(STEEL_WORN, (0.4, 0.38, 0.35), 0.4), 0.85))
        parts.append(trig)
    guard_pts = []
    for k in range(25):
        a = math.pi * k / 24.0
        guard_pts.append(Vector((0.0, -0.024 - math.sin(a) * 0.03, 0.03 + math.cos(a) * -0.032 + 0.032)))
    guard = sweep("guard", guard_pts, 0.0026)
    paint(guard, steel_colour)
    parts.append(guard)
    grip_outline = [(-0.02, 0.07), (0.012, 0.07), (0.015, 0.095), (0.004, 0.13), (-0.022, 0.18), (-0.05, 0.2), (-0.088, 0.206),
                    (-0.1, 0.194), (-0.094, 0.172), (-0.068, 0.15), (-0.052, 0.118), (-0.043, 0.094), (-0.035, 0.075)]
    grip = profile_solid("grip", grip_outline, lambda y, z: 0.019 - 0.004 * smoothstep(0.1, 0.17, z) + 0.002 * smoothstep(0.17, 0.24, z), 0.006)
    for v in grip.data.vertices:
        g = to_g(v.co)
        bulge = math.exp(-((g.z - 0.15) ** 2) / 0.003) * 0.003
        g.x *= 1.0 + bulge * 30.0
        v.co = to_b(g)
    paint(grip, lambda g, n: wood_colour(g, n) if not (g.z > 0.205 and g.y < -0.09) else (*mix(WALNUT_DARK, (0.3, 0.2, 0.12), 0.4), 0.2))
    parts.append(grip)
    pin = tube("hinge_pin", HINGE + Vector((-0.024, 0, 0)), HINGE + Vector((0.024, 0, 0)), 0.0042, 0.0, 16)
    paint(pin, lambda g, n: steel_colour(g, n, 1.8))
    parts.append(pin)
    for sx in (-1.0, 1.0):
        screw = tube("screw", Vector((sx * 0.0236, -0.006, 0.05)), Vector((sx * 0.0246, -0.006, 0.05)), 0.0028, 0.0, 14)
        paint(screw, lambda g, n: (*STEEL_WORN, 0.85))
        parts.append(screw)
    return join(parts, "frame")


def sweep(name, pts, r, segs=12):
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        ref = Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0))
        u = d.cross(ref).normalized()
        v = d.cross(u)
        ring = []
        for k in range(segs):
            ang = math.tau * k / segs
            ring.append(bm.verts.new(to_b(p + (u * math.cos(ang) + v * math.sin(ang)) * r)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish_mesh(name, bm)


def apply_loc(obj):
    select_only(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def build_shell(name):
    parts = []
    hull = tube("hull", Vector((0, 0, 0.0)), Vector((0, 0, -0.058)), 0.0098, 0.0, 28)
    for v in hull.data.vertices:
        g = to_g(v.co)
        if g.z < -0.055:
            g.x *= 0.92
            g.y *= 0.92
        v.co = to_b(g)

    def hull_colour(g, n):
        ribs = math.sin(math.atan2(g.y, g.x) * 18.0) * 0.5 + 0.5
        col = mix(HULL, (0.55, 0.08, 0.05), ribs * 0.25)
        if g.z < -0.056:
            col = mix(col, (0.2, 0.02, 0.02), 0.6)
        return (*col, 0.5)
    paint(hull, hull_colour)
    parts.append(hull)
    head = tube("head", Vector((0, 0, 0.0015)), Vector((0, 0, -0.016)), 0.0102, 0.0, 28)
    paint(head, lambda g, n: (*mix(BRASS, (0.85, 0.66, 0.3), max(0.0, n.z) * 0.6 + (noise.noise(g * 200.0) * 0.5 + 0.5) * 0.2), 0.9))
    parts.append(head)
    rim = tube("rim", Vector((0, 0, 0.0028)), Vector((0, 0, 0.0005)), 0.0112, 0.0, 28)
    paint(rim, lambda g, n: (*BRASS, 0.9))
    parts.append(rim)
    primer = tube("primer", Vector((0, 0, 0.0031)), Vector((0, 0, 0.002)), 0.0028, 0.0, 16)
    paint(primer, lambda g, n: (0.55, 0.5, 0.45, 0.95))
    parts.append(primer)
    return join(parts, name)


def bake(objs):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.04
    for obj in objs:
        mat = bpy.data.materials.new(obj.name)
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
            k = 0.35 + 0.65 * a
            col.data[loop.index].color = (b[0] * k, b[1] * k, b[2] * k, b[3])
        mesh.color_attributes.remove(mesh.color_attributes["AO"])
        mesh.color_attributes.remove(mesh.color_attributes["Base"])
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
        mesh.color_attributes.render_color_index = 0


def set_origin(obj, pivot_g):
    pivot = to_b(pivot_g)
    obj.data.transform(Matrix.Translation(-pivot))
    obj.location = pivot


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kwargs = dict(filepath=path, export_format="GLB", export_yup=True, export_apply=True, use_selection=True, export_normals=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kwargs)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    print("make_sawnoff: wrote", path, "triangles:", tris)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    barrels = build_barrels()
    frame = build_frame()
    bake([barrels, frame])
    set_origin(barrels, HINGE)
    export([barrels, frame], OUT_GUN)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    shell = build_shell("shell")
    bake([shell])
    export([shell], OUT_SHELL)


main()
