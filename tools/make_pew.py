# MAKE_PEW - builds the church pew (assets/models/pew.glb).
#
# Run from the project folder (Blender 4.2 or newer, tested on 5.2):
#   blender --background --factory-startup --python tools/make_pew.py
#
# An oak pew of the kind found in old parish churches:
#   - two shaped pew ends: a sloping armrest that sweeps up into a rounded
#     top, with a raised pointed-arch panel on both faces;
#   - a seat with a rounded front edge and an apron under it;
#   - a backrest of three boards between rails, leaning back 8 degrees;
#   - a hymn-book shelf and a kneeler on the back, for the row behind;
#   - a stretcher and a centre support underneath.
#
# Sizes match the old box pews in level.gd: 2.4 m long, seat at 0.46 m,
# back at the +Z side (the row faces -Z, towards the altar).
# Coordinates below are written Godot-style (x right, y up, z back) and
# turned into Blender's Z-up at the end.
#
# Colours: no texture is stored here. UVs run along the wood grain and
# level.gd puts a code-made oak texture on them (textures.gd oak()).
# Vertex colour R = ambient occlusion baked with Cycles (dark in corners and
# near the floor), G = wear (seats and armrests polished by hands).

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "models", "pew.glb"))
PREVIEW = None
if "--" in sys.argv:
    extra = sys.argv[sys.argv.index("--") + 1:]
    if extra:
        PREVIEW = extra[0]

LENGTH = 2.4
END_T = 0.055                      # pew end thickness
END_X = LENGTH * 0.5 - END_T       # inner face of the ends
SEAT_Y = 0.46
BACK_TILT = math.radians(8.0)
BACK_PIVOT = Vector((0.0, SEAT_Y, 0.17))
STEP = 0.1                         # mesh density for the baked shadows

rng = random.Random(3)
parts = []


# ------------------------------------------------------------------ helpers

def lerp(a, b, t):
    return a + (b - a) * t


def add_box(bm, mn, mx, step=STEP):
    """A box made of a grid of quads (dense enough to carry baked shadows)."""
    n = [max(1, round((mx[k] - mn[k]) / step)) for k in range(3)]
    for a in range(3):
        b, c = [(1, 2), (2, 0), (0, 1)][a]
        for side in (0, 1):
            grid = []
            for i in range(n[b] + 1):
                row = []
                for j in range(n[c] + 1):
                    co = [0.0, 0.0, 0.0]
                    co[a] = mn[a] if side == 0 else mx[a]
                    co[b] = lerp(mn[b], mx[b], i / n[b])
                    co[c] = lerp(mn[c], mx[c], j / n[c])
                    row.append(bm.verts.new(co))
                grid.append(row)
            for i in range(n[b]):
                for j in range(n[c]):
                    q = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
                    if side == 0:
                        q.reverse()
                    bm.faces.new(q)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)


def bevel_hard_edges(bm, width, segments=2):
    edges = [e for e in bm.edges if len(e.link_faces) == 2
             and e.link_faces[0].normal.dot(e.link_faces[1].normal) < 0.5]
    if edges and width > 0:
        bmesh.ops.bevel(bm, geom=edges, offset=width, offset_type="OFFSET",
                        segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)


def grain_uvs(bm, grain_axis, scale=(1.0 / 1.2, 1.0 / 0.3)):
    """Project UVs so the texture's grain (along U) runs along grain_axis."""
    uv = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    off = (rng.random() * 7.0, rng.random() * 7.0)
    bm.normal_update()
    for f in bm.faces:
        nrm = f.normal
        a = max(range(3), key=lambda k: abs(nrm[k]))
        if a == grain_axis:
            # end grain: show the side of the texture across the cut
            u_axis, v_axis = [k for k in range(3) if k != a]
        else:
            u_axis = grain_axis
            v_axis = [k for k in range(3) if k != a and k != grain_axis][0]
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co[u_axis] * scale[0] + off[0], co[v_axis] * scale[1] + off[1])


def finish(name, bm, grain_axis, matrix=None):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    grain_uvs(bm, grain_axis)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    parts.append(obj)
    return obj


def box_part(name, mn, mx, grain_axis=0, bevel=0.004, matrix=None, step=STEP):
    bm = bmesh.new()
    add_box(bm, mn, mx, step)
    bevel_hard_edges(bm, bevel)
    return finish(name, bm, grain_axis, matrix)


def catmull(points, per_seg=4):
    """Smooth an open list of 2D points (keeps the first and last)."""
    out = []
    for i in range(len(points) - 1):
        p0 = points[max(i - 1, 0)]
        p1, p2 = points[i], points[i + 1]
        p3 = points[min(i + 2, len(points) - 1)]
        for s in range(per_seg):
            t = s / per_seg
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t
                                    + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                                    + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3) for k in range(2)))
    out.append(points[-1])
    return out


def resample(poly, spacing):
    """Add points along straight edges so the outline is evenly dense."""
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        d = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(d / spacing))
        for k in range(n):
            out.append((lerp(a[0], b[0], k / n), lerp(a[1], b[1], k / n)))
    return out


def slab(name, outline_zy, x0, thickness, grain_axis=1, bevel=0.004):
    """Extrude a (z, y) outline along +x, from x0 by thickness."""
    bm = bmesh.new()
    verts = [bm.verts.new((x0, y, z)) for z, y in outline_zy]
    face = bm.faces.new(verts)
    if face.normal.x > 0:
        face.normal_flip()
    res = bmesh.ops.extrude_face_region(bm, geom=[face])
    new_verts = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=new_verts, vec=(thickness, 0.0, 0.0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bevel_hard_edges(bm, bevel)
    caps = [f for f in bm.faces if len(f.verts) > 4]
    tri = bmesh.ops.triangulate(bm, faces=caps, quad_method="BEAUTY", ngon_method="BEAUTY")
    cap_edges = list({e for f in tri["faces"] for e in f.edges})
    bmesh.ops.subdivide_edges(bm, edges=cap_edges, cuts=1, use_grid_fill=True)
    return finish(name, bm, grain_axis)


# ------------------------------------------------------------------ parts

def pew_end_outline():
    front = [(-0.24, 0.0), (-0.24, 0.55)]
    curve = catmull([
        (-0.24, 0.55), (-0.232, 0.605), (-0.205, 0.635), (-0.16, 0.645),
        (-0.06, 0.64), (0.03, 0.648), (0.085, 0.685), (0.125, 0.76),
        (0.15, 0.85), (0.172, 0.93), (0.205, 0.982), (0.255, 1.0),
        (0.3, 0.99), (0.33, 0.955), (0.338, 0.9),
    ], per_seg=4)
    back = [(0.338, 0.0)]
    return resample(front[:1] + curve + back, 0.04)


def arch_outline(z0, z1, y0, y_spring, apex_y, segs=8):
    """A pointed (Gothic) arch panel outline in (z, y)."""
    w = z1 - z0
    r = w * 0.9                                 # arcs wider than half: pointed top
    cz = (z0 + z1) * 0.5
    pts = [(z0, y0), (z1, y0), (z1, y_spring)]
    # right arc: centred on the left side, from the right spring up to the apex
    c_right = (z1 - r, y_spring)
    a0 = 0.0
    a1 = math.acos(max(-1.0, min(1.0, (cz - c_right[0]) / r)))
    for k in range(1, segs + 1):
        a = lerp(a0, a1, k / segs)
        pts.append((c_right[0] + r * math.cos(a), c_right[1] + r * math.sin(a) * (apex_y - y_spring) / (r * math.sin(a1))))
    c_left = (z0 + r, y_spring)
    for k in range(segs - 1, -1, -1):
        a = lerp(a0, a1, k / segs)
        pts.append((c_left[0] - r * math.cos(a), c_left[1] + r * math.sin(a) * (apex_y - y_spring) / (r * math.sin(a1))))
    return pts


def build():
    outline = pew_end_outline()
    panel = arch_outline(-0.165, 0.245, 0.11, 0.42, 0.565)
    inner_panel = arch_outline(-0.14, 0.22, 0.135, 0.42, 0.53)
    for side in (-1.0, 1.0):
        x_in = side * END_X
        x0 = min(x_in, x_in + side * END_T)
        slab("End", outline, x0, END_T, bevel=0.006)
        # raised panel on both faces, and a sunken field inside it
        for face_x, out in ((x0, -1.0), (x0 + END_T, 1.0)):
            slab("Panel", panel, face_x if out > 0 else face_x - 0.007, 0.007, bevel=0.003)
            slab("Field", inner_panel, face_x + out * 0.007 if out > 0 else face_x - 0.007 - 0.004, 0.004, bevel=0.0015)

    # seat, apron, stretcher, centre support
    box_part("Seat", (-END_X, SEAT_Y - 0.042, -0.225), (END_X, SEAT_Y, 0.19), bevel=0.012)
    box_part("Apron", (-END_X, SEAT_Y - 0.13, -0.21), (END_X, SEAT_Y - 0.042, -0.185), bevel=0.004)
    box_part("Stretcher", (-END_X, 0.1, 0.03), (END_X, 0.16, 0.07), bevel=0.006)
    box_part("Support", (-0.022, 0.0, -0.17), (0.022, SEAT_Y - 0.042, 0.16), grain_axis=1, bevel=0.005)

    # backrest, built upright and then leaned back around the seat's back edge
    lean = (Matrix.Translation(BACK_PIVOT) @ Matrix.Rotation(BACK_TILT, 4, "X")
            @ Matrix.Translation(-BACK_PIVOT))
    z_back = 0.17
    box_part("BackRail", (-END_X, SEAT_Y, z_back), (END_X, SEAT_Y + 0.07, z_back + 0.032), bevel=0.005, matrix=lean)
    # three boards edge to edge: the bevels make the grooves between them.
    # (No gaps: the PSX vertex wobble would open them into holes.)
    y = SEAT_Y + 0.07
    board_h = (0.905 - y) / 3.0
    for k in range(3):
        box_part("Board", (-END_X, y, z_back + 0.002), (END_X, y + board_h, z_back + 0.026), bevel=0.005, matrix=lean)
        y += board_h
    box_part("TopRail", (-END_X - 0.004, 0.905, z_back - 0.008), (END_X + 0.004, 0.952, z_back + 0.04),
             bevel=0.014, matrix=lean)

    # hymn-book shelf on the back, with a lip and three brackets
    def back_z(yy):
        return z_back + 0.026 + (yy - SEAT_Y) * math.tan(BACK_TILT)
    sy = 0.745
    box_part("Shelf", (-END_X, sy, back_z(sy) - 0.008), (END_X, sy + 0.016, 0.332), bevel=0.003)
    box_part("ShelfLip", (-END_X, sy + 0.016, 0.316), (END_X, sy + 0.05, 0.332), bevel=0.004)
    for bx in (-0.8, 0.0, 0.8):
        box_part("Bracket", (bx - 0.012, sy - 0.07, back_z(sy - 0.07) - 0.004), (bx + 0.012, sy, back_z(sy) + 0.05),
                 grain_axis=1, bevel=0.003, step=0.05)

    # kneeler for the row behind, on two arms from the pew ends
    box_part("Kneeler", (-END_X + 0.03, 0.07, 0.40), (END_X - 0.03, 0.105, 0.56), bevel=0.008)
    for sx in (-1.0, 1.0):
        x = sx * (END_X - 0.03)
        box_part("KneelArm", (x - 0.02, 0.05, 0.30), (x + 0.02, 0.09, 0.47), bevel=0.004, step=0.05)


# ------------------------------------------------------------------ bake

def bake_shadows(obj):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 96
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.35

    mat = bpy.data.materials.new("Oak")
    mat.use_nodes = True
    obj.data.materials.append(mat)
    mesh = obj.data
    attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    mesh.color_attributes.active_color = attr
    mesh.color_attributes.render_color_index = 0

    # a floor to cast contact shadows
    bpy.ops.mesh.primitive_plane_add(size=12.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    scene.render.bake.target = "VERTEX_COLORS"
    bpy.ops.object.bake(type="AO")
    bpy.data.objects.remove(ground)

    # R = shadow (from the bake), G = wear from hands and sitting
    for loop in mesh.loops:
        co = mesh.vertices[loop.vertex_index].co          # Blender: Z up, -Y = Godot +z
        n = mesh.vertices[loop.vertex_index].normal
        ao = attr.data[loop.index].color[0]
        gy, gz = co.z, -co.y
        wear = 0.0
        if n.z > 0.6:
            if SEAT_Y - 0.01 < gy < SEAT_Y + 0.005 and gz < 0.15:
                wear = 1.0 - abs(co.x) / END_X * 0.5                 # polished where people sit
            elif 0.6 < gy < 0.66 and gz < 0.05:
                wear = 1.0                                           # armrests
            elif gy > 0.94:
                wear = 0.7                                           # top rail, under hands
        elif gz < -0.21 and SEAT_Y - 0.03 < gy < SEAT_Y + 0.005:
            wear = 0.8                                               # front edge of the seat
        attr.data[loop.index].color = (ao, wear, 0.0, 1.0)


# ------------------------------------------------------------------ main

def preview(path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 40
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (2.4, -2.0, 1.5)
    target = Vector((0.0, 0.0, 0.5))
    d = target - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    pew = bpy.context.active_object
    pew.name = "Pew"
    pew.data.name = "Pew"
    # Godot-style (y up, z back) -> Blender (z up, -y back)
    pew.data.transform(Matrix.Rotation(math.radians(90.0), 4, "X"))
    for p in pew.data.polygons:
        p.use_smooth = True
    if hasattr(pew.data, "set_sharp_from_angle"):
        pew.data.set_sharp_from_angle(angle=math.radians(40.0))
    bake_shadows(pew)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    pew.select_set(True)
    kwargs = dict(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True,
                  use_selection=True, export_normals=True, export_texcoords=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kwargs)
    print("make_pew: wrote", OUT, "triangles:", sum(len(p.vertices) - 2 for p in pew.data.polygons))
    if PREVIEW:
        preview(PREVIEW)
        print("make_pew: preview", PREVIEW)


main()
