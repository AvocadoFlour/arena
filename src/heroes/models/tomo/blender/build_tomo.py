"""Tomo - procedural Blender build (Blender 4.2, headless):
    blender -b --python src/heroes/models/tomo/blender/build_tomo.py -- [--out DIR] [--shots DIR] [--poses DIR]
Lean damage hero (docs/concept/tomo_v1.png): tall, narrow silhouette; black beanie with a long dark ponytail coming
out under it at the back, short dark beard, black tee with a V neck, dark charcoal shorts, grey socks, red sneakers
with white soles, a closed silver laptop with a red sticker in the left hand. Packets fire from the right hand
(Muzzle marker). Faces Blender -Y, metres, ~1.95 m. Exports ../tomo.glb."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "common", "blender"))
from toonbuild import Build, arg
from mathutils import Vector, Matrix

B = Build("tomo", {
    "skin":    (0.92, 0.76, 0.63),
    "skin_dk": (0.78, 0.58, 0.46),
    "beard":   (0.22, 0.15, 0.10),
    "hair":    (0.25, 0.17, 0.11),
    "brow":    (0.18, 0.12, 0.08),
    "eye":     (0.08, 0.07, 0.07),
    "beanie":  (0.09, 0.09, 0.10),
    "beanie_rib": (0.14, 0.14, 0.15),
    "tee":     (0.10, 0.10, 0.11),
    "shorts":  (0.22, 0.22, 0.24),
    "sock":    (0.55, 0.55, 0.57),
    "shoe":    (0.86, 0.14, 0.16),
    "sole":    (0.97, 0.97, 0.96),
    "lace":    (0.97, 0.97, 0.96),
    "laptop":  (0.80, 0.82, 0.86),
    "laptop_dk": (0.45, 0.47, 0.52),
    "sticker": (0.90, 0.12, 0.14),
    "tie":     (0.86, 0.14, 0.16),
    "mouth":   (0.45, 0.22, 0.20),
    "vneck":   (0.92, 0.76, 0.63),
    "sticker_dot": (0.98, 0.96, 0.94),
})
OUT = arg("--out", os.path.dirname(HERE))

HEAD_C = Vector((0, 0.0, 1.79)); HEAD_R = (0.084, 0.095, 0.11)
SH_Z = 1.565; SH_X = 0.185
ELB = 1.27; WRIST = 1.0
HIP_X = 0.085; HIP_Z = 1.0; KNEE_Z = 0.55; ANK_Z = 0.1
ARM_OUT = 0.05

def arm_pt(s, z):
    t = (SH_Z - z) / (SH_Z - WRIST)
    return Vector((s * (SH_X + 0.02 + ARM_OUT * t), 0.0, z))
def leg_pt(s, z):
    t = (HIP_Z - z) / (HIP_Z - ANK_Z)
    return Vector((s * (HIP_X + 0.012 * t), -0.004 * t, z))

# ------------------------------------------------------------- torso: black tee (slim, slightly boxy)
TOR = [(1.635, 0.06, 0.055), (1.60, 0.15, 0.085), (1.56, 0.19, 0.1), (1.49, 0.185, 0.108), (1.40, 0.172, 0.104),
       (1.30, 0.158, 0.098), (1.20, 0.152, 0.094), (1.10, 0.152, 0.094), (1.02, 0.156, 0.096), (0.97, 0.158, 0.098)]
B.loft("tee", [((0, 0.0, z), a, b) for z, a, b in TOR], "tee", ["hips", "spine", "chest", "neck"], n=20)
B.loft("neck", [((0, 0.008, 1.60), 0.047, 0.045), ((0, 0.008, 1.71), 0.044, 0.043)], "skin", ["neck", "head"], n=12)
# V neck: skin triangle on the chest front, tee hem line
B.decal("vneck", [(-0.045, 0.0), (0.045, 0.0), (0.0, -0.06)], (0, -0.088, 1.605), "vneck", ["chest"], pitch=-0.12)
for s, nm in ((1, "L"), (-1, "R")):
    # short sleeves over the upper arm
    B.loft("sleeve_" + nm, [(arm_pt(s, SH_Z + 0.005) + Vector((-s * 0.01, 0, 0)), 0.068, 0.07), (arm_pt(s, 1.47), 0.066, 0.066),
                             (arm_pt(s, 1.38), 0.062, 0.062)], "tee", ["upper_arm." + nm, "chest"], n=14)
    B.ellipsoid("shoulder_" + nm, arm_pt(s, SH_Z - 0.02) + Vector((-s * 0.015, 0, 0)), (0.075, 0.072, 0.06), "tee", ["upper_arm." + nm, "chest"], seg=12, rings=8)

# ------------------------------------------------------------- shorts (dark charcoal, knee length, a bit loose)
B.loft("shorts_top", [((0, 0, 1.02), 0.155, 0.1), ((0, 0, 0.96), 0.17, 0.11), ((0, 0, 0.9), 0.172, 0.108)], "shorts", ["hips"], n=18)
B.loft("waist", [((0, 0, 1.005), 0.16, 0.103), ((0, 0, 0.985), 0.162, 0.104)], "tee", ["hips"], n=18)
for s, nm in ((1, "L"), (-1, "R")):
    zs = [0.95, 0.85, 0.75, 0.66, 0.62]
    rr = [0.098, 0.098, 0.094, 0.09, 0.09]
    B.loft("shorts_" + nm, [(leg_pt(s, z) + Vector((s * 0.01, 0, 0)), r, r * 1.05) for z, r in zip(zs, rr)], "shorts", ["hips", "thigh." + nm], n=14)
    # bare legs: thin, long
    lz = [0.64, KNEE_Z + 0.03, KNEE_Z, 0.42, 0.3, 0.2]
    lr = [0.056, 0.05, 0.048, 0.05, 0.042, 0.036]
    B.loft("leg_" + nm, [(leg_pt(s, z), r, r * 1.05) for z, r in zip(lz, lr)], "skin", ["thigh." + nm, "shin." + nm], n=12)
    B.loft("sock_" + nm, [(leg_pt(s, 0.215), 0.04, 0.042), (leg_pt(s, 0.15), 0.038, 0.04), (leg_pt(s, 0.09), 0.04, 0.044)], "sock", ["shin." + nm, "foot." + nm], n=12)
    fx = leg_pt(s, ANK_Z).x
    # red sneakers with white soles + laces (concept + photo)
    B.box("shoe_" + nm, (fx, -0.045, 0.06), (0.1, 0.25, 0.085), "shoe", ["foot." + nm], bevel=0.025)
    B.ellipsoid("toe_" + nm, (fx, -0.14, 0.05), (0.05, 0.065, 0.04), "shoe", ["foot." + nm], seg=10, rings=6)
    B.box("sole_" + nm, (fx, -0.05, 0.014), (0.112, 0.29, 0.03), "sole", ["foot." + nm], bevel=0.01)
    B.box("toecap_" + nm, (fx, -0.168, 0.03), (0.08, 0.04, 0.04), "sole", ["foot." + nm], bevel=0.012)
    for k in range(3):
        B.box("lace_%s_%d" % (nm, k), (fx, -0.11 + k * 0.035, 0.1 + k * 0.006), (0.06, 0.012, 0.01), "lace", ["foot." + nm])

# ------------------------------------------------------------- arms (slim), hands
for s, nm in ((1, "L"), (-1, "R")):
    az = [1.40, 1.33, ELB, 1.18, 1.09, WRIST]
    ar = [0.048, 0.045, 0.04, 0.042, 0.037, 0.031]
    B.loft("arm_" + nm, [(arm_pt(s, z), r, r) for z, r in zip(az, ar)], "skin", ["upper_arm." + nm, "forearm." + nm], n=12)
    hp = arm_pt(s, WRIST - 0.055)
    B.ellipsoid("hand_" + nm, hp, (0.026, 0.045, 0.055), "skin", ["hand." + nm], seg=10, rings=7)
    B.ellipsoid("thumb_" + nm, hp + Vector((-s * 0.012, -0.04, 0.012)), (0.014, 0.02, 0.03), "skin", ["hand." + nm], seg=8, rings=5)
MUZZLE = arm_pt(-1, WRIST - 0.12)

# ------------------------------------------------------------- laptop (closed, held by its edge in the left hand)
LH = arm_pt(1, WRIST - 0.06)
LAP_C = LH + Vector((0.032, -0.02, -0.11))
B.box("laptop", LAP_C, (0.026, 0.25, 0.34), "laptop", ["hand.L"], bevel=0.008)
B.box("laptop_seam", LAP_C + Vector((-0.0005, 0, 0)), (0.008, 0.256, 0.346), "laptop_dk", ["hand.L"])
B.decal("sticker", B.ellipse_pts(0.03, 0.03, 12), LAP_C + Vector((0.0145, 0.01, 0.02)), "sticker", ["hand.L"], yaw=math.pi / 2)
B.decal("sticker_in", B.ellipse_pts(0.013, 0.013, 10), LAP_C + Vector((0.0152, 0.01, 0.02)), "sticker_dot", ["hand.L"], yaw=math.pi / 2)

# ------------------------------------------------------------- head: beard, eyes, brows, beanie, ponytail
B.ellipsoid("head", HEAD_C, HEAD_R, "skin", ["head"], seg=18, rings=12)
B.ellipsoid("jaw", HEAD_C + Vector((0, -0.012, -0.055)), (0.074, 0.08, 0.06), "skin", ["head"], seg=14, rings=9)
# short dark beard: shell over the jaw + chin, moustache
B.ellipsoid("beard", HEAD_C + Vector((0, -0.03, -0.066)), (0.075, 0.07, 0.05), "beard", ["head"], seg=16, rings=9)
B.ellipsoid("chin", HEAD_C + Vector((0, -0.068, -0.095)), (0.036, 0.03, 0.03), "beard", ["head"], seg=10, rings=6)
FY = HEAD_C.y - HEAD_R[1]
B.box("moustache", (0, FY + 0.004, HEAD_C.z - 0.045), (0.06, 0.016, 0.014), "beard", ["head"], bevel=0.005)
B.decal("mouth", [(-0.02, 0.0), (0.02, 0.0), (0.012, -0.008), (-0.012, -0.008)], (0, FY - 0.012, HEAD_C.z - 0.062), "mouth", ["head"])
B.ellipsoid("nose", (0, FY - 0.004, HEAD_C.z - 0.012), (0.014, 0.018, 0.022), "skin_dk", ["head"], seg=8, rings=6)
for s in (1, -1):
    B.ellipsoid("eye_%d" % s, (s * 0.033, FY + 0.012, HEAD_C.z + 0.018), (0.011, 0.006, 0.012), "eye", ["head"], seg=8, rings=6)
    B.box("brow_%d" % s, (s * 0.035, FY + 0.01, HEAD_C.z + 0.043), (0.034, 0.01, 0.009), "brow", ["head"], rot=(0, s * -6, 0))
    B.ellipsoid("ear_%d" % s, HEAD_C + Vector((s * 0.085, 0.01, -0.005)), (0.014, 0.022, 0.032), "skin", ["head"], seg=8, rings=6)
# hair visible under the beanie: sides (sideburns into the beard) and the back
B.ellipsoid("hair_back", HEAD_C + Vector((0, 0.022, 0.012)), (0.088, 0.09, 0.098), "hair", ["head"], seg=16, rings=10)
for s in (1, -1):
    B.box("sideburn_%d" % s, HEAD_C + Vector((s * 0.081, -0.02, -0.01)), (0.012, 0.03, 0.06), "beard", ["head"], bevel=0.004)
# black beanie: tall rounded crown + ribbed cuff
B.ellipsoid("beanie", HEAD_C + Vector((0, 0.008, 0.055)), (0.094, 0.103, 0.108), "beanie", ["head"], seg=18, rings=11)
B.ellipsoid("beanie_top", HEAD_C + Vector((0, 0.014, 0.115)), (0.075, 0.08, 0.07), "beanie", ["head"], seg=14, rings=8)
B.loft("beanie_cuff", [((0, 0.006, HEAD_C.z + 0.028), 0.097, 0.106), ((0, 0.006, HEAD_C.z + 0.058), 0.099, 0.108),
                       ((0, 0.006, HEAD_C.z + 0.072), 0.097, 0.106)], "beanie_rib", ["head"], n=20, cap0=False, cap1=False)
# LONG PONYTAIL coming out under the beanie at the back of the head, hair tie, falls down the back
PONY = [Vector((0, 0.1, HEAD_C.z + 0.0)), Vector((0, 0.135, HEAD_C.z - 0.09)), Vector((0, 0.145, HEAD_C.z - 0.22)),
        Vector((0, 0.14, HEAD_C.z - 0.36)), Vector((0, 0.13, HEAD_C.z - 0.5))]
B.ellipsoid("pony_root", PONY[0] + Vector((0, -0.01, 0.0)), (0.042, 0.03, 0.04), "hair", ["head"], seg=10, rings=7)
B.loft("tie", [(PONY[0] + Vector((0, 0.012, -0.012)), 0.03, 0.026), (PONY[0] + Vector((0, 0.02, -0.03)), 0.03, 0.026)], "tie", ["head", "pony_0.C"], n=10)
pr = [(PONY[0] + Vector((0, 0.022, -0.035)), 0.026, 0.022), (PONY[1], 0.036, 0.03), (PONY[1].lerp(PONY[2], 0.5), 0.038, 0.03),
      (PONY[2], 0.034, 0.027), (PONY[2].lerp(PONY[3], 0.5), 0.029, 0.023), (PONY[3], 0.024, 0.019),
      (PONY[3].lerp(PONY[4], 0.6), 0.015, 0.012), (PONY[4] + Vector((0, -0.005, -0.02)), 0.003, 0.003)]
B.loft("ponytail", pr, "hair", ["head", "pony_0.C", "pony_1.C", "pony_2.C", "pony_3.C"], n=12)

# ------------------------------------------------------------- armature
B.begin_rig("TomoRig")
B.bone("root", (0, 0, 0), (0, 0.2, 0))
B.bone("hips", (0, 0, 1.0), (0, 0, 1.15), "root")
B.bone("spine", (0, 0, 1.15), (0, 0, 1.34), "hips", connect=True)
B.bone("chest", (0, 0, 1.34), (0, 0, 1.6), "spine", connect=True)
B.bone("neck", (0, 0.008, 1.6), (0, 0.008, 1.71), "chest")
B.bone("head", (0, 0.008, 1.71), (0, 0.008, 1.93), "neck", connect=True)
for k in range(4):
    B.bone("pony_%d.C" % k, PONY[k], PONY[k + 1], "head" if k == 0 else "pony_%d.C" % (k - 1), connect=k > 0)
for s, nm in ((1, "L"), (-1, "R")):
    B.bone("shoulder." + nm, (s * 0.04, 0, 1.56), arm_pt(s, SH_Z) - Vector((s * 0.03, 0, 0)), "chest")
    B.bone("upper_arm." + nm, arm_pt(s, SH_Z), arm_pt(s, ELB), "shoulder." + nm)
    B.bone("forearm." + nm, arm_pt(s, ELB), arm_pt(s, WRIST), "upper_arm." + nm, connect=True)
    B.bone("hand." + nm, arm_pt(s, WRIST), arm_pt(s, WRIST - 0.12), "forearm." + nm, connect=True)
    B.bone("thigh." + nm, leg_pt(s, HIP_Z), leg_pt(s, KNEE_Z), "hips")
    B.bone("shin." + nm, leg_pt(s, KNEE_Z), leg_pt(s, ANK_Z), "thigh." + nm, connect=True)
    B.bone("foot." + nm, leg_pt(s, ANK_Z), leg_pt(s, ANK_Z) + Vector((0, -0.16, -0.07)), "shin." + nm, connect=True)
B.end_rig()
tris = B.skin_and_join("TomoMesh")
B.marker("Muzzle", "hand.R", MUZZLE)

# ------------------------------------------------------------- animations (24 fps)
B.begin_anim()
LAP = {"upper_arm.L": (0, 0, 6), "forearm.L": (-12, 0, 0), "hand.L": (0, 0, 0)}   # laptop hangs at the side
def idle(br):
    p = {"chest": (br, 0, 0), "neck": (-br * 0.5, 0, 0), "upper_arm.R": (0, 0, -5), "forearm.R": (-10, 0, 0), "head": (0, br * 0.8, 0)}
    p.update(LAP)
    return p
B.action("idle_loop", [(1, idle(0)), (25, idle(2.0)), (49, idle(0))])

def run_pose(ph):
    s, c = math.sin(ph), math.cos(ph)
    return {"hips": (0, s * 6, 0), "spine": (8, -s * 4, 0), "chest": (5, -s * 8, 0),
            "thigh.L": (-s * 42, 0, 0), "thigh.R": (s * 42, 0, 0),
            "shin.L": (max(0.0, c) * 65 + 10, 0, 0), "shin.R": (max(0.0, -c) * 65 + 10, 0, 0),
            "upper_arm.R": (-s * 38, 0, -6), "forearm.R": (-50, 0, 0),
            "upper_arm.L": (s * 22, 0, 8), "forearm.L": (-25, 0, 0)}
run = []
for k in range(5):
    ph = 2 * math.pi * k / 4
    run.append((1 + k * 5, run_pose(ph), {"hips": (0, abs(math.cos(ph)) * 0.03, 0)}))
B.action("run_loop", run)

# aim: right arm straight out at the target, palm forward (packets leave the hand)
AIM = {"upper_arm.R": (-88, 0, 4), "forearm.R": (-4, 0, 0), "hand.R": (-12, 0, 0), "shoulder.R": (0, 0, 0)}
B.action("aim_loop", [(1, AIM), (11, AIM)])
KICK = {"upper_arm.R": (-96, 0, 4), "forearm.R": (-14, 0, 0), "hand.R": (-30, 0, 0)}
B.action("shoot", [(1, AIM), (2, KICK), (4, AIM), (5, KICK), (7, AIM), (8, KICK), (11, AIM)])
# Hotfix blink: low forward lean, arms trailing
BLINK = {"spine": (28, 0, 0), "chest": (10, 0, 0), "head": (-22, 0, 0), "upper_arm.R": (40, 0, -25), "upper_arm.L": (35, 0, 20),
         "forearm.R": (-20, 0, 0), "forearm.L": (-20, 0, 0), "thigh.L": (-55, 0, 0), "thigh.R": (28, 0, 0), "shin.R": (45, 0, 0), "shin.L": (35, 0, 0)}
B.action("blink", [(1, idle(0)), (3, BLINK), (8, BLINK), (14, idle(0))])
# Breakpoint throw: overhand right-arm throw of the marker
WIND = {"chest": (-6, 25, 0), "spine": (0, 10, 0), "upper_arm.R": (-150, 0, -20), "forearm.R": (-70, 0, 0), "upper_arm.L": (-40, 0, 10)}
REL = {"chest": (12, -20, 0), "spine": (6, -8, 0), "upper_arm.R": (-80, 0, 5), "forearm.R": (-5, 0, 0), "hand.R": (-25, 0, 0),
       "upper_arm.L": (10, 0, 10), "thigh.L": (-25, 0, 0), "shin.L": (20, 0, 0)}
B.action("throw", [(1, idle(0)), (5, WIND), (8, REL), (13, REL), (20, idle(0))])
# Force Push ult: wide stance, both palms shove forward
GATHER = {"chest": (-8, 0, 0), "upper_arm.R": (-40, 0, -30), "upper_arm.L": (-40, 0, 30), "forearm.R": (-110, 0, 0), "forearm.L": (-110, 0, 0),
          "thigh.L": (-15, 0, 0), "thigh.R": (10, 0, 0), "shin.L": (20, 0, 0)}
SHOVE = {"spine": (14, 0, 0), "chest": (8, 0, 0), "upper_arm.R": (-88, 0, 10), "upper_arm.L": (-88, 0, -10), "forearm.R": (-2, 0, 0),
         "forearm.L": (-2, 0, 0), "hand.R": (-60, 0, 0), "hand.L": (-60, 0, 0), "thigh.L": (-40, 0, 0), "shin.L": (40, 0, 0), "thigh.R": (25, 0, 0)}
B.action("push", [(1, idle(0)), (8, GATHER), (12, SHOVE), (24, SHOVE), (32, idle(0))])
# death: knees buckle, falls forward
KNEEL = {"thigh.L": (-90, 0, 0), "thigh.R": (-20, 0, 0), "shin.L": (100, 0, 0), "shin.R": (110, 0, 0), "spine": (20, 0, 0), "head": (20, 0, 0),
         "upper_arm.R": (-20, 0, -20), "upper_arm.L": (-20, 0, 20)}
DOWN = {"hips": (80, 0, 0), "thigh.L": (-20, 0, 0), "thigh.R": (-10, 0, 0), "shin.L": (30, 0, 0), "upper_arm.R": (-150, 0, -30),
        "upper_arm.L": (-150, 0, 30), "head": (-30, 0, 0)}
B.action("death", [(1, idle(0)), (8, KNEEL, {"hips": (0, -0.36, 0)}), (18, DOWN, {"hips": (0, -0.82, 0.0)})])
B.end_anim()

B.export(os.path.join(OUT, "tomo.glb"))
SH = arg("--shots")
B.shots(SH, 0.98, 2.4, views=(("front", 0), ("side", 90), ("back", 180), ("three_quarter", 35)))
PO = arg("--poses")
if PO:
    B.shots(PO, 0.98, 2.4, views=())
    B.pose_shots(PO, [(a, f, y, "%s_%d_%d.png" % (a, f, y)) for a, f, y in
                      [("idle_loop", 1, 0), ("idle_loop", 1, 90), ("aim_loop", 1, 0), ("aim_loop", 1, 90), ("shoot", 2, 90),
                       ("blink", 5, 90), ("throw", 5, 90), ("throw", 9, 90), ("push", 14, 0), ("push", 14, 90),
                       ("death", 18, 90), ("run_loop", 6, 90)]], 0.98, 2.6)
