"""Übel - procedural Blender build (Blender 4.2, headless):
    blender -b --python src/heroes/models/ubel/blender/build_ubel.py -- [--out DIR] [--shots DIR] [--poses DIR]
Fan character based on Übel (Frieren), in the game's flat toon style. Tall (~8 heads, 1.68 m), small head: dark
green hair with three bangs and a thick side ponytail over her left shoulder, droopy purple eyes, calm faint smile.
Black fitted top held by straps to a choker ring, thick front-clasped belt with side loops, black pleated skirt,
black knee boots, all with white trims; right forearm glove, arm/thigh bands. Weapon: black staff-spear with two
curved blades and a zigzag tip (BladeTip marker). Faces Blender -Y, metres. Exports ../ubel.glb."""
import sys, os, math
import bmesh
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "common", "blender"))
from toonbuild import Build, arg
from mathutils import Vector, Matrix

B = Build("ubel", {
    "skin":    (0.98, 0.90, 0.84),
    "skin_dk": (0.88, 0.72, 0.66),
    "hair":    (0.14, 0.27, 0.20),
    "hair_lt": (0.20, 0.36, 0.27),
    "eye":     (0.10, 0.08, 0.12),
    "iris":    (0.52, 0.30, 0.66),
    "white":   (0.97, 0.97, 0.97),
    "sclera":  (0.98, 0.98, 0.98),
    "black":   (0.07, 0.07, 0.09),
    "cloth":   (0.10, 0.10, 0.12),
    "pleat":   (0.05, 0.05, 0.06),
    "silver":  (0.78, 0.80, 0.84),
    "mouth":   (0.66, 0.36, 0.38),
    "blade":   (0.62, 0.64, 0.70),
    "ribbon":  (0.06, 0.06, 0.07),
})
OUT = arg("--out", os.path.dirname(HERE))

HEAD_C = Vector((0, 0.0, 1.575)); HEAD_R = (0.072, 0.082, 0.1)
SH_Z = 1.39; SH_X = 0.145
ELB = 1.12; WRIST = 0.885
HIP_X = 0.072; HIP_Z = 0.88; KNEE_Z = 0.48; ANK_Z = 0.075
ARM_OUT = 0.035

def arm_pt(s, z):
    t = (SH_Z - z) / (SH_Z - WRIST)
    return Vector((s * (SH_X + 0.015 + ARM_OUT * t), 0.0, z))
def leg_pt(s, z):
    t = (HIP_Z - z) / (HIP_Z - ANK_Z)
    return Vector((s * (HIP_X + 0.012 * t), -0.004 * t, z))

# ------------------------------------------------------------- torso: skin shoulders/chest top, black fitted top
B.loft("neck", [((0, 0.006, 1.43), 0.036, 0.034), ((0, 0.006, 1.52), 0.034, 0.032)], "skin", ["neck", "head"], n=12)
UP = [(1.455, 0.045, 0.04), (1.43, 0.115, 0.07), (1.395, 0.14, 0.08), (1.35, 0.14, 0.088)]
B.loft("chest_skin", [((0, 0.0, z), a, b) for z, a, b in UP], "skin", ["chest", "neck"], n=18)
TOP = [(1.355, 0.142, 0.092), (1.31, 0.14, 0.098), (1.26, 0.124, 0.086), (1.19, 0.104, 0.072), (1.12, 0.1, 0.07), (1.06, 0.112, 0.076)]
B.loft("top", [((0, 0.0, z), a, b) for z, a, b in TOP], "cloth", ["chest", "spine", "hips"], n=20)
B.loft("top_trim", [((0, 0.0, 1.358), 0.145, 0.095), ((0, 0.0, 1.348), 0.146, 0.096)], "white", ["chest"], n=20, cap0=False, cap1=False)
# choker + ring, three front straps and one back strap up to the ring
B.loft("choker", [((0, 0.006, 1.47), 0.039, 0.037), ((0, 0.006, 1.49), 0.039, 0.037)], "black", ["neck"], n=14)
RING = Vector((0, -0.034, 1.474))
B.loft("ring", [(RING + Vector((0.0, 0, 0.012 * math.sin(a))) + Vector((0.012 * math.cos(a), 0, 0)), 0.003, 0.003) for a in
                [2 * math.pi * k / 10 for k in range(11)]], "silver", ["neck"], n=6)
for x0 in (-0.09, 0.0, 0.09):
    a = Vector((x0, -0.095, 1.352)); b = RING + Vector((x0 * 0.1, -0.004, -0.012))
    B.loft("strap_%d" % int(x0 * 100), [(a, 0.006, 0.003), (a.lerp(b, 0.5) + Vector((0, -0.012, 0)), 0.005, 0.003), (b, 0.004, 0.003)], "black", ["chest", "neck"], n=6)
B.loft("strap_back", [(Vector((0, 0.095, 1.352)), 0.006, 0.003), (Vector((0, 0.06, 1.43)), 0.005, 0.003), (Vector((0, 0.03, 1.47)), 0.004, 0.003)], "black", ["chest", "neck"], n=6)
for s, nm in ((1, "L"), (-1, "R")):
    B.ellipsoid("shoulder_" + nm, arm_pt(s, SH_Z - 0.015) + Vector((-s * 0.012, 0, 0)), (0.05, 0.05, 0.045), "skin", ["upper_arm." + nm, "chest"], seg=12, rings=8)

# ------------------------------------------------------------- belt + pleated skirt
B.loft("belt", [((0, 0, 1.075), 0.118, 0.08), ((0, 0, 1.03), 0.124, 0.084)], "black", ["hips"], n=20)
for z in (1.077, 1.028):
    B.loft("belt_trim_%d" % int(z * 1000), [((0, 0, z + 0.003), 0.12, 0.082), ((0, 0, z - 0.003), 0.125, 0.085)], "white", ["hips"], n=20, cap0=False, cap1=False)
B.box("buckle", (0, -0.088, 1.052), (0.05, 0.012, 0.04), "silver", ["hips"], bevel=0.004)
B.box("buckle_in", (0, -0.094, 1.052), (0.03, 0.006, 0.022), "black", ["hips"])
for s in (1, -1):
    for k in (0, 1):
        B.loft("loop_%d_%d" % (s, k), [(Vector((s * (0.09 + k * 0.025), -0.05 + k * 0.03, 1.045)), 0.008, 0.004),
                                       (Vector((s * (0.11 + k * 0.025), -0.045 + k * 0.03, 0.99)), 0.008, 0.004)], "black", ["hips"], n=6)
SK = [(1.03, 0.124, 0.086), (0.95, 0.155, 0.12), (0.87, 0.19, 0.155), (0.8, 0.215, 0.18)]
B.loft("skirt", [((0, 0.005, z), a, b) for z, a, b in SK], "cloth", ["hips"], n=24, cap0=False, cap1=False)
B.loft("skirt_hem", [((0, 0.005, 0.805), 0.216, 0.181), ((0, 0.005, 0.79), 0.218, 0.183)], "white", ["hips"], n=24, cap0=False, cap1=False)
for k in range(12):   # pleat folds: dark creases down the skirt
    a = 2 * math.pi * (k + 0.5) / 12
    pts = [(Vector((math.cos(a) * rx * 1.012, math.sin(a) * ry * 1.012 + 0.005, z)), 0.004, 0.004) for z, rx, ry in SK[1:]]
    B.loft("pleat_%d" % k, pts, "pleat", ["hips"], n=4)

# ------------------------------------------------------------- legs: thighs + bands, black knee boots with white tops
for s, nm in ((1, "L"), (-1, "R")):
    lz = [0.93, 0.8, 0.66, KNEE_Z + 0.03, KNEE_Z]
    lr = [0.068, 0.062, 0.055, 0.046, 0.044]
    B.loft("leg_" + nm, [(leg_pt(s, z), r, r * 1.05) for z, r in zip(lz, lr)], "skin", ["thigh." + nm, "shin." + nm], n=12)
    B.loft("thighband_" + nm, [(leg_pt(s, 0.705), 0.06, 0.062), (leg_pt(s, 0.68), 0.059, 0.061)], "black", ["thigh." + nm], n=12)
    bz = [0.5, 0.44, 0.36, 0.25, 0.15, ANK_Z]
    br = [0.05, 0.049, 0.046, 0.04, 0.036, 0.04]
    B.loft("boot_" + nm, [(leg_pt(s, z), r, r * 1.08) for z, r in zip(bz, br)], "black", ["shin." + nm, "foot." + nm], n=12)
    B.loft("boottrim_" + nm, [(leg_pt(s, 0.515), 0.052, 0.056), (leg_pt(s, 0.49), 0.052, 0.056)], "white", ["shin." + nm], n=12)
    B.loft("shinband_" + nm, [(leg_pt(s, 0.33), 0.047, 0.05), (leg_pt(s, 0.31), 0.046, 0.049)], "white", ["shin." + nm], n=12)
    fx = leg_pt(s, ANK_Z).x
    B.box("foot_" + nm, (fx, -0.04, 0.045), (0.07, 0.19, 0.07), "black", ["foot." + nm], bevel=0.02)
    B.box("sole_" + nm, (fx, -0.04, 0.008), (0.074, 0.2, 0.016), "white", ["foot." + nm], bevel=0.006)
    B.box("heel_" + nm, (fx, 0.035, 0.03), (0.05, 0.05, 0.05), "black", ["foot." + nm], bevel=0.008)

# ------------------------------------------------------------- arms: slim; right glove, arm bands
for s, nm in ((1, "L"), (-1, "R")):
    az = [1.37, 1.28, ELB, 1.06, 0.97, WRIST]
    ar = [0.04, 0.036, 0.031, 0.032, 0.028, 0.024]
    B.loft("arm_" + nm, [(arm_pt(s, z), r, r) for z, r in zip(az, ar)], "skin", ["upper_arm." + nm, "forearm." + nm], n=12)
    hp = arm_pt(s, WRIST - 0.05)
    hand_mat = "black" if s < 0 else "skin"
    B.ellipsoid("hand_" + nm, hp, (0.022, 0.036, 0.045), hand_mat, ["hand." + nm], seg=10, rings=7)
    B.ellipsoid("thumb_" + nm, hp + Vector((-s * 0.01, -0.03, 0.01)), (0.011, 0.016, 0.024), hand_mat, ["hand." + nm], seg=8, rings=5)
B.loft("glove_R", [(arm_pt(-1, 1.03), 0.034, 0.034), (arm_pt(-1, 0.95), 0.031, 0.031), (arm_pt(-1, WRIST - 0.005), 0.028, 0.028)], "black", ["forearm.R"], n=12)
B.loft("glovetrim_R", [(arm_pt(-1, 1.04), 0.035, 0.035), (arm_pt(-1, 1.025), 0.035, 0.035)], "white", ["forearm.R"], n=12)
for k, z in enumerate((1.27, 1.235)):
    B.loft("armband_L%d" % k, [(arm_pt(1, z + 0.01), 0.039, 0.039), (arm_pt(1, z - 0.01), 0.038, 0.038)], "black", ["upper_arm.L"], n=12)
B.loft("armband_R", [(arm_pt(-1, 1.26), 0.039, 0.039), (arm_pt(-1, 1.24), 0.038, 0.038)], "silver", ["upper_arm.R"], n=12)

# ------------------------------------------------------------- head: face (conformed decals), hair, side ponytail
B.ellipsoid("head", HEAD_C, HEAD_R, "skin", ["head"], seg=18, rings=12)
JAW_C = HEAD_C + Vector((0, -0.01, -0.05)); JAW_R = (0.055, 0.066, 0.058)
B.ellipsoid("jaw", JAW_C, JAW_R, "skin", ["head"], seg=14, rings=9)
FACE = [(HEAD_C, HEAD_R), (JAW_C, JAW_R)]
def face_y(x, z):
    best = 0.0
    for c, r in FACE:
        q = 1.0 - ((x - c.x) / r[0]) ** 2 - ((z - c.z) / r[2]) ** 2
        if q > 0:
            best = min(best, c.y - r[1] * math.sqrt(q))
    return best
def face_decal(name, pts2d, cx, cz, material, off):
    bm = bmesh.new()
    vs = [bm.verts.new((cx + u, face_y(cx + u, cz + v) - off, cz + v)) for u, v in pts2d]
    bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    B.obj(name, bm, material, ["head"], smooth=False)
EZ = HEAD_C.z - 0.006
for s in (1, -1):
    ex = s * 0.028
    def mir(pts):
        out = [(u * s, v) for u, v in pts]
        return out if s > 0 else list(reversed(out))
    # droopy, half-lidded eyes: outer corner lower, heavy straight upper lid -> calm, unsettling
    face_decal("eye_%d" % s, mir([(-0.016, 0.004), (-0.004, 0.009), (0.012, 0.007), (0.019, -0.003), (0.008, -0.008), (-0.01, -0.006)]), ex, EZ, "sclera", 0.0015)
    face_decal("iris_%d" % s, B.ellipse_pts(0.0085, 0.009, 12), ex - s * 0.001, EZ - 0.001, "iris", 0.0025)
    face_decal("pupil_%d" % s, B.ellipse_pts(0.004, 0.005, 8), ex - s * 0.001, EZ - 0.0015, "eye", 0.0033)
    face_decal("lid_%d" % s, mir([(-0.018, 0.005), (-0.004, 0.0105), (0.013, 0.0085), (0.023, -0.004), (0.026, -0.002), (0.016, 0.0125),
                                   (-0.004, 0.0145), (-0.019, 0.0085)]), ex, EZ, "eye", 0.0042)   # heavy lashes, flick down-out
    face_decal("lowlid_%d" % s, mir([(-0.01, -0.0075), (0.012, -0.009), (0.012, -0.0072), (-0.01, -0.006)]), ex, EZ, "eye", 0.003)
    face_decal("brow_%d" % s, mir([(-0.016, 0.0), (0.0, 0.003), (0.018, -0.001), (0.018, 0.003), (0.0, 0.0065), (-0.016, 0.0035)]), ex, EZ + 0.026, "hair", 0.002)
# faint closed-mouth smile (one corner a little higher)
face_decal("mouth", [(-0.012, 0.001), (-0.004, -0.002), (0.005, -0.0018), (0.013, 0.003), (0.006, 0.0002), (-0.004, -0.0003)], 0.0, HEAD_C.z - 0.066, "mouth", 0.0018)
face_decal("nose", [(-0.0025, 0.0), (0.0025, 0.0), (0.0, 0.007)], 0.0, HEAD_C.z - 0.038, "skin_dk", 0.002)
for s in (1, -1):
    B.ellipsoid("ear_%d" % s, HEAD_C + Vector((s * 0.072, 0.008, -0.008)), (0.011, 0.018, 0.026), "skin", ["head"], seg=8, rings=6)
# hair: cap, three bangs (split), side locks, back volume
B.ellipsoid("hair_cap", HEAD_C + Vector((0, 0.012, 0.02)), (0.081, 0.09, 0.104), "hair", ["head"], seg=18, rings=12)
B.ellipsoid("hair_back", HEAD_C + Vector((0, 0.035, -0.03)), (0.075, 0.06, 0.09), "hair", ["head"], seg=14, rings=9)
for k, (x, w, ln) in enumerate(((-0.04, 0.026, 0.07), (0.0, 0.03, 0.06), (0.042, 0.026, 0.072))):
    top = Vector((x * 0.8, -0.062, HEAD_C.z + 0.085))
    B.loft("bang_%d" % k, [(top, w, 0.014), (Vector((x, -0.084, HEAD_C.z + 0.04)), w * 0.9, 0.011),
                           (Vector((x * 1.1, -0.088, HEAD_C.z + 0.085 - ln)), w * 0.35, 0.006), (Vector((x * 1.15, -0.087, HEAD_C.z + 0.075 - ln - 0.012)), 0.002, 0.002)],
           "hair" if k != 1 else "hair_lt", ["head"], n=8)
for s in (1, -1):
    B.loft("sidelock_%d" % s, [(Vector((s * 0.068, -0.045, HEAD_C.z + 0.05)), 0.016, 0.02), (Vector((s * 0.078, -0.05, HEAD_C.z - 0.03)), 0.014, 0.018),
                               (Vector((s * 0.072, -0.045, HEAD_C.z - 0.11)), 0.004, 0.005)], "hair", ["head"], n=8)
# thick side ponytail: tied at her left (+X) below the ear, falls forward over the left shoulder onto the chest
PONY = [Vector((0.07, 0.03, HEAD_C.z - 0.05)), Vector((0.1, -0.005, HEAD_C.z - 0.13)), Vector((0.12, -0.05, HEAD_C.z - 0.24)),
        Vector((0.115, -0.07, HEAD_C.z - 0.36)), Vector((0.1, -0.07, HEAD_C.z - 0.47))]
B.loft("pony_tie", [(PONY[0] + Vector((-0.01, 0.005, 0.012)), 0.026, 0.026), (PONY[0] + Vector((0.004, 0.0, -0.008)), 0.026, 0.026)], "black", ["head"], n=10)
pr = [(PONY[0], 0.03, 0.03), (PONY[1], 0.046, 0.04), (PONY[1].lerp(PONY[2], 0.5), 0.05, 0.042), (PONY[2], 0.046, 0.038),
      (PONY[2].lerp(PONY[3], 0.5), 0.04, 0.032), (PONY[3], 0.032, 0.026), (PONY[3].lerp(PONY[4], 0.6), 0.018, 0.015), (PONY[4], 0.003, 0.003)]
B.loft("ponytail", pr, "hair", ["head", "pony_0.L", "pony_1.L", "pony_2.L", "pony_3.L"], n=12)

# ------------------------------------------------------------- staff-spear in the right hand
RH = arm_pt(-1, WRIST - 0.05)
S_LO = RH + Vector((0, -0.015, -0.42)); S_HI = RH + Vector((0, -0.015, 0.95))
B.loft("staff", [(S_LO, 0.011, 0.011), (S_HI, 0.011, 0.011)], "black", ["hand.R"], n=8)
B.loft("staff_cap", [(S_LO + Vector((0, 0, -0.02)), 0.004, 0.004), (S_LO + Vector((0, 0, 0.02)), 0.014, 0.014)], "silver", ["hand.R"], n=8)
B.loft("collar", [(S_HI + Vector((0, 0, -0.03)), 0.017, 0.017), (S_HI + Vector((0, 0, 0.01)), 0.017, 0.017)], "silver", ["hand.R"], n=8)
for s in (1, -1):   # two curved blades beside the tip
    pts = [S_HI + Vector((s * 0.01, 0, -0.02)), S_HI + Vector((s * 0.07, 0, 0.02)), S_HI + Vector((s * 0.1, 0, 0.1)), S_HI + Vector((s * 0.08, 0, 0.19))]
    B.loft("blade_%d" % s, [(pts[0], 0.012, 0.004), (pts[1], 0.02, 0.004), (pts[2], 0.014, 0.003), (pts[3], 0.002, 0.002)], "blade", ["hand.R"], n=6)
zig = [(-0.012, 0.0), (0.012, 0.0), (0.006, 0.08), (0.02, 0.08), (-0.004, 0.2), (0.0, 0.11), (-0.016, 0.11)]
B.prism("tip", zig, 0.012, "blade", ["hand.R"], xf=Matrix.Translation(S_HI + Vector((0, 0, 0.01))))
B.loft("ribbon", [(S_HI + Vector((0.012, 0, -0.06)), 0.01, 0.003), (S_HI + Vector((0.05, 0.03, -0.15)), 0.012, 0.003), (S_HI + Vector((0.06, 0.05, -0.27)), 0.004, 0.002)], "ribbon", ["hand.R"], n=6)
TIP = S_HI + Vector((0, 0, 0.2))

# ------------------------------------------------------------- armature
B.begin_rig("UbelRig")
B.bone("root", (0, 0, 0), (0, 0.2, 0))
B.bone("hips", (0, 0, 0.88), (0, 0, 1.02), "root")
B.bone("spine", (0, 0, 1.02), (0, 0, 1.19), "hips", connect=True)
B.bone("chest", (0, 0, 1.19), (0, 0, 1.43), "spine", connect=True)
B.bone("neck", (0, 0.006, 1.43), (0, 0.006, 1.52), "chest")
B.bone("head", (0, 0.006, 1.52), (0, 0.006, 1.7), "neck", connect=True)
for k in range(4):
    B.bone("pony_%d.L" % k, PONY[k], PONY[k + 1], "head" if k == 0 else "pony_%d.L" % (k - 1), connect=k > 0)
for s, nm in ((1, "L"), (-1, "R")):
    B.bone("shoulder." + nm, (s * 0.035, 0, 1.39), arm_pt(s, SH_Z) - Vector((s * 0.025, 0, 0)), "chest")
    B.bone("upper_arm." + nm, arm_pt(s, SH_Z), arm_pt(s, ELB), "shoulder." + nm)
    B.bone("forearm." + nm, arm_pt(s, ELB), arm_pt(s, WRIST), "upper_arm." + nm, connect=True)
    B.bone("hand." + nm, arm_pt(s, WRIST), arm_pt(s, WRIST - 0.1), "forearm." + nm, connect=True)
    B.bone("thigh." + nm, leg_pt(s, HIP_Z), leg_pt(s, KNEE_Z), "hips")
    B.bone("shin." + nm, leg_pt(s, KNEE_Z), leg_pt(s, ANK_Z), "thigh." + nm, connect=True)
    B.bone("foot." + nm, leg_pt(s, ANK_Z), leg_pt(s, ANK_Z) + Vector((0, -0.14, -0.06)), "shin." + nm, connect=True)
B.end_rig()
tris = B.skin_and_join("UbelMesh")
B.marker("BladeTip", "hand.R", TIP)

# ------------------------------------------------------------- animations (24 fps)
B.begin_anim()
HOLD = {"upper_arm.R": (-8, 0, -6), "forearm.R": (-28, 0, 0), "hand.R": (0, 0, 0)}   # staff upright at her side
def idle(br):
    p = {"chest": (br, 0, 0), "neck": (-br * 0.5, 0, 0), "head": (2, 0, -7 + br),   # head tilted: calm, unsettling
         "upper_arm.L": (0, 0, 4), "forearm.L": (-8, 0, 0)}
    p.update(HOLD)
    return p
B.action("idle_loop", [(1, idle(0)), (25, idle(2.0)), (49, idle(0))])
def run_pose(ph):
    s, c = math.sin(ph), math.cos(ph)
    return {"hips": (0, s * 6, 0), "spine": (12, -s * 4, 0), "chest": (6, -s * 8, 0), "head": (-10, 0, 0),
            "thigh.L": (-s * 46, 0, 0), "thigh.R": (s * 46, 0, 0),
            "shin.L": (max(0.0, c) * 70 + 10, 0, 0), "shin.R": (max(0.0, -c) * 70 + 10, 0, 0),
            "upper_arm.R": (30, 0, -10), "forearm.R": (-40, 0, 0), "hand.R": (-60, 0, 0),   # staff trailing low behind
            "upper_arm.L": (s * 30, 0, 8), "forearm.L": (-30, 0, 0)}
run = []
for k in range(5):
    ph = 2 * math.pi * k / 4
    run.append((1 + k * 4, run_pose(ph), {"hips": (0, abs(math.cos(ph)) * 0.03, 0)}))
B.action("run_loop", run)
# melee: horizontal staff-blade sweeps (wind-up, hit, follow-through) and an overhead downward finisher cut
def sweep(z_from, z_to):
    W = {"chest": (0, z_from * 0.4, 0), "upper_arm.R": (-80, 0, z_from), "forearm.R": (-30, 0, 0), "hand.R": (0, 0, -85)}
    H = {"chest": (0, z_to * 0.2, 0), "upper_arm.R": (-85, 0, 0), "forearm.R": (-5, 0, 0), "hand.R": (0, 0, -85)}
    F = {"chest": (0, z_to * 0.5, 0), "upper_arm.R": (-75, 0, z_to), "forearm.R": (-20, 0, 0), "hand.R": (0, 0, -85)}
    return [(1, HOLD), (4, W), (7, H), (10, F), (16, HOLD)]
B.action("swing_a", sweep(-55, 50))
B.action("swing_b", sweep(50, -55))
UPC = {"spine": (-10, 0, 0), "upper_arm.R": (-170, 0, -10), "forearm.R": (-30, 0, 0), "hand.R": (-20, 0, 0), "upper_arm.L": (-150, 0, 10), "forearm.L": (-40, 0, 0)}
DNC = {"spine": (25, 0, 0), "chest": (10, 0, 0), "upper_arm.R": (-50, 0, 0), "forearm.R": (-5, 0, 0), "hand.R": (-90, 0, 0), "upper_arm.L": (-45, 0, 0),
       "thigh.L": (-40, 0, 0), "shin.L": (40, 0, 0), "thigh.R": (20, 0, 0)}
B.action("finisher", [(1, HOLD), (5, UPC), (9, DNC, {"hips": (0, -0.06, 0)}), (14, DNC, {"hips": (0, -0.06, 0)}), (22, HOLD)])
# E: wide one-armed cutting slash, fully extended, body turning through
CW = {"chest": (0, 45, 0), "spine": (0, 20, 0), "upper_arm.R": (-85, 0, -70), "forearm.R": (-10, 0, 0), "hand.R": (0, 0, -85), "thigh.R": (-20, 0, 0)}
CF = {"chest": (0, -50, 0), "spine": (0, -20, 0), "upper_arm.R": (-88, 0, 80), "forearm.R": (0, 0, 0), "hand.R": (0, 0, -85), "thigh.L": (-30, 0, 0), "shin.L": (25, 0, 0)}
B.action("cut", [(1, HOLD), (5, CW), (8, CF), (14, CF), (20, HOLD)])
# Shift: crouch and spring (leap onto a head)
CROUCH = {"spine": (25, 0, 0), "thigh.L": (-60, 0, 0), "thigh.R": (-60, 0, 0), "shin.L": (90, 0, 0), "shin.R": (90, 0, 0), "upper_arm.L": (30, 0, 15)}
SPRING = {"spine": (-5, 0, 0), "thigh.L": (-30, 0, 0), "thigh.R": (10, 0, 0), "shin.L": (50, 0, 0), "shin.R": (30, 0, 0), "upper_arm.L": (-120, 0, 20),
          "upper_arm.R": (-60, 0, -10)}
B.action("leap", [(1, HOLD), (4, CROUCH, {"hips": (0, -0.16, 0)}), (8, SPRING, {"hips": (0, 0.05, 0)}), (14, SPRING)])
# mounted: crouched on a head, knees out, staff raised ready (loops while riding)
def ride(br):
    return {"hips": (0, br * 3, 0), "spine": (28, 0, 0), "chest": (6 + br, 0, 0), "head": (-28, 0, -6),
            "thigh.L": (-95, 0, -18), "thigh.R": (-95, 0, 18), "shin.L": (135, 0, 0), "shin.R": (135, 0, 0),
            "foot.L": (-20, 0, 0), "foot.R": (-20, 0, 0),
            "upper_arm.R": (-60, 0, -15), "forearm.R": (-50, 0, 0), "hand.R": (75, 0, 0), "upper_arm.L": (-40, 0, 25), "forearm.L": (-45, 0, 0)}
B.action("ride_loop", [(1, ride(0), {"hips": (0, -0.38, 0.0)}), (13, ride(1.5), {"hips": (0, -0.37, 0.0)}), (25, ride(0), {"hips": (0, -0.38, 0.0)})])
# Q: full spin cut (hips turn 360) with the staff out
SP = {"upper_arm.R": (-85, 0, 0), "forearm.R": (0, 0, 0), "hand.R": (0, 0, -85), "upper_arm.L": (-60, 0, -40), "spine": (10, 0, 0),
      "thigh.L": (-25, 0, 0), "shin.L": (30, 0, 0), "thigh.R": (-25, 0, 0), "shin.R": (30, 0, 0)}
spin = [(1, HOLD)]
for k in range(5):
    p = dict(SP); p["hips"] = (0, -90 * k, 0)
    spin.append((4 + k * 3, p, {"hips": (0, -0.05, 0)}))
spin.append((24, HOLD))
B.action("spin", spin, interp='LINEAR')
KNEEL = {"thigh.L": (-90, 0, 0), "thigh.R": (-20, 0, 0), "shin.L": (100, 0, 0), "shin.R": (110, 0, 0), "spine": (20, 0, 0), "head": (20, 0, 0),
         "upper_arm.R": (-20, 0, -20), "upper_arm.L": (-20, 0, 20)}
DOWN = {"hips": (80, 0, 0), "thigh.L": (-20, 0, 0), "thigh.R": (-10, 0, 0), "shin.L": (30, 0, 0), "upper_arm.R": (-150, 0, -30),
        "upper_arm.L": (-150, 0, 30), "head": (-30, 0, 0)}
B.action("death", [(1, idle(0)), (8, KNEEL, {"hips": (0, -0.3, 0)}), (18, DOWN, {"hips": (0, -0.72, 0.0)})])
B.end_anim()

B.export(os.path.join(OUT, "ubel.glb"))
SH = arg("--shots")
B.shots(SH, 0.86, 2.1, views=(("front", 0), ("side", 90), ("back", 180), ("three_quarter", 35)))
PO = arg("--poses")
if PO:
    B.shots(PO, 0.86, 2.1, views=())
    B.pose_shots(PO, [(a, f, y, "%s_%d_%d.png" % (a, f, y)) for a, f, y in
                      [("idle_loop", 1, 0), ("idle_loop", 1, 90), ("swing_a", 7, 0), ("swing_a", 7, 90), ("finisher", 9, 90), ("cut", 8, 0),
                       ("leap", 8, 90), ("ride_loop", 1, 0), ("ride_loop", 1, 90), ("spin", 10, 35), ("run_loop", 5, 90),
                       ("death", 18, 90)]], 0.86, 2.3)
