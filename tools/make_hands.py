# MAKE_HANDS - the player's hands (assets/models/hand_right.glb, hand_left.glb).
#
# Run from the project folder (Blender 4.2 or newer, tested on 5.2):
#   blender --background --factory-startup --python tools/make_hands.py [-- preview.png]
#
# Built like the dead exorcist (make_exorcist.py): a skeleton of points and
# radii grown into a smooth surface by the Skin modifier. Each hand is built
# in the space of what it holds, so the fingers sit exactly on it:
#   right: holds the chalk (hand_chalk.gd: the stick runs from 0 to -Z,
#          radius 7 mm) in a pinch - thumb under, index on top, middle at the
#          side, ring and little finger tucked in;
#   left:  holds the brass chamberstick (origin = bottom of the dish, axes as
#          the player's hands, the finger ring towards you): index finger
#          through the ring, thumb on the thumb rest, the other fingers
#          under the dish.
# Black cassock sleeves with a strip of white shirt cuff. Coordinates are
# written Godot-style (x right, y up, z towards you) and turned into
# Blender's Z-up. Shadows baked into vertex colours with Cycles.

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "models"))
PREVIEW = None
if "--" in sys.argv:
    extra = sys.argv[sys.argv.index("--") + 1:]
    if extra:
        PREVIEW = extra[0]

G2B = Matrix.Rotation(math.radians(90.0), 4, "X")      # Godot (x, y, z) -> Blender (x, -z, y)
SKIN = (0.7, 0.53, 0.44)
SLEEVE = (0.05, 0.047, 0.055)
CUFF = (0.78, 0.76, 0.7)

# --- right hand, in the chalk's space ---------------------------------------
RIGHT = {
    "points": {
        "elbow": ((0.075, -0.07, 0.34), 0.033),
        "forearm": ((0.052, -0.035, 0.2), 0.029),
        "cuff": ((0.036, -0.01, 0.098), 0.023),
        "wrist": ((0.03, -0.002, 0.07), 0.02),
        "palm": ((0.022, 0.008, 0.035), 0.024),
    },
    "chain": [("elbow", "forearm", "skin"), ("forearm", "wrist", "skin"), ("wrist", "palm", "skin")],
    "fingers": [
        ("palm", [(0.008, -0.012, 0.04), (0.0, -0.012, 0.02), (-0.006, -0.007, -0.004)], 0.0095),   # thumb, under
        ("palm", [(0.008, 0.022, 0.012), (0.0, 0.02, -0.008), (-0.002, 0.0095, -0.019)], 0.0085),    # index, on top
        ("palm", [(0.021, 0.018, 0.012), (0.019, 0.012, -0.01), (0.011, 0.0, -0.017)], 0.0088),      # middle, at the side
        ("palm", [(0.031, 0.012, 0.018), (0.034, 0.0, 0.004), (0.027, -0.009, 0.016)], 0.0082),     # ring, tucked
        ("palm", [(0.039, 0.005, 0.026), (0.041, -0.006, 0.016), (0.035, -0.012, 0.026)], 0.0072),  # little
    ],
}

# --- left hand, in the chamberstick's space -----------------------------------
LEFT = {
    "points": {
        "elbow": ((-0.18, -0.16, 0.39), 0.033),
        "forearm": ((-0.145, -0.1, 0.26), 0.029),
        "cuff": ((-0.112, -0.045, 0.142), 0.023),
        "wrist": ((-0.1, -0.03, 0.115), 0.02),
        "palm": ((-0.082, -0.016, 0.082), 0.025),
    },
    "chain": [("elbow", "forearm", "skin"), ("forearm", "wrist", "skin"), ("wrist", "palm", "skin")],
    "fingers": [
        ("palm", [(-0.072, 0.0, 0.058), (-0.05, 0.008, 0.045), (-0.032, 0.002, 0.056)], 0.0088),   # index, through the ring
        ("palm", [(-0.086, 0.004, 0.084), (-0.064, 0.018, 0.062), (-0.045, 0.022, 0.045)], 0.0098),  # thumb, on the rest
        ("palm", [(-0.075, -0.018, 0.064), (-0.045, -0.012, 0.045), (-0.022, -0.008, 0.028)], 0.0088),  # under the dish
        ("palm", [(-0.083, -0.021, 0.074), (-0.056, -0.014, 0.06), (-0.034, -0.009, 0.044)], 0.0084),
        ("palm", [(-0.092, -0.024, 0.084), (-0.07, -0.016, 0.075), (-0.052, -0.011, 0.064)], 0.0075),
    ],
}


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length, t


def build_hand(name, spec):
    names = list(spec["points"].keys())
    verts = [Vector(spec["points"][n][0]) for n in names]
    radii = [spec["points"][n][1] for n in names]
    edges = []
    labels = []
    for a, b, lab in spec["chain"]:
        edges.append((names.index(a), names.index(b)))
        labels.append((Vector(spec["points"][a][0]), Vector(spec["points"][b][0]), lab))
    for start, joints, r in spec["fingers"]:
        prev = names.index(start)
        prev_p = Vector(spec["points"][start][0])
        for j, jp in enumerate(joints):
            verts.append(Vector(jp))
            radii.append(r * (1.0 - 0.12 * j))
            edges.append((prev, len(verts) - 1))
            labels.append((prev_p, Vector(jp), "skin"))
            prev = len(verts) - 1
            prev_p = Vector(jp)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([G2B @ v for v in verts], edges, [])
    obj = link(bpy.data.objects.new(name, mesh))
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    sv = obj.data.skin_vertices[0].data
    for i, r in enumerate(radii):
        sv[i].radius = (r, r)
    sv[names.index("palm")].use_root = True
    sub = obj.modifiers.new("Sub", "SUBSURF")
    sub.levels = 2
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)

    cuff_p = Vector(spec["points"]["cuff"][0])
    wrist_p = Vector(spec["points"]["wrist"][0])
    palm_p = Vector(spec["points"]["palm"][0])
    # a hand is flatter than it is wide: squash the palm along its own up
    back = (palm_p - wrist_p).normalized()
    side = back.cross(Vector((0, 1, 0))).normalized()
    up = side.cross(back).normalized()
    for v in obj.data.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))
        d = g - palm_p
        w = math.exp(-(d.length / 0.03) ** 2)
        g -= up * d.dot(up) * 0.35 * w
        v.co = Vector((g.x, -g.z, g.y))
    obj.data.update()

    attr = obj.data.color_attributes.new("Base", "FLOAT_COLOR", "POINT")
    for v in obj.data.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))
        best = None
        for a, b, lab in labels:
            d, t = seg_dist(g, a, b)
            if best is None or d < best[0]:
                best = (d, t, lab)
        lab = best[2]
        c = SKIN
        c = tuple(c[k] * (0.92 + 0.12 * noise.noise(g * 120.0)) for k in range(3))
        attr.data[v.index].color = (c[0], c[1], c[2], 0.0)
    for p in obj.data.polygons:
        p.use_smooth = True
    # the cassock sleeve and the white shirt cuff: open tubes round the forearm
    elbow_p = Vector(spec["points"]["elbow"][0])
    axis = (cuff_p - elbow_p).normalized()
    sleeve = tube(name + "Sleeve", elbow_p - axis * 0.02, cuff_p, 0.042, 0.036, SLEEVE, wobble=0.003)
    shirt = tube(name + "Cuff", cuff_p - axis * 0.02, cuff_p + axis * 0.011, 0.027, 0.026, CUFF)
    bpy.ops.object.select_all(action="DESELECT")
    for o in (obj, sleeve, shirt):
        o.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    return obj


def tube(name, a, b, ra, rb, colour, segs=20, rings=10, wobble=0.0):
    """An open cloth tube from a to b (Godot space), 3 mm thick."""
    axis = (b - a).normalized()
    side = axis.cross(Vector((0, 1, 0)))
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(axis).normalized()
    verts = []
    faces = []
    for i in range(rings + 1):
        t = i / rings
        c = a.lerp(b, t)
        r = ra + (rb - ra) * t
        for j in range(segs):
            ang = math.tau * j / segs
            # cloth folds a little, more towards the elbow
            rr = r + wobble * (1.0 - t * 0.5) * math.sin(ang * 3.0 + t * 4.0)
            p = c + (side * math.cos(ang) + up * math.sin(ang)) * rr
            verts.append(G2B @ p)
    for i in range(rings):
        for j in range(segs):
            k0 = i * segs + j
            k1 = i * segs + (j + 1) % segs
            faces.append((k0, k1, k1 + segs, k0 + segs))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = link(bpy.data.objects.new(name, mesh))
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.003
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier="Solid")
    for p in obj.data.polygons:
        p.use_smooth = True
    attr = obj.data.color_attributes.new("Base", "FLOAT_COLOR", "POINT")
    for v in obj.data.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))
        k = 0.85 + 0.3 * max(0.0, noise.noise(g * 60.0))
        attr.data[v.index].color = (colour[0] * k, colour[1] * k, colour[2] * k, 0.0)
    return obj


def bake(obj):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.03
    mat = bpy.data.materials.new("Hand")
    mat.use_nodes = True
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
        k = 0.45 + 0.55 * ao.data[loop.index].color[0]
        col.data[loop.index].color = (b[0] * k, b[1] * k, b[2] * k, 0.0)
    mesh.color_attributes.remove(mesh.color_attributes["AO"])
    mesh.color_attributes.remove(mesh.color_attributes["Base"])
    # keep exactly one colour layer, so glTF has only COLOR_0
    for extra in [c.name for c in mesh.color_attributes if c.name != "Col"]:
        mesh.color_attributes.remove(mesh.color_attributes[extra])
    mesh.color_attributes.active_color = mesh.color_attributes["Col"]
    mesh.color_attributes.render_color_index = 0
    print("make_hands: colour layers", [c.name for c in mesh.color_attributes])


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    kwargs = dict(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                  use_selection=True, export_normals=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kwargs)
    print("make_hands: wrote", path, "triangles:", sum(len(p.vertices) - 2 for p in obj.data.polygons))


def preview(path, right, left):
    """Both hands with what they hold, for checking the grip."""
    scene = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, "candle.glb"))
    holder = [o for o in bpy.context.selected_objects]
    for o in holder:
        o.matrix_world = Matrix.Rotation(-2.36, 4, "Z") @ o.matrix_world     # as in player.gd
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.0068, depth=0.09, location=(0, 0, 0))
    chalk = bpy.context.active_object
    chalk.matrix_world = G2B @ Matrix.Translation((0, 0, -0.045))
    # put the right hand + chalk beside the candle, like on screen
    shift = Matrix.Translation(G2B @ Vector((0.28, 0.04, 0.0)))
    right.matrix_world = shift @ right.matrix_world
    chalk.matrix_world = shift @ chalk.matrix_world
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 700
    for i, (loc, tgt) in enumerate([((0.1, 0.45, 0.25), (0.12, 0.0, 0.03)), ((0.55, -0.35, 0.3), (0.12, 0.0, 0.03))]):
        cam = bpy.data.objects.new("C", bpy.data.cameras.new("C"))
        link(cam)
        cam.data.lens = 50
        cam.location = loc
        cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        scene.render.filepath = path.replace(".png", "_%d.png" % i)
        bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    right = build_hand("HandRight", RIGHT)
    left = build_hand("HandLeft", LEFT)
    for h in (right, left):
        bake(h)
    export(right, os.path.join(OUT, "hand_right.glb"))
    export(left, os.path.join(OUT, "hand_left.glb"))
    if PREVIEW:
        preview(PREVIEW, right, left)


main()
