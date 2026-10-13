"""Cob - procedural Blender build (Blender 4.2, headless):
    blender -b --python src/heroes/models/cob/blender/build_cob.py -- [--out DIR] [--shots DIR] [--poses DIR]
A wide stone beetle: faceted grey shell plates over a dark core, moss tufts, amber crystals (one front-right
crystal is the shooter / muzzle), plated head with glowing amber eyes and curved mandibles, six thick
segmented stone legs with toes. Custom rig (body/head/mandibles/6x2 leg bones). Faces Blender -Y, metres.
Exports ../cob.glb."""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "common", "blender"))
from toonbuild import Build, arg
from mathutils import Vector, Matrix

B = Build("cob", {
    "stone":    (0.72, 0.73, 0.74),
    "stone_lt": (0.81, 0.81, 0.82),
    "stone_dk": (0.45, 0.45, 0.47),
    "belly":    (0.38, 0.38, 0.40),
    "moss":     (0.50, 0.62, 0.36),
    "amber":    (0.96, 0.60, 0.20),
    "amber_lt": (1.00, 0.78, 0.36),
    "eye":      (1.00, 0.74, 0.16),
    "pupil":    (0.30, 0.16, 0.05),
})
OUT = arg("--out", os.path.dirname(HERE))
rnd = random.Random(42)

SHELL_C = Vector((0, 0.12, 0.6)); SHELL_R = Vector((0.74, 0.86, 0.66))
HEAD_C = Vector((0, -0.9, 0.5)); HEAD_R = (0.4, 0.34, 0.35)

def on_shell(az, el, lift=0.0):
    """Point + normal on the shell ellipsoid; az 0 = back (+Y), 90 = left (+X); el = elevation."""
    a, e = math.radians(az), math.radians(el)
    d = Vector((math.cos(e) * math.sin(a), math.cos(e) * math.cos(a), math.sin(e)))
    p = SHELL_C + Vector((d.x * SHELL_R.x, d.y * SHELL_R.y, d.z * SHELL_R.z))
    n = Vector((d.x / SHELL_R.x, d.y / SHELL_R.y, d.z / SHELL_R.z)).normalized()
    return p + n * lift, n

def eul(n):
    return [math.degrees(a) for a in Vector((0, 0, 1)).rotation_difference(n).to_euler()]

# ------------------------------------------------------------- shell: dark core + faceted stone plates
B.ellipsoid("shell_core", SHELL_C, SHELL_R * 0.98, "stone_dk", ["body"], seg=18, rings=10)
B.ellipsoid("belly", (0, 0.05, 0.42), (0.6, 0.8, 0.26), "belly", ["body"], seg=14, rings=8)
plates = [(90, 1, 0.24)]   # (elevation, count, size)
plates += [(66, 6, 0.26), (42, 10, 0.27), (20, 13, 0.26), (0, 15, 0.24), (-16, 15, 0.2)]
pi = 0
for el, cnt, sz in plates:
    for k in range(cnt):
        az = 360.0 * (k + (0.5 if (el // 10) % 2 else 0.0)) / cnt + rnd.uniform(-6, 6)
        azn = (az + 360) % 360
        if el <= 20 and 150 < azn < 210:      # leave the head opening at the front
            continue
        p, n = on_shell(az, el + rnd.uniform(-3, 3), 0.02)
        mat = "stone" if rnd.random() < 0.7 else "stone_lt"
        w = sz * rnd.uniform(0.9, 1.1)
        B.rock("plate_%d" % pi, p, (w, w * 0.95, 0.075), mat, ["body"], seg=6, rings=4, rot=eul(n), seed=pi, jitter=0.1)
        pi += 1
# collar plates arching over the head
for k in range(5):
    az = 180 + (k - 2) * 20
    p, n = on_shell(az, 12 + abs(k - 2) * 4, 0.03)
    B.rock("collar_%d" % k, p, (0.2, 0.17, 0.08), "stone", ["body"], seg=6, rings=4, rot=eul(n), seed=100 + k)

# moss tufts: little clusters of thin blades on top of the shell
def tuft(name, p, n, bones):
    t1 = n.cross(Vector((1, 0, 0))).normalized() if abs(n.x) < 0.9 else n.cross(Vector((0, 1, 0))).normalized()
    t2 = n.cross(t1)
    for b in range(6):
        a = 2 * math.pi * b / 6 + rnd.uniform(-0.3, 0.3)
        d = (n * 1.0 + (t1 * math.cos(a) + t2 * math.sin(a)) * 0.9).normalized()
        L = rnd.uniform(0.07, 0.11)
        B.loft("%s_%d" % (name, b), [(p, 0.018, 0.012), (p + d * L, 0.002, 0.002)], "moss", bones, n=4)
    B.ellipsoid(name + "_base", p, (0.045, 0.045, 0.02), "moss", bones, seg=8, rings=4)
for k, (az, el) in enumerate([(40, 70), (140, 62), (250, 58), (320, 45), (100, 35), (200, 40), (10, 25), (280, 22), (60, 15), (160, 82), (300, 75)]):
    p, n = on_shell(az, el, 0.09)
    tuft("moss_%d" % k, p, n, ["body"])

# amber crystals (one front-right crystal is the shooter: Muzzle marker at its tip)
CRY = [((-0.36, -0.25), 58, 0.34, 0.085), ((0.5, 0.18), 40, 0.28, 0.075), ((0.28, 0.55), 52, 0.3, 0.08), ((-0.55, 0.42), 30, 0.24, 0.07)]
for k, ((x, y), el, h, r) in enumerate(CRY):
    az = math.degrees(math.atan2(x, y))
    p, n = on_shell(az, el, 0.02)
    B.crystal("crystal_%d" % k, p, h, r, "amber" if k % 2 == 0 else "amber_lt", ["body"], tilt=eul((n + Vector((0, 0, 0.6))).normalized()))
# shooter crystal: front-right, pointing forward (character's right is -X)
GUN_BASE = Vector((-0.45, -0.74, 0.92))
GUN_DIR = Vector((0, -1, 0.15)).normalized()
B.crystal("gun_crystal", GUN_BASE, 0.4, 0.075, "amber_lt", ["body"], tilt=eul(GUN_DIR))
B.rock("gun_mount", GUN_BASE + Vector((0, 0.06, -0.03)), (0.13, 0.13, 0.08), "stone", ["body"], seg=6, rings=4, seed=7)
MUZZLE = GUN_BASE + GUN_DIR * 0.42

# ------------------------------------------------------------- head: plated dome, amber eyes, mandibles
B.rock("head", HEAD_C, HEAD_R, "stone", ["head"], seg=10, rings=7, seed=3, jitter=0.05)
for k, (dx, dz, w) in enumerate([(0, 0.2, 0.16), (-0.15, 0.13, 0.13), (0.15, 0.13, 0.13), (0, 0.06, 0.12)]):
    q = HEAD_C + Vector((dx * 1.2, -0.2 - abs(dx) * 0.2, dz * 1.2))
    n = (q - HEAD_C).normalized()
    B.rock("head_plate_%d" % k, q, (w, w * 0.9, 0.05), "stone_lt", ["head"], seg=6, rings=4, rot=eul(n), seed=20 + k)
B.rock("snout", HEAD_C + Vector((0, -0.3, -0.1)), (0.17, 0.15, 0.14), "stone", ["head"], seg=8, rings=5, seed=9)
for s, nm in ((1, "L"), (-1, "R")):
    ec = HEAD_C + Vector((s * 0.2, -0.27, 0.05))
    B.ellipsoid("eye_rim_%s" % nm, ec + Vector((0, 0.01, 0)), (0.085, 0.05, 0.085), "stone_dk", ["head"], seg=10, rings=6)
    B.ellipsoid("eye_%s" % nm, ec, (0.07, 0.045, 0.07), "eye", ["head"], seg=10, rings=6)
    B.ellipsoid("pupil_%s" % nm, ec + Vector((0, -0.04, 0)), (0.028, 0.012, 0.028), "pupil", ["head"], seg=8, rings=4)
    # mandible: thick base curving down and inward to a point
    m0 = HEAD_C + Vector((s * 0.17, -0.3, -0.16))
    path = [m0, m0 + Vector((s * 0.03, -0.1, -0.1)), m0 + Vector((s * 0.0, -0.15, -0.24)), m0 + Vector((-s * 0.06, -0.14, -0.33))]
    B.loft("mandible_" + nm, [(path[0], 0.06, 0.055), (path[1], 0.05, 0.045), (path[2], 0.032, 0.03), (path[3], 0.004, 0.004)],
           "stone_lt", ["mandible." + nm], n=8)

# ------------------------------------------------------------- legs: 3 per side, thick stone segments + toes
LEGS = {}
for s, nm in ((1, "L"), (-1, "R")):
    for key, y, fwd in (("f", -0.5, -0.32), ("m", 0.08, 0.0), ("b", 0.6, 0.3)):
        hip = Vector((s * 0.5, y, 0.42))
        knee = Vector((s * 0.88, y + fwd * 0.6, 0.5))
        foot = Vector((s * 1.0, y + fwd, 0.06))
        b0, b1 = "leg_%s_0.%s" % (key, nm), "leg_%s_1.%s" % (key, nm)
        LEGS[(key, nm)] = (hip, knee, foot)
        B.loft(b0, [(hip, 0.16, 0.16), (hip.lerp(knee, 0.5), 0.175, 0.175), (knee, 0.155, 0.155)], "stone", [b0, b1], n=9)
        B.loft(b1, [(knee, 0.16, 0.16), (knee.lerp(foot, 0.5), 0.15, 0.15), (foot + Vector((0, 0, 0.05)), 0.18, 0.18)], "stone", [b1, b0], n=9)
        # segment bands (lighter plates) on upper + lower leg
        for j, (a, b, t) in enumerate(((hip, knee, 0.5), (knee, foot, 0.3), (knee, foot, 0.65))):
            q = a.lerp(b, t)
            d = (b - a).normalized()
            up = Vector((s * 0.3, 0, 1)).normalized()
            n = (up - d * up.dot(d)).normalized()
            B.rock("%s_plate_%d" % (b0, j), q + n * 0.11, (0.17, 0.14, 0.07), "stone_lt", [b0 if j == 0 else b1], seg=6, rings=4, rot=eul(n), seed=hash((key, nm, j)) % 999)
        B.rock(b0 + "_knee", knee + Vector((0, 0, 0.04)), (0.17, 0.17, 0.13), "stone", [b0, b1], seg=6, rings=4, seed=hash((key, nm)) % 999)
        for t in range(3):
            a = math.radians(-35 + 35 * t)
            dirv = Vector((s * math.sin(a) * 0.6 + s * 0.4, -math.cos(a) if key != "b" else -math.cos(a) * 0.6, 0)).normalized()
            B.rock("%s_toe_%d" % (b1, t), foot + dirv * 0.17 + Vector((0, 0, -0.01)), (0.075, 0.075, 0.06), "stone", [b1], seg=6, rings=4, seed=t + 50)

# ------------------------------------------------------------- armature
B.begin_rig("CobRig")
B.bone("root", (0, 0, 0), (0, 0.3, 0))
B.bone("body", (0, 0.35, 0.55), (0, -0.45, 0.55), "root")
B.bone("head", (0, -0.62, 0.5), (0, -1.25, 0.5), "body")
for s, nm in ((1, "L"), (-1, "R")):
    m0 = HEAD_C + Vector((s * 0.17, -0.3, -0.16))
    B.bone("mandible." + nm, m0, m0 + Vector((-s * 0.06, -0.14, -0.33)), "head")
    for key in "fmb":
        hip, knee, foot = LEGS[(key, nm)]
        B.bone("leg_%s_0.%s" % (key, nm), hip, knee, "body")
        B.bone("leg_%s_1.%s" % (key, nm), knee, foot, "leg_%s_0.%s" % (key, nm), connect=True)
B.end_rig()
tris = B.skin_and_join("CobMesh")
B.marker("Muzzle", "body", MUZZLE)

# ------------------------------------------------------------- animations (24 fps)
B.begin_anim()
def legs(f):
    """f(key, side_sign, nm) -> (x,y,z) for upper bone; returns pose dict incl. lower bones counter-rotated."""
    p = {}
    for s, nm in ((1, "L"), (-1, "R")):
        for key in "fmb":
            up, lo = f(key, s, nm)
            p["leg_%s_0.%s" % (key, nm)] = up
            p["leg_%s_1.%s" % (key, nm)] = lo
    return p
def idle(br):
    p = {"head": (br, 0, 0), "mandible.L": (0, 0, br * 3), "mandible.R": (0, 0, -br * 3)}
    return p
B.action("idle_loop", [(1, idle(0), {"body": (0, 0, 0)}), (25, idle(2), {"body": (0, 0, 0.02)}), (49, idle(0), {"body": (0, 0, 0)})])

TRI_A = {("f", "L"), ("m", "R"), ("b", "L")}
def gait(ph):
    def f(key, s, nm):
        g = 0.0 if (key, nm) in TRI_A else math.pi
        sw = math.sin(ph + g)
        lift = max(0.0, math.cos(ph + g))
        return (-lift * 22 * s, 0, sw * 22 * s), (lift * 14 * s, 0, 0)
    p = legs(f)
    p["head"] = (math.sin(ph * 2) * 2, 0, math.sin(ph) * 3)
    p["body"] = (0, math.sin(ph) * 3, 0)
    return p
run = []
for k in range(9):
    ph = 2 * math.pi * k / 8
    run.append((1 + k * 2, gait(ph), {"body": (0, 0, abs(math.sin(ph)) * 0.025)}))
B.action("run_loop", run)

AIM = {"head": (-12, 0, 0), "mandible.L": (0, 0, -22), "mandible.R": (0, 0, 22)}
B.action("aim_loop", [(1, AIM), (11, AIM)])
B.action("shoot", [(1, {}), (3, AIM, {"body": (0, 0.05, 0)}), (8, AIM), (14, {})])
# boulder roll (0.8 s): legs tucked in, body spins forward
TUCK = legs(lambda k, s, nm: ((-50 * s, 0, 0), (60 * s, 0, 0)))
rollf = [(1, {}), (3, dict(TUCK), {"body": (0, 0, 0.2)})]
for i, a in enumerate((-90, -180, -270, -360)):
    p = dict(TUCK); p["body"] = (a, 0, 0); p["head"] = (25, 0, 0)
    rollf.append((3 + (i + 1) * 3.5, p, {"body": (0, 0, 0.2)}))
rollf.append((24, {}))
B.action("roll", [(int(f), p, *r) for f, p, *r in rollf])
# geode wall: rear up on the back legs, slam the front legs down
REAR = legs(lambda k, s, nm: ((-45 * s, 0, -20 * s), (30 * s, 0, 0)) if k == "f" else ((0, 0, 0), (0, 0, 0)))
REAR["body"] = (20, 0, 0); REAR["head"] = (15, 0, 0); REAR["mandible.L"] = (0, 0, -25); REAR["mandible.R"] = (0, 0, 25)
STOMP = legs(lambda k, s, nm: ((15 * s, 0, 15 * s), (-10 * s, 0, 0)) if k == "f" else ((0, 0, 0), (0, 0, 0)))
STOMP["body"] = (-6, 0, 0); STOMP["head"] = (-8, 0, 0)
B.action("wall", [(1, {}), (7, REAR, {"body": (0, 0, 0.12)}), (11, STOMP, {"body": (0, 0, -0.06)}), (16, STOMP), (24, {})])
# quarry quake (ult): crouch, heave up, crash down with legs splayed
CR = legs(lambda k, s, nm: ((10 * s, 0, 0), (-15 * s, 0, 0)))
UPP = legs(lambda k, s, nm: ((-30 * s, 0, 0), (40 * s, 0, 0)))
UPP["body"] = (12, 0, 0); UPP["head"] = (12, 0, 0)
SPL = legs(lambda k, s, nm: ((25 * s, 0, 0), (-30 * s, 0, 0)))
SPL["head"] = (-15, 0, 0); SPL["mandible.L"] = (0, 0, -25); SPL["mandible.R"] = (0, 0, 25)
B.action("slam", [(1, {}), (5, CR, {"body": (0, 0, -0.1)}), (11, UPP, {"body": (0, 0, 0.45)}), (15, SPL, {"body": (0, 0, -0.14)}),
                  (22, SPL, {"body": (0, 0, -0.12)}), (30, {})])
# death: flips over onto its back, legs curl
CURL = legs(lambda k, s, nm: ((-60 * s, 0, 0), (70 * s, 0, 0)))
FLIP = dict(CURL); FLIP["body"] = (0, 180, 0)
HALF = dict(CURL); HALF["body"] = (0, 100, 0)
B.action("death", [(1, {}), (8, HALF, {"body": (0, 0, 0.5)}), (16, FLIP, {"body": (0, 0, 0.75)}), (24, FLIP, {"body": (0, 0, 0.72)})])
B.end_anim()

B.export(os.path.join(OUT, "cob.glb"))
B.shots(arg("--shots"), 0.55, 3.0)
PO = arg("--poses")
if PO:
    B.shots(PO, 0.6, 2.6, views=())
    B.pose_shots(PO, [(a, f, y, "%s_%d_%d.png" % (a, f, y)) for a, f, y in
                      [("idle_loop", 1, 0), ("run_loop", 3, 0), ("run_loop", 3, 90), ("run_loop", 11, 90), ("aim_loop", 1, 90), ("roll", 8, 90),
                       ("wall", 7, 90), ("wall", 11, 90), ("slam", 11, 90), ("slam", 15, 0), ("death", 24, 90), ("death", 24, 35)]], 0.6, 3.0)
