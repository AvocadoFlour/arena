"""The Best - procedural Blender build (Blender 4.2, headless):
    blender -b --python src/heroes/models/the_best/blender/build_the_best.py -- [--out DIR] [--shots DIR] [--poses DIR]
Spiky-haired brawler: pointed shades + grin, bare chest with a bandage strap, black cape with white lining and
ragged hem, red waist sash with a long ragged tail, baggy white pants, bandaged forearms/shins, sandals, a huge
jagged cleaver sword in the right hand. Faces Blender -Y, metres, ~1.9 m. Exports ../the_best.glb."""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "common", "blender"))
from toonbuild import Build, arg
from mathutils import Vector, Matrix

B = Build("tb", {
    "skin":    (0.93, 0.78, 0.64),
    "line":    (0.42, 0.26, 0.18),
    "black":   (0.07, 0.07, 0.08),
    "white":   (0.97, 0.97, 0.96),
    "lining":  (0.94, 0.94, 0.95),
    "red":     (0.80, 0.10, 0.12),
    "red_dk":  (0.58, 0.06, 0.08),
    "bandage": (0.93, 0.91, 0.85),
    "steel":   (0.86, 0.88, 0.92),
    "steel_dk":(0.50, 0.53, 0.60),
    "grip":    (0.30, 0.20, 0.12),
    "sandal":  (0.36, 0.24, 0.15),
    "shades":  (0.04, 0.04, 0.05),
    "teeth":   (1.0, 1.0, 1.0),
    "mouth":   (0.15, 0.04, 0.05),
})
OUT = arg("--out", os.path.dirname(HERE))

HEAD_C = Vector((0, 0.0, 1.735)); HEAD_R = (0.088, 0.098, 0.112)
SH_Z = 1.515; SH_X = 0.2
ELB = 1.22; WRIST = 0.975
HIP_X = 0.1; HIP_Z = 0.98; KNEE_Z = 0.54; ANK_Z = 0.11
ARM_OUT = 0.09

def arm_pt(s, z):
    t = (SH_Z - z) / (SH_Z - WRIST)
    return Vector((s * (SH_X + 0.03 + ARM_OUT * t), 0.0, z))
def leg_pt(s, z):
    t = (HIP_Z - z) / (HIP_Z - ANK_Z)
    return Vector((s * (HIP_X + 0.03 * t), -0.004 * t, z))

# ------------------------------------------------------------- torso (bare, muscular)
TOR = [(1.585, 0.065, 0.06), (1.545, 0.17, 0.1), (1.50, 0.215, 0.12), (1.44, 0.215, 0.13), (1.37, 0.195, 0.128),
       (1.29, 0.165, 0.112), (1.20, 0.145, 0.1), (1.11, 0.145, 0.1), (1.03, 0.158, 0.104), (0.95, 0.155, 0.1)]
def tor_r(z):
    for (z0, a0, b0), (z1, a1, b1) in zip(TOR, TOR[1:]):
        if z1 <= z <= z0:
            t = (z0 - z) / (z0 - z1)
            return a0 + (a1 - a0) * t, b0 + (b1 - b0) * t
    return TOR[-1][1], TOR[-1][2]
B.loft("torso", [((0, 0.0, z), a, b) for z, a, b in TOR], "skin", ["hips", "spine", "chest", "neck"], n=18)
B.loft("neck", [((0, 0.01, 1.56), 0.058, 0.055), ((0, 0.01, 1.66), 0.052, 0.05)], "skin", ["neck", "head"], n=12)
for s in (1, -1):
    B.ellipsoid("pec_%d" % s, (s * 0.088, -0.072, 1.405), (0.092, 0.06, 0.068), "skin", ["chest"], seg=12, rings=8)
# bandage strap across the chest: tilted ring hugging the torso (left shoulder -> right hip)
pts = []
for k in range(25):
    th = 2 * math.pi * k / 24
    z = 1.30 + 0.17 * math.cos(th)
    a, b = tor_r(z)
    extra = 0.03 if (math.cos(th) > 0.3 and math.sin(th) < 0) else 0.0   # ride over the left pec
    pts.append(((math.cos(th) * (a + 0.012 + extra * 0.4), math.sin(th) * (b + 0.014 + extra), z), 0.007, 0.024))
B.loft("strap", pts, "bandage", ["chest", "spine"], n=6, cap0=False, cap1=False)

# ------------------------------------------------------------- sash (red) + hanging ragged tail
B.loft("sash", [((0, 0, 1.075), 0.152, 0.108), ((0, 0, 1.03), 0.172, 0.12), ((0, 0, 0.97), 0.176, 0.122), ((0, 0, 0.935), 0.17, 0.118)],
       "red", ["hips"], n=18)
B.ellipsoid("knot", (0.085, -0.122, 1.0), (0.05, 0.035, 0.045), "red_dk", ["hips"], seg=10, rings=6)
tail = B.jag([(0.03, 0.0), (0.13, 0.0), (0.17, -0.3), (0.22, -0.55), (0.06, -0.48), (0.04, -0.25)], 0.035, 4, seed=3, edges=[2, 3])
B.prism("sash_tail", tail, 0.012, "red", ["hips", "thigh.L"], xf=Matrix.Translation((0.02, -0.135, 0.99)) @ Matrix.Rotation(math.radians(4), 4, 'X'))

# ------------------------------------------------------------- legs: baggy white pants, bandaged shins, sandals
B.loft("pants_top", [((0, 0, 1.0), 0.17, 0.115), ((0, 0, 0.93), 0.2, 0.125), ((0, 0.0, 0.86), 0.2, 0.12)], "white", ["hips"], n=18)
for s, nm in ((1, "L"), (-1, "R")):
    zs = [0.97, 0.86, 0.74, 0.62, 0.52, 0.42, 0.34, 0.31]
    rr = [0.13, 0.135, 0.125, 0.118, 0.125, 0.115, 0.075, 0.07]
    B.loft("pants_" + nm, [(leg_pt(s, z) + Vector((s * 0.008, 0, 0)), r, r * 1.08) for z, r in zip(zs, rr)], "white", ["thigh." + nm, "shin." + nm], n=14)
    rings = []
    z = 0.335
    k = 0
    while z > ANK_Z + 0.01:
        r = 0.054 - (0.335 - z) * 0.05 + (0.004 if k % 2 == 0 else 0.0)
        rings.append((leg_pt(s, z), r, r * 1.05)); z -= 0.03; k += 1
    B.loft("shin_wrap_" + nm, rings, "bandage", ["shin." + nm], n=12)
    fx = s * (HIP_X + 0.03)
    B.ellipsoid("foot_" + nm, (fx, -0.055, 0.055), (0.052, 0.115, 0.042), "skin", ["foot." + nm], seg=12, rings=7)
    B.box("sole_" + nm, (fx, -0.055, 0.014), (0.12, 0.28, 0.026), "sandal", ["foot." + nm], bevel=0.008)
    for k, y in enumerate((-0.12, 0.0)):
        B.box("strap_%s_%d" % (nm, k), (fx, -0.05 + y * 0.6, 0.075 - k * 0.01), (0.112, 0.03, 0.018), "sandal", ["foot." + nm], bevel=0.005, rot=(0, 0, 0))

# ------------------------------------------------------------- arms (muscular, bandaged forearms, fists)
for s, nm in ((1, "L"), (-1, "R")):
    az = [SH_Z + 0.01, 1.42, 1.33, ELB, 1.14, 1.06, WRIST]
    ar = [0.07, 0.066, 0.062, 0.05, 0.058, 0.05, 0.042]
    B.loft("arm_" + nm, [(arm_pt(s, z), r, r) for z, r in zip(az, ar)], "skin", ["upper_arm." + nm, "forearm." + nm], n=12)
    B.ellipsoid("delt_" + nm, arm_pt(s, SH_Z - 0.035), (0.082, 0.078, 0.08), "skin", ["upper_arm." + nm, "chest"], seg=12, rings=8)
    rings = []
    z = 1.16; k = 0
    while z > WRIST - 0.01:
        r = 0.058 - (1.16 - z) * 0.08 + (0.005 if k % 2 == 0 else 0.0)
        rings.append((arm_pt(s, z), r, r)); z -= 0.028; k += 1
    B.loft("wrap_" + nm, rings, "bandage", ["forearm." + nm], n=12)
    # simple hand: palm block + thumb + 3-finger mitt + separate index finger (own bones, so the ult can point)
    hp = arm_pt(s, WRIST)
    B.box("palm_" + nm, hp + Vector((0, 0, -0.045)), (0.042, 0.09, 0.075), "skin", ["hand." + nm], bevel=0.012)
    B.loft("thumb_" + nm, [(hp + Vector((-s * 0.012, -0.04, -0.03)), 0.017, 0.017), (hp + Vector((-s * 0.022, -0.07, -0.06)), 0.014, 0.014),
                           (hp + Vector((-s * 0.024, -0.082, -0.085)), 0.011, 0.011)], "skin", ["hand." + nm], n=8)
    B.box("mitt_" + nm, hp + Vector((0, 0.012, -0.112)), (0.036, 0.062, 0.07), "skin", ["fingers." + nm], bevel=0.012)
    B.box("index_" + nm, hp + Vector((0, -0.034, -0.118)), (0.034, 0.028, 0.088), "skin", ["index." + nm], bevel=0.01)

# ------------------------------------------------------------- head: grin, pointed shades, spiky black hair
B.ellipsoid("head", HEAD_C, HEAD_R, "skin", ["head"], seg=18, rings=12)
B.ellipsoid("jaw", HEAD_C + Vector((0, -0.016, -0.06)), (0.078, 0.082, 0.058), "skin", ["head"], seg=14, rings=9)
for s in (1, -1):
    B.ellipsoid("ear_%d" % s, HEAD_C + Vector((s * 0.088, 0.01, -0.01)), (0.014, 0.022, 0.03), "skin", ["head"], seg=8, rings=6)
FY = HEAD_C.y - HEAD_R[1]
# grin: dark mouth + white teeth band
B.decal("mouth", [(-0.042, 0.004), (-0.02, -0.018), (0.0, -0.024), (0.02, -0.018), (0.042, 0.004), (0.0, -0.004)],
        (0, FY + 0.006, HEAD_C.z - 0.078), "mouth", ["head"])
B.decal("teeth", [(-0.036, 0.0), (-0.018, -0.012), (0.0, -0.015), (0.018, -0.012), (0.036, 0.0), (0.0, -0.006)],
        (0, FY + 0.004, HEAD_C.z - 0.079), "teeth", ["head"])
# pointed shades: two angular lenses + bridge (thin prisms wrapped slightly around the face)
lens = [(0.004, 0.012), (0.062, 0.02), (0.074, 0.006), (0.05, -0.022), (0.012, -0.016)]
for s in (1, -1):
    pts2 = [(s * x, z) for x, z in lens]
    if s < 0:
        pts2 = list(reversed(pts2))
    B.prism("lens_%d" % s, pts2, 0.008, "shades", ["head"],
            xf=Matrix.Translation((0, FY + 0.012, HEAD_C.z - 0.006)) @ Matrix.Rotation(-s * 0.28, 4, 'Z'))
    B.loft("temple_%d" % s, [((s * 0.072, FY + 0.03, HEAD_C.z + 0.002), 0.004, 0.004), ((s * 0.09, 0.0, HEAD_C.z + 0.004), 0.004, 0.004)], "shades", ["head"], n=5)
B.box("bridge", (0, FY + 0.006, HEAD_C.z + 0.002), (0.02, 0.008, 0.008), "shades", ["head"])
B.ellipsoid("hair_cap", HEAD_C + Vector((0, 0.016, 0.03)), (0.096, 0.1, 0.098), "black", ["head"], seg=16, rings=10)
rnd = random.Random(7)
spikes = []
for k in range(9):        # crown ring, tilted back
    a = 2 * math.pi * k / 9 + 0.2
    spikes.append((Vector((math.sin(a) * 0.75, math.cos(a) * 0.75 + 0.15, 0.75)), 0.13))
for k in range(7):        # lower ring (sides + back)
    a = math.radians(-120 + 240 * k / 6)
    spikes.append((Vector((math.sin(a), math.cos(a) * 0.9 + 0.2, 0.15)), 0.11))
for x in (-0.5, -0.15, 0.2, 0.55):   # fringe spikes over the forehead, pointing up/forward
    spikes.append((Vector((x, -0.75, 0.75)), 0.1))
spikes.append((Vector((0, 0.1, 1.0)), 0.14))
for i, (d, L) in enumerate(spikes):
    d = d.normalized()
    base = HEAD_C + Vector((0, 0.016, 0.03)) + Vector((d.x * 0.085, d.y * 0.09, d.z * 0.088))
    L *= rnd.uniform(0.85, 1.2)
    tip = base + d * L + Vector((0, 0.02, 0.02))
    B.loft("spike_%d" % i, [(base - d * 0.01, 0.034, 0.03), (base.lerp(tip, 0.5), 0.02, 0.018), (tip, 0.002, 0.002)], "black", ["head"], n=5)

# ------------------------------------------------------------- cape: black outside, white lining, ragged hem
NU, NV = 18, 9
rnd = random.Random(11)
hem = [rnd.uniform(0.0, 0.22) * (1.0 if k % 2 else 0.35) for k in range(NU + 1)]
def cape_pt(u, v, inner):
    phi = math.radians(-78 + 156 * u)
    rx = 0.235 + 0.36 * v + 0.075 * math.sin(math.pi * min(1.0, v / 0.7))   # clear the arms
    ry = 0.13 + 0.26 * v
    yoff = 0.03 + 0.08 * v
    z = 1.565 - 1.12 * v
    if v >= 0.999:
        z += hem[int(round(u * NU))]
    elif v > 0.85:
        z += hem[int(round(u * NU))] * (v - 0.85) / 0.15 * 0.5
    k = 0.965 if inner else 1.0
    return Vector((math.sin(phi) * rx * k, math.cos(phi) * ry * k + yoff, z - (0.004 if inner else 0)))
import bmesh
for inner in (False, True):
    bm = bmesh.new()
    G = [[bm.verts.new(cape_pt(i / NU, j / NV, inner)) for i in range(NU + 1)] for j in range(NV + 1)]
    for j in range(NV):
        for i in range(NU):
            q = (G[j][i], G[j][i + 1], G[j + 1][i + 1], G[j + 1][i])
            bm.faces.new(tuple(reversed(q)) if inner else q)
    bm.normal_update()
    cands = ["chest"] + ["cape_%d.%s" % (k, s) for k in range(3) for s in "LR"]
    B.obj("cape_in" if inner else "cape_out", bm, "lining" if inner else "black", cands)
# collar band over the shoulders
B.loft("cape_collar", [((math.sin(math.radians(a)) * 0.2, math.cos(math.radians(a)) * 0.115 + 0.02, 1.57), 0.012, 0.03)
                       for a in range(-90, 91, 15)], "black", ["chest"], n=6)

# ------------------------------------------------------------- the sword (right hand, blade forward in rest pose)
HAND = arm_pt(-1, WRIST - 0.06)
GUARD = HAND + Vector((0, -0.09, 0))
L = 1.12
blade = [(0.0, 0.062), (0.3, 0.07), (0.62, 0.085), (0.9, 0.11), (L, -0.01), (0.94, -0.13), (0.86, -0.1), (0.6, -0.11), (0.3, -0.085), (0.0, -0.06)]
blade = B.jag(blade, 0.022, 3, seed=5, edges=[1, 2, 6, 7, 8])
# local x -> world -Y (length), local y -> world X (thickness), local z -> world Z (width)
XF = Matrix(((0, 1, 0, GUARD.x), (-1, 0, 0, GUARD.y), (0, 0, 1, GUARD.z), (0, 0, 0, 1)))
B.prism("blade", blade, 0.026, "steel", ["hand.R"], xf=XF)
B.prism("fuller", [(0.06, 0.012), (0.82, 0.02), (0.86, -0.004), (0.06, -0.006)], 0.032, "steel_dk", ["hand.R"], xf=XF)
B.box("guard", GUARD + Vector((0, 0.012, 0)), (0.06, 0.04, 0.3), "steel_dk", ["hand.R"], bevel=0.008)
for s in (1, -1):
    B.ellipsoid("guard_end_%d" % s, GUARD + Vector((0, 0.012, s * 0.16)), (0.036, 0.03, 0.03), "steel_dk", ["hand.R"], seg=8, rings=6)
B.loft("grip", [(GUARD + Vector((0, 0.03, 0)), 0.022, 0.022), (HAND + Vector((0, 0.1, 0)), 0.02, 0.02)], "grip", ["hand.R"], n=8)
B.ellipsoid("pommel", HAND + Vector((0, 0.115, 0)), (0.03, 0.03, 0.03), "steel_dk", ["hand.R"], seg=8, rings=6)
SWORD_TIP = GUARD + Vector((0, -L, -0.01))

# ------------------------------------------------------------- armature
B.begin_rig("TheBestRig")
B.bone("root", (0, 0, 0), (0, 0.2, 0))
B.bone("hips", (0, 0, 0.98), (0, 0, 1.12), "root")
B.bone("spine", (0, 0, 1.12), (0, 0, 1.3), "hips", connect=True)
B.bone("chest", (0, 0, 1.3), (0, 0, 1.55), "spine", connect=True)
B.bone("neck", (0, 0.01, 1.55), (0, 0.01, 1.66), "chest")
B.bone("head", (0, 0.01, 1.66), (0, 0.01, 1.88), "neck", connect=True)
for s, nm in ((1, "L"), (-1, "R")):
    B.bone("shoulder." + nm, (s * 0.04, 0, 1.52), arm_pt(s, SH_Z) - Vector((s * 0.03, 0, 0)), "chest")
    B.bone("upper_arm." + nm, arm_pt(s, SH_Z), arm_pt(s, ELB), "shoulder." + nm)
    B.bone("forearm." + nm, arm_pt(s, ELB), arm_pt(s, WRIST), "upper_arm." + nm, connect=True)
    B.bone("hand." + nm, arm_pt(s, WRIST), arm_pt(s, WRIST - 0.08), "forearm." + nm, connect=True)
    B.bone("fingers." + nm, arm_pt(s, WRIST - 0.08) + Vector((0, 0.012, 0)), arm_pt(s, WRIST - 0.15) + Vector((0, 0.012, 0)), "hand." + nm)
    B.bone("index." + nm, arm_pt(s, WRIST - 0.08) + Vector((0, -0.034, 0)), arm_pt(s, WRIST - 0.16) + Vector((0, -0.034, 0)), "hand." + nm)
    B.bone("thigh." + nm, leg_pt(s, HIP_Z), leg_pt(s, KNEE_Z), "hips")
    B.bone("shin." + nm, leg_pt(s, KNEE_Z), leg_pt(s, ANK_Z), "thigh." + nm, connect=True)
    B.bone("foot." + nm, leg_pt(s, ANK_Z), leg_pt(s, ANK_Z) + Vector((0, -0.16, -0.07)), "shin." + nm, connect=True)
    chain = [Vector((s * 0.16, 0.14, 1.53)), Vector((s * 0.25, 0.22, 1.18)), Vector((s * 0.33, 0.3, 0.82)), Vector((s * 0.4, 0.36, 0.46))]
    for k in range(3):
        B.bone("cape_%d.%s" % (k, nm), chain[k], chain[k + 1], "chest" if k == 0 else "cape_%d.%s" % (k - 1, nm), connect=k > 0)
B.end_rig()
tris = B.skin_and_join("TheBestMesh")
B.marker("SwordTip", "hand.R", SWORD_TIP)

# ------------------------------------------------------------- animations (24 fps)
CURL = float(arg("--curl", "-90"))
B.begin_anim()
# idle: sword resting on the right shoulder (concept pose), left fist on hip, chest breathing
FIST = {"fingers.L": (CURL, 0, 0), "index.L": (CURL, 0, 0), "fingers.R": (CURL, 0, 0), "index.R": (CURL, 0, 0)}
_c = [float(v) for v in arg("--carry", "20,0,10,-150,-35,0,0").split(",")]
CARRY = {"upper_arm.R": (_c[0], _c[1], _c[2]), "forearm.R": (_c[3], 0, 0), "hand.R": (_c[4], _c[5], _c[6])}
CARRY.update(FIST)   # fists by default (right hand wraps the grip); the ult opens the left index to point
def idle(br):
    p = {"chest": (br, 0, 0), "neck": (-br * 0.5, 0, 0), "upper_arm.L": (0, 0, 25), "forearm.L": (-40, 0, 0), "hand.L": (0, 0, 0)}
    p.update(CARRY)
    p.update(FIST)
    return p
B.action("idle_loop", [(1, idle(0)), (25, idle(2.5)), (49, idle(0))])

def run_pose(ph):
    s, c = math.sin(ph), math.cos(ph)
    p = {"hips": (0, s * 7, 0), "spine": (10, -s * 4, 0), "chest": (6, -s * 9, 0),
         "thigh.L": (-s * 40, 0, 0), "thigh.R": (s * 40, 0, 0),
         "shin.L": (max(0.0, c) * 60 + 10, 0, 0), "shin.R": (max(0.0, -c) * 60 + 10, 0, 0),
         "upper_arm.L": (s * 40, 0, 8), "forearm.L": (-45, 0, 0)}
    p.update(CARRY)
    p["upper_arm.R"] = (20 + s * 5, 0, 10)
    return p
run = []
for k in range(5):
    ph = 2 * math.pi * k / 4
    run.append((1 + k * 5, run_pose(ph), {"hips": (0, abs(math.cos(ph)) * 0.03, 0)}))
B.action("run_loop", run)

# combo swings (upper body; ~0.42 s): A = forehand sweep right->left, B = backhand left->right
def _mix(a, b, t):
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k, (0, 0, 0)), b.get(k, (0, 0, 0))
        out[k] = tuple(x + (y - x) * t for x, y in zip(va, vb))
    return out
def _fist(p):
    q = dict(p); q.update(FIST); return q
# anticipation (deeper wind-up) -> fast hit (frame 8, ~0.29 s) -> follow-through overshoot -> settle -> carry
WIND_A = {"chest": (0, -35, 0), "spine": (0, -10, 0), "upper_arm.R": (-95, 60, 0), "forearm.R": (-30, 0, 0), "hand.R": (70, 0, 0)}
HIT_A = {"chest": (8, 40, 0), "spine": (4, 12, 0), "upper_arm.R": (-80, -65, 0), "forearm.R": (-5, 0, 0), "hand.R": (70, 0, 0)}
ANT_A = _mix(WIND_A, {"chest": (-6, -50, 0), "spine": (0, -16, 0), "upper_arm.R": (-105, 78, 0), "forearm.R": (-45, 0, 0), "hand.R": (70, 0, 0)}, 1.0)
FOL_A = {"chest": (14, 55, 0), "spine": (8, 18, 0), "upper_arm.R": (-62, -92, 0), "forearm.R": (-12, 0, 0), "hand.R": (78, 0, 0)}
B.action("swing_a", [(1, _fist(CARRY)), (4, _fist(ANT_A)), (6, _fist(WIND_A)), (8, _fist(HIT_A)), (11, _fist(FOL_A)), (15, _fist(_mix(FOL_A, HIT_A, 0.5))), (21, _fist(CARRY))])
WIND_B = {"chest": (0, 35, 0), "spine": (0, 10, 0), "upper_arm.R": (-90, -70, 0), "forearm.R": (-40, 0, 0), "hand.R": (70, 0, 0)}
HIT_B = {"chest": (8, -40, 0), "spine": (4, -12, 0), "upper_arm.R": (-85, 55, 0), "forearm.R": (-5, 0, 0), "hand.R": (70, 0, 0)}
ANT_B = {"chest": (-6, 50, 0), "spine": (0, 16, 0), "upper_arm.R": (-98, -85, 0), "forearm.R": (-55, 0, 0), "hand.R": (70, 0, 0)}
FOL_B = {"chest": (14, -55, 0), "spine": (8, -18, 0), "upper_arm.R": (-70, 80, 0), "forearm.R": (-12, 0, 0), "hand.R": (62, 0, 0)}
B.action("swing_b", [(1, _fist(CARRY)), (4, _fist(ANT_B)), (6, _fist(WIND_B)), (8, _fist(HIT_B)), (11, _fist(FOL_B)), (15, _fist(_mix(FOL_B, HIT_B, 0.5))), (21, _fist(CARRY))])
# finisher: two-handed overhead slam with a crouch (full body)
UP = {"spine": (-12, 0, 0), "chest": (-10, 0, 0), "upper_arm.R": (-170, 0, 15), "upper_arm.L": (-170, 0, -15),
      "forearm.R": (-30, 0, 0), "forearm.L": (-30, 0, 0), "thigh.L": (-10, 0, 0), "thigh.R": (10, 0, 0)}
SLAM = {"spine": (30, 0, 0), "chest": (20, 0, 0), "head": (-20, 0, 0), "upper_arm.R": (-60, 0, 20), "upper_arm.L": (-60, 0, -20),
        "forearm.R": (-10, 0, 0), "forearm.L": (-10, 0, 0), "thigh.L": (-55, 0, 0), "thigh.R": (-20, 0, 0),
        "shin.L": (70, 0, 0), "shin.R": (60, 0, 0), "foot.L": (-15, 0, 0)}
ANT_F = {"spine": (14, 0, 0), "chest": (8, 0, 0), "upper_arm.R": (-30, 0, 25), "upper_arm.L": (-30, 0, -25), "forearm.R": (-70, 0, 0),
         "forearm.L": (-70, 0, 0), "thigh.L": (-35, 0, 0), "thigh.R": (-30, 0, 0), "shin.L": (55, 0, 0), "shin.R": (50, 0, 0)}
UP2 = dict(UP); UP2.update({"spine": (-18, 0, 0), "chest": (-14, 0, 0), "head": (-8, 0, 0)})
FOL_F = dict(SLAM); FOL_F.update({"spine": (40, 0, 0), "chest": (26, 0, 0), "upper_arm.R": (-40, 0, 22), "upper_arm.L": (-40, 0, -22)})
B.action("finisher", [(1, _fist(CARRY)), (4, _fist(ANT_F), {"hips": (0, -0.08, 0)}), (8, _fist(UP2)), (11, _fist(SLAM)),
                      (14, _fist(FOL_F), {"hips": (0, -0.06, 0)}), (20, _fist(FOL_F), {"hips": (0, -0.06, 0)}), (28, _fist(CARRY))])
# leap (Fearless Leap, ~0.75 s airborne): crouch, launch, tuck with sword overhead, slam on landing
CROUCH = {"thigh.L": (-50, 0, 0), "thigh.R": (-50, 0, 0), "shin.L": (80, 0, 0), "shin.R": (80, 0, 0), "spine": (25, 0, 0)}
CROUCH.update(CARRY)
TUCK = {"thigh.L": (-80, 0, 0), "thigh.R": (-60, 0, 0), "shin.L": (100, 0, 0), "shin.R": (90, 0, 0), "spine": (-5, 0, 0),
        "upper_arm.R": (-175, 0, 10), "forearm.R": (-25, 0, 0), "upper_arm.L": (-160, 0, -20)}
B.action("leap", [(1, CROUCH), (4, {"spine": (-8, 0, 0), "upper_arm.R": (-150, 0, 10), "upper_arm.L": (-140, 0, -20)}), (10, TUCK), (16, TUCK), (20, SLAM), (26, SLAM), (32, CARRY)])
# dash (Swagger Step): low lean forward, sword trailing behind
DASH = {"spine": (30, 0, 0), "chest": (10, 0, 0), "head": (-25, 0, 0), "upper_arm.R": (45, 0, -30), "forearm.R": (-20, 0, 0),
        "upper_arm.L": (-50, 0, 20), "forearm.L": (-30, 0, 0), "thigh.L": (-60, 0, 0), "thigh.R": (30, 0, 0), "shin.R": (50, 0, 0), "shin.L": (40, 0, 0)}
B.action("dash", [(1, CARRY), (3, DASH), (8, DASH), (14, CARRY)])
# ult (No Limits): point forward with the left hand (concept pose), sword raised high, chest out
ULT = {"chest": (-12, 0, 0), "head": (-10, 0, 0), "upper_arm.L": (-85, 0, 0), "forearm.L": (-10, 0, 0),
       "upper_arm.R": (-170, 0, -10), "forearm.R": (-20, 0, 0), "fingers.L": (CURL, 0, 0), "index.L": (0, 0, 0)}
B.action("ult", [(1, CARRY), (6, ULT), (26, ULT), (34, CARRY)])
# death: drop to the knees and fall forward
KNEEL = {"thigh.L": (-90, 0, 0), "thigh.R": (-20, 0, 0), "shin.L": (100, 0, 0), "shin.R": (110, 0, 0), "spine": (20, 0, 0), "head": (20, 0, 0),
         "upper_arm.R": (-20, 0, -20), "upper_arm.L": (-20, 0, 20)}
DOWN = {"hips": (80, 0, 0), "thigh.L": (-20, 0, 0), "thigh.R": (-10, 0, 0), "shin.L": (30, 0, 0), "upper_arm.R": (-150, 0, -30),
        "upper_arm.L": (-150, 0, 30), "head": (-30, 0, 0)}
B.action("death", [(1, CARRY), (8, KNEEL, {"hips": (0, -0.35, 0)}), (18, DOWN, {"hips": (0, -0.8, 0.0)})])
B.end_anim()

B.export(os.path.join(OUT, "the_best.glb"))
SH = arg("--shots")
B.shots(SH, 0.95, 2.6)
PO = arg("--poses")
if PO:
    B.shots(PO, 0.95, 2.4, views=())
    B.pose_shots(PO, [(a, f, y, "%s_%d_%d.png" % (a, f, y)) for a, f, y in
                      [("idle_loop", 1, 0), ("idle_loop", 1, 90), ("swing_a", 4, 0), ("swing_a", 7, 0), 
                       ("leap", 12, 90), ("dash", 5, 90), ("ult", 12, 0), ("death", 18, 90), ("run_loop", 6, 90),
                       ("swing_a", 11, 0), ("finisher", 4, 90), ("finisher", 8, 90), ("finisher", 11, 90), ("finisher", 14, 90), ("ult", 12, 90)]], 0.95, 2.6)
