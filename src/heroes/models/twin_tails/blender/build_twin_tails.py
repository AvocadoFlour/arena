"""Twin Tails - procedural Blender build (Blender 4.2, run headless):
    blender -b --python src/heroes/models/twin_tails/blender/build_twin_tails.py -- [--out DIR] [--shots DIR]
Builds mesh + armature + actions from code (reproducible), exports twin_tails.glb next to this folder's parent,
optionally renders front/side/3-4 turnaround PNGs. Character faces Blender -Y; units metres; height 1.75 m.
Style: flat colours (white / black / pale ice-blue / silver), outlines done in-engine (inverted hull)."""
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix, Euler, Quaternion

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(name, default=None):
    return ARGS[ARGS.index(name) + 1] if name in ARGS else default
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = arg("--out", os.path.dirname(HERE))
SHOTS = arg("--shots")

# ---------------------------------------------------------------- scene reset
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---------------------------------------------------------------- palette
PAL = {
    "skin":   (0.99, 0.95, 0.92),
    "white":  (0.97, 0.98, 1.00),
    "black":  (0.06, 0.06, 0.08),
    "ice":    (0.62, 0.81, 0.96),   # pale ice-blue (hair, trims) - cooler/paler than teal, no teal
    "ice_dk": (0.42, 0.66, 0.90),   # trims / stripes
    "silver": (0.78, 0.81, 0.86),
    "eye":    (0.10, 0.12, 0.18),
    "iris":   (0.40, 0.62, 0.86),
    "lip":    (0.86, 0.60, 0.62),
    "sole":   (0.10, 0.10, 0.12),
}
MATS = {}
def srgb_to_lin(x):
    return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
def mat(name):
    if name not in MATS:
        m = bpy.data.materials.new("tt_" + name)
        c = tuple(srgb_to_lin(x) for x in PAL[name])   # palette is sRGB; Blender colours are linear
        m.diffuse_color = (*c, 1.0)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*c, 1.0)
        bsdf.inputs["Roughness"].default_value = 1.0
        MATS[name] = m
    return MATS[name]

# ---------------------------------------------------------------- mesh helpers
PARTS = []   # (object, bone candidates)

def new_obj(name, bm, material, bones):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    ob.data.materials.append(mat(material))
    for p in ob.data.polygons:
        p.use_smooth = True
    PARTS.append((ob, bones))
    return ob

def _frame(t):
    t = t.normalized()
    ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((0, -1, 0))
    x = ref.cross(t).normalized() if abs(t.z) < 0.9 else Vector((1, 0, 0))
    if abs(t.z) >= 0.9:
        x = Vector((1, 0, 0))
        y = t.cross(x).normalized()
        x = y.cross(t).normalized()
    else:
        y = t.cross(x).normalized()
    return x, y

def loft(name, rings, material, bones, n=14, cap0=True, cap1=True, arc=None):
    """rings: list of (center Vector, rx, ry[, twist]) - ellipse cross sections. rx along the ring's
    'side' axis (world X for vertical tubes), ry along front/back. arc=(a0,a1) degrees -> open shell."""
    bm = bmesh.new()
    loops = []
    for i, r in enumerate(rings):
        c, rx, ry = Vector(r[0]), r[1], r[2]
        a = Vector(rings[min(i + 1, len(rings) - 1)][0]) - Vector(rings[max(i - 1, 0)][0])
        if a.length < 1e-6:
            a = Vector((0, 0, -1))
        x, y = _frame(a)
        vs = []
        cnt = n if arc is None else n + 1
        for k in range(cnt):
            if arc is None:
                th = 2 * math.pi * k / n
            else:
                th = math.radians(arc[0] + (arc[1] - arc[0]) * k / n)
            vs.append(bm.verts.new(c + x * (math.cos(th) * rx) + y * (math.sin(th) * ry)))
        loops.append(vs)
    for i in range(len(loops) - 1):
        a, b = loops[i], loops[i + 1]
        m = len(a)
        for k in range(m if arc is None else m - 1):
            k2 = (k + 1) % m
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    if arc is None:
        if cap0:
            bm.faces.new(list(reversed(loops[0])))
        if cap1:
            bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_obj(name, bm, material, bones)

def ellipsoid(name, c, r, material, bones, seg=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * r[0], v.co.y * r[1], v.co.z * r[2])) + Vector(c)
    return new_obj(name, bm, material, bones)

def boxm(name, c, size, material, bones, bevel=0.0, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect='EDGES')
    R = Euler([math.radians(a) for a in rot]).to_matrix()
    for v in bm.verts:
        v.co = R @ v.co + Vector(c)
    return new_obj(name, bm, material, bones)

def star_prism(name, c, r_out, r_in, depth, material, bones, normal_axis="Y", rot_z=0.0):
    bm = bmesh.new()
    pts = []
    for k in range(10):
        r = r_out if k % 2 == 0 else r_in
        th = math.pi / 2 + k * math.pi / 5
        pts.append((math.cos(th) * r, math.sin(th) * r))
    def put(px, py, d):
        if normal_axis == "Y":
            return Vector((px, d, py))
        return Vector((d, px, py))
    front = [bm.verts.new(put(px, py, -depth / 2)) for px, py in pts]
    back = [bm.verts.new(put(px, py, depth / 2)) for px, py in pts]
    cf = bm.verts.new(put(0, 0, -depth / 2))
    cb = bm.verts.new(put(0, 0, depth / 2))
    for k in range(10):
        k2 = (k + 1) % 10
        bm.faces.new((cf, front[k2], front[k]))
        bm.faces.new((cb, back[k], back[k2]))
        bm.faces.new((front[k], front[k2], back[k2], back[k]))
    R = Matrix.Rotation(rot_z, 3, 'Z')
    for v in bm.verts:
        v.co = R @ v.co + Vector(c)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_obj(name, bm, material, bones)

def flat_decal(name, pts2d, c, material, bones, depth=0.002, yaw=0.0):
    """Flat polygon in the XZ plane facing -Y (the face), placed at c."""
    bm = bmesh.new()
    vs = [bm.verts.new((p[0], 0.0, p[1])) for p in pts2d]
    bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    R = Matrix.Rotation(yaw, 3, 'Z')
    for v in bm.verts:
        v.co = R @ v.co + Vector(c)
    ob = new_obj(name, bm, material, bones)
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob

def ellipse_pts(w, h, n=10, squash_top=1.0):
    out = []
    for k in range(n):
        th = 2 * math.pi * k / n
        z = math.sin(th) * h * (squash_top if math.sin(th) > 0 else 1.0)
        out.append((math.cos(th) * w, z))
    return out

# ---------------------------------------------------------------- proportions (Z up, faces -Y)
H = 1.75
HEAD_C = Vector((0, 0.0, 1.635)); HEAD_R = (0.078, 0.088, 0.105)
NECK0, NECK1 = 1.47, 1.56
SH_Z = 1.425; SH_X = 0.165
ELB = 1.17; WRIST = 0.93
HIP_X = 0.085; HIP_Z = 0.90; KNEE_Z = 0.49; ANK_Z = 0.10
ARM_OUT = 0.07   # A-pose: wrist this much further out than shoulder

def arm_pt(side, z):
    t = (SH_Z - z) / (SH_Z - WRIST)
    return Vector((side * (SH_X + 0.02 + ARM_OUT * t), 0.0, z))

def leg_pt(side, z):
    t = (HIP_Z - z) / (HIP_Z - ANK_Z)
    return Vector((side * (HIP_X + 0.012 * t), -0.004 * t, z))

# ---------------------------------------------------------------- body
# torso (skin) - neck to hips; black top / shorts / jacket are shells over it
torso = [((0, 0.005, 1.475), 0.05, 0.04), ((0, 0.0, 1.43), 0.14, 0.075), ((0, -0.005, 1.36), 0.135, 0.085),
         ((0, -0.005, 1.29), 0.118, 0.08), ((0, 0.0, 1.20), 0.098, 0.068), ((0, 0.0, 1.11), 0.105, 0.07),
         ((0, 0.0, 1.03), 0.135, 0.085), ((0, 0.0, 0.95), 0.15, 0.09), ((0, 0.0, 0.88), 0.135, 0.085)]
loft("torso", torso, "skin", ["hips", "spine", "chest", "neck"], n=18)
loft("neck", [((0, 0.008, NECK0), 0.034, 0.032), ((0, 0.008, NECK1), 0.031, 0.03)], "skin", ["neck", "head"], n=12)
# bandeau top (black) and the shorts (black) - slightly larger shells
loft("top", [((0, -0.004, 1.385), 0.141, 0.091), ((0, -0.006, 1.33), 0.133, 0.091), ((0, -0.006, 1.27), 0.121, 0.086)],
     "black", ["chest", "spine"], n=18)
loft("shorts_waist", [((0, 0.0, 1.075), 0.114, 0.077), ((0, 0.0, 1.03), 0.141, 0.09), ((0, 0.0, 0.95), 0.156, 0.095),
                      ((0, 0.0, 0.89), 0.15, 0.09), ((0, 0.0, 0.86), 0.09, 0.07)], "black", ["hips"], n=18)
loft("belt", [((0, 0.0, 1.085), 0.12, 0.081), ((0, 0.0, 1.06), 0.125, 0.084)], "black", ["hips"], n=18)
for s, nm in ((1, "L"), (-1, "R")):
    # legs (skin), thigh -> ankle
    zs = [HIP_Z + 0.02, 0.82, 0.72, 0.60, KNEE_Z + 0.02, KNEE_Z - 0.04, 0.38, 0.27, 0.17, ANK_Z]
    rr = [0.075, 0.072, 0.064, 0.055, 0.047, 0.046, 0.053, 0.046, 0.037, 0.033]
    loft("leg_" + nm, [(leg_pt(s, z), r, r * 1.05) for z, r in zip(zs, rr)], "skin", ["thigh." + nm, "shin." + nm], n=14)
    # shorts legs
    loft("shorts_" + nm, [(leg_pt(s, 0.93), 0.074, 0.088), (leg_pt(s, 0.87), 0.08, 0.086), (leg_pt(s, 0.80), 0.079, 0.083)],
         "black", ["thigh." + nm, "hips"], n=14)
    # socks: knee-high white with two ice-blue stripes
    sz = [0.44, 0.38, 0.27, 0.17, ANK_Z - 0.01]
    sr = [0.052, 0.058, 0.050, 0.041, 0.037]
    loft("sock_" + nm, [(leg_pt(s, z), r, r * 1.05) for z, r in zip(sz, sr)], "white", ["shin." + nm], n=14)
    for zz in (0.425, 0.405):
        rz = 0.055
        loft("stripe_%s_%d" % (nm, int(zz * 1000)), [(leg_pt(s, zz + 0.006), rz, rz * 1.05), (leg_pt(s, zz - 0.006), rz, rz * 1.05)],
             "ice_dk", ["shin." + nm], n=14)
    # chunky sneakers: white upper, black platform sole, silver laces
    fx = s * (HIP_X + 0.014)
    boxm("shoe_up_" + nm, (fx, -0.03, 0.105), (0.112, 0.24, 0.1), "white", ["foot." + nm], bevel=0.04)
    ellipsoid("shoe_toe_" + nm, (fx, -0.12, 0.085), (0.058, 0.075, 0.045), "white", ["foot." + nm], seg=12, rings=8)
    boxm("sole_" + nm, (fx, -0.04, 0.03), (0.125, 0.3, 0.06), "sole", ["foot." + nm], bevel=0.018)
    boxm("sole_line_" + nm, (fx, -0.04, 0.062), (0.128, 0.302, 0.01), "white", ["foot." + nm], bevel=0.004)
    for k in range(3):
        boxm("lace_%s_%d" % (nm, k), (fx, -0.08 + k * 0.03, 0.125 + k * 0.006), (0.06, 0.008, 0.008), "silver", ["foot." + nm], rot=(25, 0, 0))
    boxm("collar_" + nm, (fx, 0.04, 0.155), (0.1, 0.06, 0.03), "ice", ["foot." + nm], bevel=0.01)

    # arms (skin) shoulder -> wrist, hands
    az = [SH_Z + 0.005, 1.33, 1.25, ELB, 1.08, 1.0, WRIST]
    ar = [0.045, 0.042, 0.037, 0.032, 0.033, 0.029, 0.025]
    loft("arm_" + nm, [(arm_pt(s, z), r, r) for z, r in zip(az, ar)], "skin", ["upper_arm." + nm, "forearm." + nm], n=12)
    hp = arm_pt(s, WRIST - 0.055)
    ellipsoid("hand_" + nm, hp, (0.02, 0.028, 0.048), "skin", ["hand." + nm], seg=10, rings=6)
    # jacket sleeves (white) + ice cuffs
    jz = [SH_Z + 0.02, 1.33, 1.25, ELB, 1.06, 0.975]
    jr = [0.056, 0.052, 0.048, 0.045, 0.047, 0.048]
    loft("sleeve_" + nm, [(arm_pt(s, z), r, r) for z, r in zip(jz, jr)], "white", ["upper_arm." + nm, "forearm." + nm], n=12, cap0=False)
    loft("cuff_" + nm, [(arm_pt(s, 0.995), 0.054, 0.054), (arm_pt(s, 0.965), 0.054, 0.054)], "ice_dk", ["forearm." + nm], n=12)
    loft("cuffw_" + nm, [(arm_pt(s, 0.965), 0.052, 0.052), (arm_pt(s, 0.955), 0.052, 0.052)], "white", ["forearm." + nm], n=12)
    # shoulder caps
    ellipsoid("shoulder_" + nm, arm_pt(s, SH_Z - 0.01), (0.056, 0.058, 0.05), "white", ["upper_arm." + nm, "chest"], seg=12, rings=8)

# cropped jacket body: open front shell (arc excludes the front) + ice trim along the opening and hem
jac = [((0, 0.0, 1.455), 0.155, 0.09), ((0, -0.002, 1.40), 0.158, 0.1), ((0, -0.002, 1.33), 0.15, 0.1),
       ((0, 0.0, 1.27), 0.137, 0.094), ((0, 0.0, 1.235), 0.132, 0.09)]
# ring angle 0 = +side axis; front is -Y. With the vertical frame, sin(th)*y where y = t x x; build arc from 300->600 (skips front)
loft("jacket", jac, "white", ["chest", "spine"], n=20, arc=(122, 418))
loft("jacket_hem", [((0, 0.0, 1.245), 0.135, 0.093), ((0, 0.0, 1.225), 0.135, 0.093)], "ice_dk", ["spine"], n=20, arc=(122, 418))
for s in (1, -1):
    # lapels: angled flat strips from shoulder to hem along the opening
    loft("lapel_%d" % s, [(Vector((s * 0.06, -0.088, 1.455)), 0.022, 0.006), (Vector((s * 0.085, -0.1, 1.39)), 0.026, 0.006),
                          (Vector((s * 0.09, -0.099, 1.30)), 0.016, 0.006), (Vector((s * 0.09, -0.094, 1.235)), 0.014, 0.006)],
         "ice_dk", ["chest", "spine"], n=8)
    loft("collar_up_%d" % s, [(Vector((s * 0.05, -0.05, 1.47)), 0.012, 0.05), (Vector((s * 0.06, -0.03, 1.515)), 0.01, 0.04)],
         "white", ["chest", "neck"], n=8)

# ---------------------------------------------------------------- head, face, hair, headset
ellipsoid("head", HEAD_C, HEAD_R, "skin", ["head"], seg=20, rings=14)
ellipsoid("jaw", HEAD_C + Vector((0, -0.012, -0.055)), (0.058, 0.07, 0.06), "skin", ["head"], seg=16, rings=10)
FACE_Y = HEAD_C.y - HEAD_R[1] + 0.006
for s in (1, -1):
    ex = s * 0.032
    ez = HEAD_C.z - 0.006
    yaw = -s * 0.32
    fy = FACE_Y + 0.012
    flat_decal("eye_%d" % s, ellipse_pts(0.02, 0.011, 12, 1.25), (ex, fy - 0.001, ez), "eye", ["head"], yaw=yaw)
    flat_decal("iris_%d" % s, ellipse_pts(0.009, 0.0095, 10), (ex + s * 0.001, fy - 0.003, ez - 0.001), "iris", ["head"], yaw=yaw)
    flat_decal("lash_%d" % s, [(-0.02, 0.009), (0.02, 0.012), (0.022, 0.016), (-0.018, 0.013)], (ex, fy - 0.004, ez + 0.002), "eye", ["head"], yaw=yaw)
    flat_decal("brow_%d" % s, [(-0.018, 0.0), (0.018, 0.004), (0.018, 0.0065), (-0.018, 0.0035)], (ex, fy - 0.001, ez + 0.026), "eye", ["head"], yaw=yaw)
flat_decal("mouth", ellipse_pts(0.011, 0.0028, 10), (0, FACE_Y + 0.02, HEAD_C.z - 0.07), "lip", ["head"])
flat_decal("nose", [(-0.003, 0.0), (0.003, 0.0), (0.0, 0.006)], (0.003, FACE_Y + 0.005, HEAD_C.z - 0.038), "lip", ["head"])

# hair: skull cap (covers back/top), fringe, side locks
ellipsoid("hair_cap", HEAD_C + Vector((0, 0.014, 0.022)), (0.088, 0.096, 0.108), "ice", ["head"], seg=20, rings=14)
for k, x in enumerate((-0.055, -0.02, 0.018, 0.05)):
    loft("fringe_%d" % k, [((x, -0.072, 1.745), 0.02, 0.012), ((x * 1.15, -0.088, 1.70), 0.017, 0.01), ((x * 1.25, -0.093, 1.665), 0.006, 0.004)],
         "ice", ["head"], n=8)
for s in (1, -1):
    loft("sidelock_%d" % s, [((s * 0.07, -0.05, 1.72), 0.016, 0.022), ((s * 0.083, -0.055, 1.62), 0.014, 0.02), ((s * 0.08, -0.05, 1.52), 0.01, 0.014),
                             ((s * 0.075, -0.045, 1.45), 0.003, 0.004)], "ice", ["head"], n=8)

# twin ponytails: tie at upper back-sides, flow out then hang to the calves (tail bones)
TAIL_N = 5
def tail_path(s):
    pts = [Vector((s * 0.1, 0.04, 1.725)), Vector((s * 0.17, 0.07, 1.67)), Vector((s * 0.235, 0.095, 1.5)),
           Vector((s * 0.26, 0.1, 1.25)), Vector((s * 0.265, 0.1, 0.95)), Vector((s * 0.255, 0.095, 0.65)), Vector((s * 0.235, 0.09, 0.36))]
    return pts
for s, nm in ((1, "L"), (-1, "R")):
    P = tail_path(s)
    rr = [0.03, 0.046, 0.056, 0.05, 0.038, 0.022, 0.003]
    rings = []
    for i in range(len(P) - 1):
        for t in (0.0, 0.5):
            if i == len(P) - 2 and t > 0:
                pass
            c = P[i].lerp(P[i + 1], t)
            r = rr[i] + (rr[i + 1] - rr[i]) * t
            rings.append((c, r * 0.75, r * 1.2))   # flatter side-to-side, like a ribbon of hair
    rings.append((P[-1], rr[-1], rr[-1]))
    loft("tail_" + nm, rings, "ice", ["tail_%d.%s" % (i, nm) for i in range(TAIL_N)] + ["head"], n=14)
    # hair tie / star clip anchor
    ellipsoid("tie_" + nm, P[0] + Vector((s * 0.008, 0, 0)), (0.022, 0.026, 0.026), "silver", ["head"], seg=10, rings=6)

# headset: band over the head, ear cups with silver wing fins, boom mic, star clip
band = []
for k in range(9):
    a = math.radians(-90 + 180 * k / 8)
    band.append(((math.sin(a) * 0.098, 0.004, HEAD_C.z + 0.005 + math.cos(a) * 0.118), 0.008, 0.012))
loft("headset_band", band, "silver", ["head"], n=8)
for s in (1, -1):
    cup_c = Vector((s * 0.1, 0.006, HEAD_C.z - 0.005))
    loft("cup_%d" % s, [(cup_c - Vector((s * 0.012, 0, 0)), 0.034, 0.034), (cup_c + Vector((s * 0.012, 0, 0)), 0.03, 0.03)], "silver", ["head"], n=16)
    loft("cupring_%d" % s, [(cup_c + Vector((s * 0.0125, 0, 0)), 0.022, 0.022), (cup_c + Vector((s * 0.016, 0, 0)), 0.02, 0.02)], "ice", ["head"], n=16)
    # wing fins: three swept blades going back/up
    for k in range(3):
        L = 0.12 - k * 0.022
        z0 = 0.03 - k * 0.022
        loft("wing_%d_%d" % (s, k), [(cup_c + Vector((s * 0.018, 0.0, z0)), 0.007, 0.02),
                                     (cup_c + Vector((s * 0.03, 0.01 + L * 0.5, z0 + 0.03 - k * 0.006)), 0.006, 0.014),
                                     (cup_c + Vector((s * 0.04, 0.01 + L, z0 + 0.06 - k * 0.01)), 0.002, 0.003)], "silver" if k != 1 else "ice_dk", ["head"], n=6)
loft("boom", [((0.095, -0.01, HEAD_C.z - 0.03), 0.004, 0.004), ((0.08, -0.06, HEAD_C.z - 0.07), 0.004, 0.004), ((0.045, -0.085, HEAD_C.z - 0.08), 0.004, 0.004)],
     "silver", ["head"], n=6)
ellipsoid("boom_tip", (0.043, -0.087, HEAD_C.z - 0.08), (0.008, 0.008, 0.008), "black", ["head"], seg=8, rings=6)
star_prism("star_clip", (0.065, -0.045, HEAD_C.z + 0.085), 0.03, 0.013, 0.012, "silver", ["head"], normal_axis="Y", rot_z=math.radians(-25))

# mic-wand in right hand (character's right = -X): silver shaft, black grip, star tip pointing down/forward
WAND_HAND = arm_pt(-1, WRIST - 0.06)
wand_top = WAND_HAND + Vector((0, 0, 0.06))
wand_tip = WAND_HAND + Vector((-0.02, -0.03, -0.48))
loft("wand_grip", [(wand_top, 0.012, 0.012), (WAND_HAND + Vector((0, 0, -0.05)), 0.012, 0.012)], "black", ["hand.R"], n=10)
loft("wand_shaft", [(WAND_HAND + Vector((0, 0, -0.05)), 0.0075, 0.0075), (wand_tip + Vector((0, 0, 0.04)), 0.0075, 0.0075)], "silver", ["hand.R"], n=10)
ellipsoid("wand_knob", wand_tip + Vector((0, 0, 0.045)), (0.014, 0.014, 0.014), "silver", ["hand.R"], seg=10, rings=6)
star_prism("wand_star", wand_tip, 0.05, 0.022, 0.016, "white", ["hand.R"], normal_axis="Y")
star_prism("wand_star_rim", wand_tip + Vector((0, 0.001, 0)), 0.056, 0.026, 0.01, "silver", ["hand.R"], normal_axis="Y")

# ---------------------------------------------------------------- armature
arm_data = bpy.data.armatures.new("TwinTailsRig")
rig = bpy.data.objects.new("TwinTailsRig", arm_data)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
EB = arm_data.edit_bones
BONES = {}
def bone(name, head, tail, parent=None, roll=0.0, connect=False):
    b = EB.new(name)
    b.head = Vector(head); b.tail = Vector(tail); b.roll = roll
    if parent:
        b.parent = EB[parent]; b.use_connect = connect
    BONES[name] = (Vector(head), Vector(tail))
    return b
bone("root", (0, 0, 0), (0, 0.2, 0))
bone("hips", (0, 0, 0.95), (0, 0, 1.08), "root")
bone("spine", (0, 0, 1.08), (0, 0, 1.25), "hips", connect=True)
bone("chest", (0, 0, 1.25), (0, 0, 1.46), "spine", connect=True)
bone("neck", (0, 0.008, 1.46), (0, 0.008, 1.56), "chest")
bone("head", (0, 0.008, 1.56), (0, 0.008, 1.76), "neck", connect=True)
for s, nm in ((1, "L"), (-1, "R")):
    bone("shoulder." + nm, (s * 0.03, 0, 1.43), arm_pt(s, SH_Z) - Vector((s * 0.02, 0, 0)), "chest")
    bone("upper_arm." + nm, arm_pt(s, SH_Z), arm_pt(s, ELB), "shoulder." + nm, connect=False)
    bone("forearm." + nm, arm_pt(s, ELB), arm_pt(s, WRIST), "upper_arm." + nm, connect=True)
    bone("hand." + nm, arm_pt(s, WRIST), arm_pt(s, WRIST - 0.1), "forearm." + nm, connect=True)
    bone("thigh." + nm, leg_pt(s, HIP_Z), leg_pt(s, KNEE_Z), "hips")
    bone("shin." + nm, leg_pt(s, KNEE_Z), leg_pt(s, ANK_Z), "thigh." + nm, connect=True)
    bone("foot." + nm, leg_pt(s, ANK_Z), leg_pt(s, ANK_Z) + Vector((0, -0.15, -0.06)), "shin." + nm, connect=True)
    P = tail_path(s)
    seg = [P[0], P[1], P[2], P[3], P[4], P[6]]
    for i in range(TAIL_N):
        bone("tail_%d.%s" % (i, nm), seg[i], seg[i + 1], "head" if i == 0 else "tail_%d.%s" % (i - 1, nm), connect=i > 0)
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------- skinning: distance-to-bone-segment weights
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length

def skin(ob, cands):
    for name in cands:
        if name not in ob.vertex_groups:
            ob.vertex_groups.new(name=name)
    for v in ob.data.vertices:
        ds = sorted(((seg_dist(v.co, *BONES[c]), c) for c in cands))
        best = ds[:2]
        ws = [1.0 / max(d, 0.004) ** 4 for d, _ in best]
        tot = sum(ws)
        for (d, c), w in zip(best, ws):
            if w / tot > 0.02:
                ob.vertex_groups[c].add([v.index], w / tot, 'REPLACE')

for ob, cands in PARTS:
    skin(ob, cands)

# join into one mesh, parent with armature modifier
bpy.ops.object.select_all(action='DESELECT')
for ob, _ in PARTS:
    ob.select_set(True)
body = PARTS[0][0]
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = "TwinTailsMesh"
body.data.name = "TwinTailsMesh"
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0002)
bpy.ops.object.mode_set(mode='OBJECT')
body.parent = rig
mod = body.modifiers.new("Armature", 'ARMATURE')
mod.object = rig

# wand tip marker: an empty parented to hand.R (imports in Godot as a BoneAttachment3D child "WandTip")
tip = bpy.data.objects.new("WandTip", None)
scene.collection.objects.link(tip)
tip.parent = rig
tip.parent_type = 'BONE'
tip.parent_bone = "hand.R"
bpy.context.view_layer.update()
tip.matrix_world = Matrix.Translation(wand_tip)

tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
print("TRIS", tris)

# ---------------------------------------------------------------- animations (pose-space euler keys)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='POSE')
PB = rig.pose.bones
for pb in PB:
    pb.rotation_mode = 'XYZ'

def clear_pose():
    for pb in PB:
        pb.rotation_euler = (0, 0, 0); pb.location = (0, 0, 0); pb.scale = (1, 1, 1)

def key(frame, poses, loc=None):
    """poses: {bone: (x,y,z) degrees} in bone-local axes. Bones pointing down: +X bends the bone toward
    the back... we verify visually; values chosen from turnarounds."""
    clear_pose()
    for name, rot in poses.items():
        PB[name].rotation_euler = [math.radians(a) for a in rot]
    if loc:
        for name, l in loc.items():
            PB[name].location = l
    for pb in PB:
        pb.keyframe_insert("rotation_euler", frame=frame)
        pb.keyframe_insert("location", frame=frame)

def action(name, frames):
    rig.animation_data_create()
    act = bpy.data.actions.new(name)
    rig.animation_data.action = act
    for f, poses, *rest in frames:
        key(f, poses, rest[0] if rest else None)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(frames[0][0]), act)
    rig.animation_data.action = None
    return act

ARM_DOWN = {"upper_arm.L": (0, 0, 0), "upper_arm.R": (0, 0, 0)}
def idle_pose(br):
    return {"chest": (br, 0, 0), "neck": (-br * 0.5, 0, 0), "upper_arm.L": (0, 0, -3 - br), "upper_arm.R": (0, 0, 3 + br),
            "forearm.L": (8, 0, 0), "forearm.R": (12, 0, 0), "tail_1.L": (0, 0, br), "tail_1.R": (0, 0, -br)}
action("idle_loop", [(1, idle_pose(0)), (25, idle_pose(2.0)), (49, idle_pose(0))])

def run_pose(ph):
    s = math.sin(ph)
    c = math.cos(ph)
    return {"hips": (0, s * 6, 0), "spine": (8, -s * 4, 0), "chest": (4, -s * 8, 0),
            "thigh.L": (-s * 38, 0, 0), "thigh.R": (s * 38, 0, 0),
            "shin.L": (max(0.0, c) * 55 + 10, 0, 0), "shin.R": (max(0.0, -c) * 55 + 10, 0, 0),
            "upper_arm.L": (s * 35, 0, -6), "upper_arm.R": (-s * 35, 0, 6), "forearm.L": (-35, 0, 0), "forearm.R": (-35, 0, 0),
            "tail_0.L": (5, 0, 0), "tail_0.R": (5, 0, 0), "tail_1.L": (3, 0, s * 3), "tail_1.R": (3, 0, -s * 3)}
run = []
for k in range(5):
    ph = 2 * math.pi * k / 4
    hop = abs(math.cos(ph)) * 0.025
    run.append((1 + k * 5, run_pose(ph), {"hips": (0, hop, 0)}))
action("run_loop", run)

shoot = {"upper_arm.R": (-75, 0, 10), "forearm.R": (-10, 0, 0), "hand.R": (-20, 0, 0), "chest": (0, 12, 0)}
action("shoot", [(1, {}), (4, shoot), (14, shoot), (22, {})])
action("aim_loop", [(1, shoot), (11, shoot)])   # held shoot/heal pose (blended in-engine, right arm only)
cast = {"upper_arm.L": (-150, 0, -15), "forearm.L": (-25, 0, 0), "chest": (-6, -8, 0), "head": (-10, 0, 0)}
action("cast", [(1, {}), (6, cast), (16, cast), (26, {})])
fall = {"hips": (-80, 0, 0), "spine": (10, 0, 0), "thigh.L": (-30, 0, 0), "thigh.R": (-20, 0, 0), "shin.L": (40, 0, 0),
        "upper_arm.L": (-60, 0, -40), "upper_arm.R": (-60, 0, 40), "head": (10, 0, 0)}
action("death", [(1, {}), (8, {"hips": (-30, 0, 0), "shin.L": (40, 0, 0), "shin.R": (40, 0, 0)}, {"hips": (0, 0, -0.25)}),
                 (18, fall, {"hips": (0, -0.75, 0.0)})])
clear_pose()
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------- export
os.makedirs(OUT_DIR, exist_ok=True)
out = os.path.join(OUT_DIR, "twin_tails.glb")
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=True, export_nla_strips=True,
                          export_animation_mode='NLA_TRACKS', export_skins=True, export_apply=False,
                          export_yup=True, export_materials='EXPORT', export_force_sampling=True)
print("EXPORTED", out)

# ---------------------------------------------------------------- turnaround renders (workbench flat + outline)
if SHOTS:
    os.makedirs(SHOTS, exist_ok=True)
    scene.render.engine = 'BLENDER_WORKBENCH'
    sh = scene.display.shading
    sh.light = 'FLAT'; sh.color_type = 'MATERIAL'; sh.show_object_outline = True; sh.object_outline_color = (0, 0, 0)
    sh.show_cavity = False
    scene.render.resolution_x = 900; scene.render.resolution_y = 1200
    scene.world = bpy.data.worlds.new("w"); scene.world.color = (1, 1, 1)
    sh.background_type = 'VIEWPORT'; sh.background_color = (1, 1, 1)
    scene.view_settings.view_transform = 'Standard'
    scene.render.film_transparent = False
    cam_d = bpy.data.cameras.new("cam"); cam_d.type = 'ORTHO'; cam_d.ortho_scale = 2.0
    cam = bpy.data.objects.new("cam", cam_d); scene.collection.objects.link(cam); scene.camera = cam
    for nm, yaw in (("front", 0), ("side", 90), ("three_quarter", 35)):
        a = math.radians(yaw)
        cam.location = (math.sin(a) * -6 * -1 if False else 6 * math.sin(a), -6 * math.cos(a), 0.9)
        cam.rotation_euler = (math.radians(90), 0, a)
        scene.render.filepath = os.path.join(SHOTS, "blender_%s.png" % nm)
        bpy.ops.render.render(write_still=True)
        print("SHOT", scene.render.filepath)
