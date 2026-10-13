"""Flat doodle concept sheets for Tomo and Nido (PIL, drawn by hand from the reference photos).
python3 docs/concept/draw_concepts.py OUTDIR  -> tomo_v1.png, nidjo_v1.png, nidjo_v2.png, nidjo_v3.png (1024x576, ~8 heads tall)."""
import sys, os
from PIL import Image, ImageDraw
S = 2                      # supersample
W, H = 1024 * S, 576 * S
K = (0, 0, 0); WH = (255, 255, 255)
LW = 5 * S

def P(pts, ox, oy):
    return [((ox + x) * S, (oy + y) * S) for x, y in pts]

def poly(d, pts, fill, ox=512, oy=0, w=LW):
    d.polygon(P(pts, ox, oy), fill=fill, outline=K, width=w)

def ell(d, cx, cy, rx, ry, fill, ox=512, w=LW):
    d.ellipse([((ox + cx - rx) * S, (cy - ry) * S), ((ox + cx + rx) * S, (cy + ry) * S)], fill=fill, outline=K, width=w)

def line(d, pts, ox=512, w=LW, c=K):
    d.line(P(pts, ox, 0), fill=c, width=w, joint="curve")

def mirror(pts):
    return [(-x, y) for x, y in pts]

def face(d, beard, glasses=False, goatee=False):
    # head ~64 px (8 heads ~ 512 px figure)
    ell(d, 0, 74, 25, 31, WH)
    for s in (1, -1):
        ell(d, s * 26, 78, 5, 8, WH, w=3 * S)
    if beard:      # short dark beard along the jaw + moustache
        poly(d, [(-24, 76), (-20, 96), (-10, 105), (0, 107), (10, 105), (20, 96), (24, 76), (18, 88), (6, 92), (-6, 92), (-18, 88)], K)
        poly(d, [(-9, 87), (0, 84), (9, 87), (0, 89)], K, w=2 * S)
        line(d, [(-5, 95), (5, 95)], w=3 * S, c=WH)
    if goatee:     # light goatee + thin moustache
        poly(d, [(-7, 96), (7, 96), (4, 106), (-4, 106)], WH, w=3 * S)
        line(d, [(-9, 89), (9, 89)], w=3 * S)
        line(d, [(-6, 94), (0, 96), (6, 94)], w=3 * S)
    if not beard and not goatee:
        line(d, [(-6, 94), (6, 94)], w=3 * S)
    for s in (1, -1):   # eyes + brows
        ell(d, s * 10, 74, 2.5, 2.5, K, w=S)
        line(d, [(s * 4, 67), (s * 16, 66)], w=4 * S)
    line(d, [(0, 76), (-3, 84), (2, 85)], w=3 * S)   # nose

def tomo(out):
    im = Image.new("RGB", (W, H), WH); d = ImageDraw.Draw(im)
    RED = (214, 40, 40)
    # legs (lean, tall), socks, red sneakers
    for s in (1, -1):
        poly(d, [(s * 8, 330), (s * 30, 330), (s * 34, 470), (s * 22, 470)], WH)          # bare legs
        poly(d, [(s * 22, 470), (s * 35, 470), (s * 35, 500), (s * 21, 500)], WH)           # socks
        line(d, [(s * 22, 478), (s * 35, 478)], w=3 * S)
        poly(d, [(s * 18, 500), (s * 38, 500), (s * 38 + s * 22, 518), (s * 60, 532), (s * 16, 532)], RED)   # sneakers
        line(d, [(s * 16, 524), (s * 60, 524)], w=4 * S)
    # dark shorts (to the knee)
    poly(d, [(-40, 245), (40, 245), (44, 345), (6, 345), (0, 290), (-6, 345), (-44, 345)], K)
    line(d, [(-40, 252), (40, 252)], w=2 * S, c=WH)
    # black tee (slim torso), arms
    poly(d, [(-46, 128), (46, 128), (64, 182), (48, 192), (42, 170), (42, 255), (-42, 255), (-42, 170), (-48, 192), (-64, 182)], K)
    line(d, [(-12, 130), (0, 140), (12, 130)], w=3 * S, c=WH)
    for s in (1, -1):
        poly(d, [(s * 52, 186), (s * 64, 182), (s * 68, 290), (s * 56, 292)], WH)                # forearms
        ell(d, s * 63, 300, 9, 12, WH)
    # neck + head + beanie
    poly(d, [(-9, 100), (9, 100), (11, 130), (-11, 130)], WH)
    face(d, beard=True)
    poly(d, [(-27, 66), (-25, 46), (-14, 32), (0, 28), (14, 32), (25, 46), (27, 66)], K)
    line(d, [(-27, 60), (27, 60)], w=3 * S, c=WH)
    # prop: a laptop held at the side (closed, red accent sticker)
    poly(d, [(-100, 250), (-70, 250), (-66, 330), (-96, 330)], WH, ox=512)
    ell(d, -83, 290, 6, 6, RED)
    im.resize((1024, 576), Image.LANCZOS).save(out)

def nidjo(out, v2=False, jacket=None, bald=None):
    """v1: jacket=v1 + hair. v2: open tartan jacket + bald. v3 = nidjo(out, jacket=True, bald=False)."""
    jacket = v2 if jacket is None else jacket
    bald = v2 if bald is None else bald
    im = Image.new("RGB", (W, H), WH); d = ImageDraw.Draw(im)
    GREEN = (40, 120, 70); RED = (190, 35, 40); NAVY = (28, 36, 70)
    # black trousers (sturdy), black sneakers
    for s in (1, -1):
        poly(d, [(s * 4, 300), (s * 44, 300), (s * 42, 500), (s * 12, 500)], K)
        poly(d, [(s * 8, 500), (s * 46, 500), (s * 64, 518), (s * 64, 532), (s * 6, 532)], WH)
        line(d, [(s * 6, 524), (s * 64, 524)], w=4 * S)
    # striped tee (navy/white)
    poly(d, [(-48, 130), (48, 130), (50, 300), (-50, 300)], WH)
    for k in range(9):
        y = 146 + k * 17
        d.rectangle([((512 - 46) * S, y * S), ((512 + 46) * S, (y + 7) * S)], fill=NAVY)
    # belt bag across the hips (black)
    poly(d, [(-58, 236), (58, 214), (60, 222), (-56, 244)], K)
    poly(d, [(-30, 240), (30, 230), (34, 262), (-28, 272)], K)
    line(d, [(-26, 252), (30, 242)], w=2 * S, c=WH)
    # green Harrington jacket, open, red tartan lining visible at the front edges
    for s in (1, -1):
        poly(d, [(s * 28, 128), (s * 62, 134), (s * 74, 200), (s * 66, 300), (s * 32, 304), (s * 38, 160)], GREEN)
        if jacket:   # wide open front: red tartan lining panels with whitish crossing lines
            poly(d, [(s * 18, 140), (s * 44, 150), (s * 40, 304), (s * 20, 304)], RED, w=3 * S)
            for yy in range(160, 300, 18):
                line(d, [(s * 20, yy), (s * 42, yy - 2)], w=2 * S, c=(245, 235, 225))
            for xx in (24, 31, 38):
                line(d, [(s * xx, 148), (s * (xx - 1), 302)], w=2 * S, c=(245, 235, 225))
            line(d, [(s * 22, 222), (s * 41, 220)], w=1 * S, c=K)
            poly(d, [(s * 12, 124), (s * 34, 120), (s * 48, 176), (s * 30, 150)], RED, w=3 * S)   # turned-back lapel
        else:
            poly(d, [(s * 30, 160), (s * 38, 160), (s * 32, 304), (s * 26, 304)], RED, w=3 * S)       # lining strip
            for yy in (190, 230, 270):
                line(d, [(s * 27, yy), (s * 37, yy - 2)], w=2 * S)                                    # tartan lines
            line(d, [(s * 33, 175), (s * 30, 300)], w=2 * S)
        poly(d, [(s * 66, 300), (s * 32, 304), (s * 32, 314), (s * 66, 310)], GREEN)            # ribbed hem
        # sleeves + hands
        poly(d, [(s * 62, 134), (s * 80, 150), (s * 86, 290), (s * 66, 292), (s * 66, 180)], GREEN)
        poly(d, [(s * 66, 288), (s * 86, 286), (s * 86, 298), (s * 66, 300)], GREEN)
        ell(d, s * 77, 310, 11, 13, WH)
        if not jacket:
            poly(d, [(s * 12, 124), (s * 30, 122), (s * 40, 146), (s * 26, 150)], GREEN)            # collar
    # neck + head + short hair
    poly(d, [(-11, 100), (11, 100), (13, 128), (-13, 128)], WH)
    face(d, beard=False, goatee=True)
    if bald:   # mostly bald: very short grey buzz low on the sides/back only, high receding (M-shaped) hairline
        BUZZ = (190, 190, 190)
        for s in (1, -1):
            d.polygon(P([(s * 26, 84), (s * 26, 66), (s * 23, 58), (s * 19, 52), (s * 15, 58), (s * 18, 68), (s * 20, 84)], 512, 0), fill=BUZZ)
            for (x, y) in ((21, 66), (22, 74), (19, 60)):
                line(d, [(s * x, y), (s * (x + 1), y + 2)], w=2 * S, c=(120, 120, 120))
            line(d, [(s * 15, 58), (s * 18, 68), (s * 20, 82)], w=2 * S, c=(120, 120, 120))   # receding edge at the temples
        line(d, [(-10, 57), (-4, 53)], w=2 * S); line(d, [(10, 57), (4, 53)], w=2 * S)   # forehead creases
        ell(d, 0, 74, 25, 31, None)   # re-ink the head outline over the buzz
    else:
        poly(d, [(-25, 70), (-24, 52), (-14, 42), (0, 40), (14, 42), (24, 52), (25, 70), (18, 56), (0, 52), (-18, 56)], K)
    im.resize((1024, 576), Image.LANCZOS).save(out)

if __name__ == "__main__":
    o = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    tomo(os.path.join(o, "tomo_v1.png")); nidjo(os.path.join(o, "nidjo_v1.png")); nidjo(os.path.join(o, "nidjo_v2.png"), v2=True)
    nidjo(os.path.join(o, "nidjo_v3.png"), jacket=True, bald=False)   # v1 head/hair + v2 jacket
