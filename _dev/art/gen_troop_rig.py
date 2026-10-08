"""Genera las piezas animables del soldado y las armas (mismo estilo: trazo grueso oscuro, colores planos).

Salida (en OUT):
  troop/body.png, troop/leg_back.png, troop/leg_front.png, troop/hand.png  (mismo lienzo que el sprite / 2)
  weapons/<id>.png        arma de lado, apuntando a la derecha (para la mano)
  weapons/icons/<id>.png  icono cuadrado 128x128
  rig.json                pivotes y bocachas (px del sprite original, origen = centro del sprite)
Uso: python gen_troop_rig.py <sprite.png> <out_dir>
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

SRC, OUT = sys.argv[1], sys.argv[2]
DOWN = 0.5           # las piezas se guardan a la mitad del sprite original
OUTL = (34, 20, 14, 255)
LW = 20              # grosor del trazo exterior (px del original)

os.makedirs(f"{OUT}/troop", exist_ok=True)
os.makedirs(f"{OUT}/weapons/icons", exist_ok=True)

# ------------------------------------------------------------------ cuerpo
src = Image.open(SRC).convert("RGBA")
W, H = src.size
CX, CY = W / 2, H / 2
HAND_C, HAND_R = (795, 1012), 82       # puño delantero (lado derecho del dibujo)
BACK_FIST_C, BACK_FIST_R = (318, 1015), 95
CUT_Y = 1062                           # bajo esta línea, las piernas son piezas sueltas
LEG_TOP = 985                          # las piernas empiezan bajo el cinturón (solapan con el cuerpo)
SPLIT_X = 575                          # entrepierna


def circle_mask(c, r):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=255)
    return m


def rect_mask(x0, y0, x1, y1):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).rectangle([x0, y0, x1, y1], fill=255)
    return m


alpha = src.getchannel("A")


def poly_mask(pts):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


# Brazos sueltos (pivotan en el hombro). El delantero se dibuja encima del arma; su manga se
# vuelve a pintar encima para tapar el corte. El trasero va detrás del cuerpo en reposo.
FRONT_ARM = [(694, 846), (900, 846), (900, 965), (700, 965), (698, 900)]
BACK_ARM = [(150, 838), (418, 838), (414, 890), (410, 965), (150, 965)]
FRONT_SLEEVE = [(670, 760), (900, 800), (900, 874), (690, 874)]
BACK_SLEEVE = [(160, 760), (440, 740), (446, 872), (160, 872)]
SHOULDER_F, SHOULDER_B = (740, 836), (322, 828)
farm_m = ImageChops.lighter(poly_mask(FRONT_ARM), circle_mask(HAND_C, 86))
barm_m = ImageChops.lighter(poly_mask(BACK_ARM), circle_mask(BACK_FIST_C, 94))
arms_m = ImageChops.lighter(farm_m, barm_m)
upper_m = ImageChops.subtract(rect_mask(0, 0, W, CUT_Y), arms_m)
legb_m = ImageChops.subtract(rect_mask(0, LEG_TOP, SPLIT_X, H), arms_m)
legf_m = ImageChops.subtract(rect_mask(SPLIT_X, LEG_TOP, W, H), arms_m)


def part(mask, img=None):
    p = (img or src).copy()
    p.putalpha(ImageChops.multiply(p.getchannel("A"), mask))
    return p.resize((int(W * DOWN), int(H * DOWN)), Image.LANCZOS)


# Los puños tapaban parte de los muslos: se rellenan con el color del pantalón y su contorno.
PANTS = (214, 190, 140, 255)
patched = src.copy()
pd = ImageDraw.Draw(patched)
for poly, edge in (
        ([(345, 985), (575, 985), (575, 1100), (300, 1100)], [(345, 985), (300, 1100)]),
        ([(575, 985), (735, 985), (770, 1100), (575, 1100)], [(735, 985), (770, 1100)])):
    hole = ImageChops.multiply(poly_mask(poly), arms_m)
    patched.paste(PANTS, (0, 0), hole)
    clip = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(clip).line(edge, fill=OUTL, width=22)
    patched.paste(clip, (0, 0), ImageChops.multiply(clip.getchannel("A"), hole))

part(upper_m).save(f"{OUT}/troop/body.png")
part(legb_m, patched).save(f"{OUT}/troop/leg_back.png")
part(legf_m, patched).save(f"{OUT}/troop/leg_front.png")
part(farm_m).save(f"{OUT}/troop/arm_front.png")
part(barm_m).save(f"{OUT}/troop/arm_back.png")
part(poly_mask(FRONT_SLEEVE)).save(f"{OUT}/troop/sleeve_front.png")
part(poly_mask(BACK_SLEEVE)).save(f"{OUT}/troop/sleeve_back.png")

# Granada de mano (mismo estilo)
g = Image.new("RGBA", (220, 240), (0, 0, 0, 0))
gd = ImageDraw.Draw(g)
gd.ellipse([20, 50, 200, 230], fill=OUTL)
gd.rounded_rectangle([70, 10, 150, 80], 12, fill=OUTL)
gd.ellipse([40, 70, 180, 210], fill=(96, 112, 58, 255))
gd.ellipse([40, 140, 180, 210], fill=(74, 88, 44, 255))
gd.ellipse([40, 70, 180, 180], fill=(96, 112, 58, 255))
gd.rounded_rectangle([88, 28, 132, 70], 8, fill=(150, 155, 165, 255))
gd.ellipse([150, 10, 205, 60], outline=OUTL, width=12)
gd.line([(75, 105), (95, 95)], fill=(255, 255, 255, 110), width=12)
for y in (120, 160):
    gd.line([(48, y), (172, y)], fill=OUTL, width=6)
g.resize((110, 120), Image.LANCZOS).save(f"{OUT}/troop/grenade.png")

# ------------------------------------------------------------------ armas
STEEL = (92, 98, 108)
STEEL_D = (62, 66, 74)
STEEL_L = (140, 148, 158)
WOOD = (150, 92, 48)
WOOD_D = (112, 66, 34)
OLIVE = (98, 112, 62)
OLIVE_D = (72, 84, 46)
RED = (186, 52, 40)
SILVER = (205, 212, 220)

# Cada arma: lista de piezas (forma, puntos, color). Origen = empuñadura (donde va el puño).
# "r" = rectángulo [x0,y0,x1,y1] (redondeado 10), "p" = polígono, "e" = elipse.
WEAPONS = {
    "pistola": {"muzzle": (300, -68), "parts": [
        ("p", [(-40, -10), (40, -10), (20, 110), (-70, 100)], WOOD),
        ("r", [-20, -40, 210, 0], STEEL_D),
        ("r", [-70, -105, 300, -35], STEEL),
        ("r", [60, -10, 120, 40], None),
    ]},
    "subfusil": {"muzzle": (380, -62), "parts": [
        ("r", [-230, -95, -100, -50], STEEL_D),
        ("p", [(-45, -20), (15, -20), (0, 100), (-60, 95)], STEEL_D),
        ("r", [60, -25, 120, 150], STEEL_D),
        ("r", [-110, -115, 270, -15], STEEL),
        ("r", [260, -80, 380, -45], STEEL_D),
    ]},
    "fusil_asalto": {"muzzle": (560, -66), "parts": [
        ("p", [(-340, -105), (-130, -95), (-130, -35), (-330, -10)], OLIVE),
        ("p", [(-45, -20), (15, -20), (0, 100), (-60, 95)], OLIVE_D),
        ("p", [(70, -30), (140, -30), (175, 140), (100, 160)], STEEL_D),
        ("r", [-140, -120, 230, -25], STEEL),
        ("r", [-40, -165, 120, -115], STEEL_D),
        ("r", [220, -100, 440, -35], OLIVE),
        ("r", [430, -80, 560, -52], STEEL_D),
    ]},
    "escopeta": {"muzzle": (600, -82), "parts": [
        ("p", [(-340, -100), (-70, -90), (-70, -30), (-320, 10)], WOOD),
        ("r", [-80, -110, 140, -25], STEEL),
        ("r", [130, -98, 600, -66], STEEL_D),
        ("r", [130, -64, 470, -38], STEEL_D),
        ("r", [230, -75, 400, -20], WOOD),
        ("p", [(-45, -25), (10, -25), (-5, 90), (-60, 85)], WOOD_D),
    ]},
    "rifle_francotirador": {"muzzle": (700, -70), "parts": [
        ("p", [(-380, -110), (-100, -90), (-60, -35), (-360, 0)], WOOD),
        ("p", [(-45, -25), (10, -25), (-5, 90), (-60, 85)], WOOD_D),
        ("r", [-110, -105, 200, -35], STEEL),
        ("r", [190, -84, 700, -58], STEEL_D),
        ("p", [(200, -40), (320, -40), (380, 60), (360, 70), (300, -10)], STEEL_D),
        ("r", [30, -120, 70, -95], STEEL_D),
        ("r", [-60, -195, 260, -125], STEEL_D),
        ("e", [235, -205, 295, -115], STEEL),
    ]},
    "ametralladora": {"muzzle": (720, -62), "parts": [
        ("p", [(-330, -110), (-150, -100), (-150, -30), (-320, -10)], OLIVE_D),
        ("r", [-40, -10, 150, 140], OLIVE),
        ("p", [(-50, -15), (5, -15), (-5, 90), (-60, 85)], STEEL_D),
        ("r", [-160, -140, 250, -10], STEEL),
        ("r", [240, -110, 600, -40], STEEL_D),
        ("r", [590, -78, 720, -48], STEEL_D),
        ("r", [-20, -185, 180, -140], STEEL_D),
        ("p", [(470, -45), (500, -45), (430, 110), (405, 100)], STEEL_D),
        ("p", [(520, -45), (550, -45), (600, 105), (575, 115)], STEEL_D),
    ]},
    "lanzagranadas": {"muzzle": (520, -78), "parts": [
        ("p", [(-330, -100), (-120, -95), (-120, -35), (-320, -5)], OLIVE),
        ("p", [(-45, -20), (15, -20), (0, 95), (-60, 90)], STEEL_D),
        ("r", [-130, -110, 60, -30], STEEL_D),
        ("e", [20, -175, 230, 20], STEEL),
        ("r", [200, -125, 520, -35], OLIVE_D),
    ]},
    "bazuca": {"muzzle": (640, -110), "parts": [
        ("r", [-420, -175, 560, -50], OLIVE),
        ("p", [(540, -195), (640, -215), (640, -10), (540, -30)], OLIVE_D),
        ("r", [-440, -185, -360, -40], OLIVE_D),
        ("r", [-60, -60, 0, 80], STEEL_D),
        ("r", [140, -60, 190, 50], STEEL_D),
        ("r", [-60, -250, 40, -175], STEEL_D),
    ]},
    "cuchillo": {"muzzle": (330, -10), "parts": [
        ("r", [-80, -32, 60, 32], WOOD_D),
        ("r", [50, -60, 80, 60], STEEL_D),
        ("p", [(75, -36), (250, -36), (330, -10), (75, 26)], SILVER),
    ]},
}

# Detalles (líneas/círculos internos finos, brillos) por arma, dibujados encima.
def details(wid, d, o):
    def L(a, b, w=8, c=OUTL):
        d.line([(a[0] + o[0], a[1] + o[1]), (b[0] + o[0], b[1] + o[1])], fill=c, width=w)
    def C(c, r, fill=None, w=8):
        d.ellipse([c[0] - r + o[0], c[1] - r + o[1], c[0] + r + o[0], c[1] + r + o[1]], outline=OUTL, fill=fill, width=w)
    hl = (255, 255, 255, 70)
    if wid == "pistola":
        for x in range(150, 280, 30): L((x, -95), (x - 10, -50), 6)
        L((-60, -90), (290, -90), 8, hl)
    elif wid == "subfusil":
        L((-100, -100), (260, -100), 8, hl)
    elif wid == "fusil_asalto":
        for x in range(250, 430, 45): L((x, -90), (x, -45), 6)
        L((-130, -105), (220, -105), 8, hl)
    elif wid == "escopeta":
        for x in range(255, 400, 35): L((x, -70), (x, -25), 6)
        L((-70, -95), (590, -92), 6, hl)
    elif wid == "rifle_francotirador":
        L((-50, -180), (250, -180), 8, hl)
        C((265, -160), 20, (120, 200, 255, 255), 6)
    elif wid == "ametralladora":
        for x in range(270, 590, 50): C((x, -75), 14, (30, 30, 34, 255), 5)
        for y in range(15, 130, 35): L((-30, y), (140, y), 5)
        L((-150, -125), (240, -125), 8, hl)
    elif wid == "lanzagranadas":
        for a in range(0, 360, 60):
            r = math.radians(a)
            C((125 + 55 * math.cos(r), -78 + 55 * math.sin(r)), 22, (40, 40, 44, 255), 5)
    elif wid == "bazuca":
        for x in (-250, 300): L((x, -175), (x, -50), 14, OLIVE_D)
        L((-400, -150), (540, -150), 10, (255, 255, 255, 70))
        C((610, -112), 40, (25, 25, 25, 255), 6)
    elif wid == "cuchillo":
        L((90, -20), (240, -20), 6, (255, 255, 255, 140))
        for x in (-40, 0, 30): L((x, -28), (x, 28), 5)


def draw_shape(d, kind, pts, fill, o, grow=0):
    if kind == "r":
        x0, y0, x1, y1 = pts
        d.rounded_rectangle([x0 + o[0] - grow, y0 + o[1] - grow, x1 + o[0] + grow, y1 + o[1] + grow], 12 + grow, fill=fill)
    elif kind == "e":
        x0, y0, x1, y1 = pts
        d.ellipse([x0 + o[0] - grow, y0 + o[1] - grow, x1 + o[0] + grow, y1 + o[1] + grow], fill=fill)
    else:
        q = [(x + o[0], y + o[1]) for x, y in pts]
        d.polygon(q, fill=fill)
        if grow:
            d.line(q + [q[0]], fill=fill, width=grow * 2)
            for x, y in q:
                d.ellipse([x - grow, y - grow, x + grow, y + grow], fill=fill)


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c) + (255,)


def render_weapon(wid, spec):
    pad = 60
    xs, ys = [], []
    for kind, pts, _ in spec["parts"]:
        if kind in "re":
            xs += [pts[0], pts[2]]; ys += [pts[1], pts[3]]
        else:
            xs += [p[0] for p in pts]; ys += [p[1] for p in pts]
    x0, y0, x1, y1 = min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad
    w, h = int(x1 - x0), int(y1 - y0)
    o = (-x0, -y0)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 1) silueta exterior gruesa
    for kind, pts, col in spec["parts"]:
        if col is None:
            continue
        draw_shape(d, kind, pts, OUTL, o, LW)
    # 2) piezas con trazo interior fino y sombra inferior
    for kind, pts, col in spec["parts"]:
        if col is None:  # guardamonte: solo aro
            x0_, y0_, x1_, y1_ = pts
            d.rounded_rectangle([x0_ + o[0], y0_ + o[1], x1_ + o[0], y1_ + o[1]], 18, outline=OUTL, width=12)
            continue
        draw_shape(d, kind, pts, OUTL, o, 7)
        draw_shape(d, kind, pts, col + (255,), o, 0)
        # sombra en la mitad inferior de la pieza
        m = Image.new("L", img.size, 0)
        md = ImageDraw.Draw(m)
        draw_shape(md, kind, pts, 255, o, 0)
        bb = m.getbbox()
        if bb:
            cut = Image.new("L", img.size, 0)
            ImageDraw.Draw(cut).rectangle([0, bb[1] + (bb[3] - bb[1]) * 0.62, w, h], fill=255)
            sm = ImageChops.multiply(m, cut)
            img.paste(Image.new("RGBA", img.size, shade(col, 0.78)), (0, 0), sm)
    details(wid, d, o)
    grip = (o[0], o[1])
    muzzle = (spec["muzzle"][0] + o[0], spec["muzzle"][1] + o[1])
    return img, grip, muzzle


meta = {
    "src_size": [W, H], "down": DOWN,
    "shoulder_front": [SHOULDER_F[0] - CX, SHOULDER_F[1] - CY],
    "shoulder_back": [SHOULDER_B[0] - CX, SHOULDER_B[1] - CY],
    "fist_front": [HAND_C[0] - CX, HAND_C[1] - CY],
    "fist_back": [BACK_FIST_C[0] - CX, BACK_FIST_C[1] - CY],
    "hip_back": [470 - CX, 1040 - CY], "hip_front": [680 - CX, 1040 - CY],
    "weapons": {},
}
for wid, spec in WEAPONS.items():
    img, grip, muzzle = render_weapon(wid, spec)
    small = img.resize((max(1, int(img.width * DOWN)), max(1, int(img.height * DOWN))), Image.LANCZOS)
    small.save(f"{OUT}/weapons/{wid}.png")
    meta["weapons"][wid] = {
        "size": [img.width, img.height],
        "grip": [grip[0], grip[1]],
        "muzzle": [muzzle[0], muzzle[1]],
    }
    # Icono: el arma inclinada 28° hacia arriba, centrada en 128x128
    rot = img.rotate(28 if wid != "cuchillo" else 40, resample=Image.BICUBIC, expand=True)
    rot = rot.crop(rot.getbbox())
    S, M = 128, 8
    k = min((S - 2 * M) / rot.width, (S - 2 * M) / rot.height)
    rot = rot.resize((max(1, int(rot.width * k)), max(1, int(rot.height * k))), Image.LANCZOS)
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.alpha_composite(rot, ((S - rot.width) // 2, (S - rot.height) // 2))
    icon.save(f"{OUT}/weapons/icons/{wid}.png")

with open(f"{OUT}/rig.json", "w") as f:
    json.dump(meta, f, indent=1)
print("ok", list(meta["weapons"]))
