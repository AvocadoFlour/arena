"""Nido - procedural Blender build (Blender 4.2, headless):
    blender -b --python src/heroes/models/nidjo/blender/build_nidjo.py -- [--out DIR] [--shots DIR] [--poses DIR]
Sturdy bruiser after docs/concept/nidjo_v3.png (ui branch) + a plain black baseball cap (no logo): short hair,
light goatee, open green Harrington jacket with red tartan lining and wide lapels, navy/white striped tee, black
belt bag, black trousers, black/white sneakers, a heavy network-switch hammer in the right hand.
Faces Blender -Y, metres, ~1.8 m. Rig/anim layout follows build_the_best.py. Exports ../nidjo.glb."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "common", "blender"))
from toonbuild import Build, arg
from mathutils import Vector, Matrix

B = Build("nj", {
    "skin":    (0.94, 0.80, 0.68),
    "hair":    (0.48, 0.36, 0.24),
    "goatee":  (0.62, 0.48, 0.32),
    "cap":     (0.07, 0.07, 0.08),
    "green":   (0.12, 0.42, 0.26),
    "green_dk":(0.08, 0.30, 0.18),
    "red":     (0.75, 0.12, 0.14),
    "plaid":   (0.95, 0.92, 0.86),
    "navy":    (0.11, 0.14, 0.28),
    "white":   (0.96, 0.96, 0.95),
    "black":   (0.07, 0.07, 0.08),
    "bag":     (0.12, 0.12, 0.13),
    "sole":    (0.95, 0.95, 0.95),
    "metal":   (0.42, 0.45, 0.50),
    "metal_dk":(0.22, 0.24, 0.28),
    "led":     (0.35, 1.0, 0.45),
    "grip":    (0.14, 0.14, 0.15),
    "eye":     (0.05, 0.05, 0.06),
})
OUT = arg("--out", os.path.dirname(HERE))

HEAD_C = Vector((0, 0.0, 1.645)); HEAD_R = (0.092, 0.1, 0.112)
SH_Z = 1.43; SH_X = 0.22
ELB = 1.15; WRIST = 0.9
HIP_X = 0.11; HIP_Z = 0.92; KNEE_Z = 0.5; ANK_Z = 0.1
ARM_OUT = 0.1

def arm_pt(s, z):
    t = (SH_Z - z) / (SH_Z - WRIST)
    return Vector((s * (SH_X + 0.05 + ARM_OUT * t), 0.0, z))
def leg_pt(s, z):
    t = (HIP_Z - z) / (HIP_Z - ANK_Z)
    return Vector((s * (HIP_X + 0.01 * t), 0.0, z))

# ------------------------------------------------------------- torso: navy/white striped tee (broad, boxy)
TOR = [(1.50, 0.08, 0.07), (1.46, 0.2, 0.13), (1.40, 0.23, 0.15), (1.30, 0.225, 0.155), (1.18, 0.215, 0.155),
       (1.06, 0.205, 0.15), (0.96, 0.2, 0.145), (0.9, 0.195, 0.14)]
def tor_r(z):
    for (z0, a0, b0), (z1, a1, b1) in zip(TOR, TOR[1:]):
        if z1 <= z <= z0:
            t = (z0 - z) / (z0 - z1)
            return a0 + (a1 - a0) * t, b0 + (b1 - b0) * t
    return TOR[-1][1], TOR[-1][2]
B.loft("torso", [((0, 0.0, z), a, b) for z, a, b in TOR], "white", ["hips", "spine", "chest", "neck"], n=18)
z = 1.40
k = 0
while z > 0.98:   # navy stripe bands, slightly proud of the tee
    a, b = tor_r(z)
    B.loft("stripe_%d" % k, [((0, 0, z), a + 0.004, b + 0.004), ((0, 0, z - 0.022), a + 0.004, b + 0.004)], "navy",
           ["chest", "spine"] if z > 1.2 else ["spine", "hips"], n=18, cap0=False, cap1=False)
    z -= 0.05; k += 1
B.loft("neck", [((0, 0.0, 1.47), 0.06, 0.058), ((0, 0.0, 1.56), 0.056, 0.054)], "skin", ["neck", "head"], n=12)
B.loft("tee_collar", [((0, 0.0, 1.475), 0.07, 0.066), ((0, 0.0, 1.465), 0.078, 0.072)], "navy", ["chest"], n=14, cap0=False, cap1=False)

# ------------------------------------------------------------- open green jacket (back + sides), red tartan lining
JK = [(1.46, 0.235, 0.165), (1.40, 0.255, 0.18), (1.25, 0.25, 0.18), (1.10, 0.245, 0.175), (0.95, 0.24, 0.17), (0.86, 0.235, 0.165)]
# open shell: loft rings on a vertical path put -Y (front) at 90 deg, so the arc 130..410 leaves an 80 deg front gap
B.loft("jacket", [((0, 0.0, z), a, b) for z, a, b in JK], "green", ["chest", "spine", "hips"], n=20, arc=(130, 410))
B.loft("jacket_in", [((0, 0.0, z), a - 0.012, b - 0.012) for z, a, b in JK], "red", ["chest", "spine", "hips"], n=20, arc=(410, 130))
B.loft("jacket_hem", [((0, 0, 0.885), 0.243, 0.172), ((0, 0, 0.85), 0.24, 0.17)], "green_dk", ["hips"], n=20, arc=(130, 410))
for s in (1, -1):
    # wide turned-back facings on both front edges: red tartan with whitish crossing lines
    fx = s * 0.17
    B.box("facing_%d" % s, (fx, -0.155, 1.13), (0.1, 0.02, 0.56), "red", ["chest", "spine"], rot=(0, 0, s * 28))
    for zz in (1.35, 1.25, 1.15, 1.05, 0.95, 0.88):
        B.box("plaid_h_%d_%d" % (s, int(zz * 100)), (fx, -0.167, zz), (0.1, 0.006, 0.008), "plaid", ["chest", "spine"], rot=(0, 0, s * 28))
    for dx in (-0.03, 0.0, 0.03):
        B.box("plaid_v_%d_%d" % (s, int(dx * 100)), (fx + s * dx * 0.88, -0.167 - s * dx * 0.47 * s, 1.13), (0.007, 0.006, 0.55), "plaid", ["chest", "spine"], rot=(0, 0, s * 28))
    # wide lapel (red, turned back) at the top of each front edge
    lap = [(0.0, 0.0), (0.13, 0.04), (0.1, -0.14), (0.02, -0.2)]
    pts = [(s * x, zz) for x, zz in lap]
    if s < 0:
        pts = list(reversed(pts))
    B.prism("lapel_%d" % s, pts, 0.014, "red", ["chest"], xf=Matrix.Translation((s * 0.075, -0.16, 1.47)) @ Matrix.Rotation(math.radians(-12), 4, 'X'))
    B.box("collar_%d" % s, (s * 0.12, -0.02, 1.48), (0.13, 0.17, 0.05), "green", ["chest", "neck"], rot=(0, 0, s * 20))

# ------------------------------------------------------------- belt bag (black, slung across the hips)
B.loft("bag_strap", [((math.cos(math.radians(a)) * 0.215, math.sin(math.radians(a)) * 0.16, 0.985 + 0.03 * math.cos(math.radians(a))), 0.012, 0.012)
                     for a in range(0, 361, 20)], "bag", ["hips"], n=6, cap0=False, cap1=False)
B.ellipsoid("bag", (-0.03, -0.17, 0.98), (0.12, 0.05, 0.055), "bag", ["hips"], seg=14, rings=8)
B.box("bag_zip", (-0.03, -0.215, 0.995), (0.18, 0.006, 0.006), "metal", ["hips"])

# ------------------------------------------------------------- legs: black trousers, black/white sneakers
B.loft("trousers_top", [((0, 0, 0.95), 0.2, 0.14), ((0, 0, 0.86), 0.21, 0.14)], "black", ["hips"], n=18)
for s, nm in ((1, "L"), (-1, "R")):
    zs = [0.92, 0.8, 0.66, 0.52, 0.38, 0.22, 0.12]
    rr = [0.105, 0.1, 0.092, 0.085, 0.08, 0.075, 0.072]
    B.loft("leg_" + nm, [(leg_pt(s, z), r, r * 1.05) for z, r in zip(zs, rr)], "black", ["thigh." + nm, "shin." + nm], n=14)
    fx = s * (HIP_X + 0.01)
    B.ellipsoid("shoe_" + nm, (fx, -0.05, 0.065), (0.065, 0.14, 0.055), "black", ["foot." + nm], seg=12, rings=7)
    B.box("sole_" + nm, (fx, -0.05, 0.018), (0.13, 0.3, 0.035), "sole", ["foot." + nm], bevel=0.01)

# ------------------------------------------------------------- arms: green sleeves, ribbed cuffs, hands
for s, nm in ((1, "L"), (-1, "R")):
    az = [SH_Z + 0.02, 1.34, 1.24, ELB, 1.06, 0.96, WRIST + 0.03]
    ar = [0.085, 0.08, 0.076, 0.07, 0.068, 0.064, 0.06]
    B.loft("sleeve_" + nm, [(arm_pt(s, z), r, r) for z, r in zip(az, ar)], "green", ["upper_arm." + nm, "forearm." + nm], n=12)
    B.ellipsoid("shoulder_" + nm, arm_pt(s, SH_Z - 0.03) + Vector((-s * 0.01, 0, 0)), (0.095, 0.09, 0.085), "green", ["upper_arm." + nm, "chest"], seg=12, rings=8)
    B.loft("cuff_" + nm, [(arm_pt(s, WRIST + 0.035), 0.058, 0.058), (arm_pt(s, WRIST - 0.0), 0.054, 0.054)], "green_dk", ["forearm." + nm], n=12)
    B.ellipsoid("hand_" + nm, arm_pt(s, WRIST - 0.055), (0.052, 0.056, 0.064), "skin", ["hand." + nm], seg=10, rings=7)

# ------------------------------------------------------------- head: short hair, light goatee, black cap
B.ellipsoid("head", HEAD_C, HEAD_R, "skin", ["head"], seg=18, rings=12)
B.ellipsoid("jaw", HEAD_C + Vector((0, -0.012, -0.055)), (0.086, 0.088, 0.062), "skin", ["head"], seg=14, rings=9)
for s in (1, -1):
    B.ellipsoid("ear_%d" % s, HEAD_C + Vector((s * 0.092, 0.01, -0.005)), (0.015, 0.024, 0.032), "skin", ["head"], seg=8, rings=6)
FY = HEAD_C.y - HEAD_R[1]
for s in (1, -1):   # eyes + brows
    B.ellipsoid("eye_%d" % s, (s * 0.034, FY + 0.012, HEAD_C.z + 0.0), (0.011, 0.006, 0.012), "eye", ["head"], seg=8, rings=5)
    B.box("brow_%d" % s, (s * 0.036, FY + 0.012, HEAD_C.z + 0.028), (0.04, 0.008, 0.009), "hair", ["head"], rot=(0, 0, -s * 6))
B.ellipsoid("nose", (0, FY - 0.004, HEAD_C.z - 0.02), (0.016, 0.018, 0.024), "skin", ["head"], seg=8, rings=6)
B.box("moustache", (0, FY + 0.006, HEAD_C.z - 0.05), (0.05, 0.008, 0.008), "goatee", ["head"])
B.box("mouth", (0, FY + 0.012, HEAD_C.z - 0.066), (0.032, 0.006, 0.005), "eye", ["head"])
B.ellipsoid("goatee", (0, FY + 0.022, HEAD_C.z - 0.1), (0.026, 0.016, 0.026), "goatee", ["head"], seg=10, rings=6)
# short hair: visible at the sides/back under the cap
B.ellipsoid("hair", HEAD_C + Vector((0, 0.012, 0.012)), (0.097, 0.1, 0.1), "hair", ["head"], seg=16, rings=10)
# plain black baseball cap (no logo): crown dome + band + forward brim
B.ellipsoid("cap_crown", HEAD_C + Vector((0, 0.005, 0.05)), (0.102, 0.108, 0.085), "cap", ["head"], seg=18, rings=10)
B.loft("cap_band", [(HEAD_C + Vector((0, 0.005, 0.04)), 0.103, 0.109), (HEAD_C + Vector((0, 0.005, 0.02)), 0.104, 0.11)], "cap", ["head"], n=18, cap0=False, cap1=False)
brim = [(-0.085, 0.0), (-0.06, -0.075), (0.0, -0.1), (0.06, -0.075), (0.085, 0.0)]
B.prism("cap_brim", brim, 0.012, "cap", ["head"],
        xf=Matrix.Translation(HEAD_C + Vector((0, -0.075, 0.03))) @ Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1))) @ Matrix.Rotation(math.radians(-8), 4, 'X'))
B.ellipsoid("cap_button", HEAD_C + Vector((0, 0.005, 0.135)), (0.012, 0.012, 0.008), "cap", ["head"], seg=8, rings=5)

# ------------------------------------------------------------- Ping Hammer: network switch on a handle (right hand)
HAND = arm_pt(-1, WRIST - 0.055)
L = 0.75
HEAD = HAND + Vector((0, -L, 0))
B.loft("handle", [(HAND + Vector((0, 0.1, 0)), 0.02, 0.02), (HEAD + Vector((0, 0.03, 0)), 0.022, 0.022)], "grip", ["hand.R"], n=8)
B.box("hammer_head", HEAD, (0.3, 0.12, 0.13), "metal", ["hand.R"], bevel=0.012)
B.box("hammer_face_l", HEAD + Vector((0.16, 0, 0)), (0.03, 0.13, 0.14), "metal_dk", ["hand.R"], bevel=0.006)
B.box("hammer_face_r", HEAD + Vector((-0.16, 0, 0)), (0.03, 0.13, 0.14), "metal_dk", ["hand.R"], bevel=0.006)
for i in range(6):   # switch ports + status LEDs on the front of the head
    x = -0.1 + i * 0.04
    B.box("port_%d" % i, HEAD + Vector((x, -0.062, -0.015)), (0.026, 0.006, 0.02), "metal_dk", ["hand.R"])
    B.box("led_%d" % i, HEAD + Vector((x, -0.062, 0.03)), (0.01, 0.006, 0.01), "led", ["hand.R"])
HAMMER_TIP = HEAD

# ------------------------------------------------------------- armature (same layout as The Best)
B.begin_rig("NidjoRig")
B.bone("root", (0, 0, 0), (0, 0.2, 0))
B.bone("hips", (0, 0, 0.92), (0, 0, 1.06), "root")
B.bone("spine", (0, 0, 1.06), (0, 0, 1.24), "hips", connect=True)
B.bone("chest", (0, 0, 1.24), (0, 0, 1.46), "spine", connect=True)
B.bone("neck", (0, 0, 1.46), (0, 0, 1.56), "chest")
B.bone("head", (0, 0, 1.56), (0, 0, 1.78), "neck", connect=True)
for s, nm in ((1, "L"), (-1, "R")):
    B.bone("shoulder." + nm, (s * 0.05, 0, 1.43), arm_pt(s, SH_Z) - Vector((s * 0.03, 0, 0)), "chest")
    B.bone("upper_arm." + nm, arm_pt(s, SH_Z), arm_pt(s, ELB), "shoulder." + nm)
    B.bone("forearm." + nm, arm_pt(s, ELB), arm_pt(s, WRIST), "upper_arm." + nm, connect=True)
    B.bone("hand." + nm, arm_pt(s, WRIST), arm_pt(s, WRIST - 0.12), "forearm." + nm, connect=True)
    B.bone("thigh." + nm, leg_pt(s, HIP_Z), leg_pt(s, KNEE_Z), "hips")
    B.bone("shin." + nm, leg_pt(s, KNEE_Z), leg_pt(s, ANK_Z), "thigh." + nm, connect=True)
    B.bone("foot." + nm, leg_pt(s, ANK_Z), leg_pt(s, ANK_Z) + Vector((0, -0.16, -0.07)), "shin." + nm, connect=True)
B.end_rig()
tris = B.skin_and_join("NidjoMesh")
B.marker("HammerHead", "hand.R", HAMMER_TIP)

# ------------------------------------------------------------- animations (24 fps)
B.begin_anim()
CARRY = {"upper_arm.R": (-25, 0, -72), "forearm.R": (-118, 0, 0), "hand.R": (0, 0, -70)}   # hammer on the shoulder
def idle(br):
    p = {"chest": (br, 0, 0), "neck": (-br * 0.5, 0, 0), "upper_arm.L": (0, 0, 12), "forearm.L": (-20, 0, 0)}
    p.update(CARRY)
    return p
B.action("idle_loop", [(1, idle(0)), (25, idle(2.0)), (49, idle(0))])

def run_pose(ph):
    s, c = math.sin(ph), math.cos(ph)
    p = {"hips": (0, s * 6, 0), "spine": (8, -s * 4, 0), "chest": (5, -s * 8, 0),
         "thigh.L": (-s * 38, 0, 0), "thigh.R": (s * 38, 0, 0),
         "shin.L": (max(0.0, c) * 55 + 10, 0, 0), "shin.R": (max(0.0, -c) * 55 + 10, 0, 0),
         "upper_arm.L": (s * 38, 0, 8), "forearm.L": (-45, 0, 0)}
    p.update(CARRY)
    p["upper_arm.R"] = (-25 + s * 6, 0, -72)
    return p
run = []
for k in range(5):
    ph = 2 * math.pi * k / 4
    run.append((1 + k * 5, run_pose(ph), {"hips": (0, abs(math.cos(ph)) * 0.025, 0)}))
B.action("run_loop", run)

# hammer swings (upper body): A = forehand, B = backhand, finisher = overhead slam (every 3rd hit, knockback pulse)
WIND_A = {"chest": (0, -35, 0), "spine": (0, -10, 0), "upper_arm.R": (-95, 60, 0), "forearm.R": (-30, 0, 0), "hand.R": (70, 0, 0)}
HIT_A = {"chest": (8, 40, 0), "spine": (4, 12, 0), "upper_arm.R": (-80, -65, 0), "forearm.R": (-5, 0, 0), "hand.R": (70, 0, 0)}
B.action("swing_a", [(1, CARRY), (5, WIND_A), (8, HIT_A), (12, HIT_A), (18, CARRY)])
WIND_B = {"chest": (0, 35, 0), "spine": (0, 10, 0), "upper_arm.R": (-90, -70, 0), "forearm.R": (-40, 0, 0), "hand.R": (70, 0, 0)}
HIT_B = {"chest": (8, -40, 0), "spine": (4, -12, 0), "upper_arm.R": (-85, 55, 0), "forearm.R": (-5, 0, 0), "hand.R": (70, 0, 0)}
B.action("swing_b", [(1, CARRY), (5, WIND_B), (8, HIT_B), (12, HIT_B), (18, CARRY)])
UP = {"spine": (-12, 0, 0), "chest": (-10, 0, 0), "upper_arm.R": (-170, 0, 15), "upper_arm.L": (-170, 0, -15),
      "forearm.R": (-30, 0, 0), "forearm.L": (-30, 0, 0)}
SLAM = {"spine": (30, 0, 0), "chest": (20, 0, 0), "head": (-20, 0, 0), "upper_arm.R": (-60, 0, 20), "upper_arm.L": (-60, 0, -20),
        "forearm.R": (-10, 0, 0), "forearm.L": (-10, 0, 0), "thigh.L": (-45, 0, 0), "thigh.R": (-15, 0, 0),
        "shin.L": (60, 0, 0), "shin.R": (50, 0, 0)}
B.action("finisher", [(1, CARRY), (7, UP), (11, SLAM), (17, SLAM), (25, CARRY)])
# Firewall: plant the hammer and push the left palm forward (shield goes up in front)
WALL = {"spine": (10, 0, 0), "upper_arm.L": (-85, 0, 0), "forearm.L": (-15, 0, 0), "hand.L": (-60, 0, 0),
        "upper_arm.R": (-40, 0, -10), "forearm.R": (-40, 0, 0), "thigh.L": (-30, 0, 0), "shin.L": (35, 0, 0), "thigh.R": (15, 0, 0)}
B.action("wall", [(1, CARRY), (5, WALL), (16, WALL), (24, CARRY)])
# Stand-up Meeting: wide arms out, then a hard pull-in (beckoning everyone to the huddle)
OPEN = {"chest": (-10, 0, 0), "upper_arm.L": (-80, 0, 45), "upper_arm.R": (-80, 0, -45), "forearm.L": (-10, 0, 0), "forearm.R": (-10, 0, 0)}
PULL = {"chest": (12, 0, 0), "spine": (6, 0, 0), "upper_arm.L": (-70, 0, -10), "upper_arm.R": (-70, 0, 10), "forearm.L": (-80, 0, 0), "forearm.R": (-80, 0, 0)}
B.action("pull", [(1, CARRY), (5, OPEN), (10, PULL), (18, PULL), (26, CARRY)])
# Rollback (ult): hammer raised high, left hand forward, chest out
ULT = {"chest": (-12, 0, 0), "head": (-10, 0, 0), "upper_arm.L": (-85, 0, 0), "forearm.L": (-10, 0, 0),
       "upper_arm.R": (-170, 0, -10), "forearm.R": (-20, 0, 0)}
B.action("ult", [(1, CARRY), (6, ULT), (26, ULT), (34, CARRY)])
KNEEL = {"thigh.L": (-90, 0, 0), "thigh.R": (-20, 0, 0), "shin.L": (100, 0, 0), "shin.R": (110, 0, 0), "spine": (20, 0, 0), "head": (20, 0, 0),
         "upper_arm.R": (-20, 0, -20), "upper_arm.L": (-20, 0, 20)}
DOWN = {"hips": (80, 0, 0), "thigh.L": (-20, 0, 0), "thigh.R": (-10, 0, 0), "shin.L": (30, 0, 0), "upper_arm.R": (-150, 0, -30),
        "upper_arm.L": (-150, 0, 30), "head": (-30, 0, 0)}
B.action("death", [(1, CARRY), (8, KNEEL, {"hips": (0, -0.33, 0)}), (18, DOWN, {"hips": (0, -0.75, 0.0)})])
B.end_anim()

B.export(os.path.join(OUT, "nidjo.glb"))
SH = arg("--shots")
B.shots(SH, 0.92, 2.4)
PO = arg("--poses")
if PO:
    B.shots(PO, 0.92, 2.4, views=())
    B.pose_shots(PO, [(a, f, y, "%s_%d_%d.png" % (a, f, y)) for a, f, y in
                      [("idle_loop", 1, 0), ("swing_a", 8, 0), ("finisher", 7, 90), ("finisher", 13, 90), ("wall", 10, 35),
                       ("pull", 5, 0), ("pull", 12, 0), ("ult", 12, 0), ("death", 18, 90), ("run_loop", 6, 90)]], 0.92, 2.6)
