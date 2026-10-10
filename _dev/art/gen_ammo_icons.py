"""Iconos de munición (mismo estilo que las armas: trazo grueso oscuro, colores planos con luz y sombra).
Cada icono son 3 cartuchos de pie, el del centro delante. La punta cambia según el tipo.
Salida: <out>/<id>.png de 128x128.  Uso: python gen_ammo_icons.py <out_dir>"""
import sys, math
from PIL import Image, ImageDraw

OUT = sys.argv[1]
SS = 4
N = 128
OL = (30, 20, 12, 255)
BRASS = (214, 164, 72, 255)
BRASS_HI = (246, 210, 128, 255)
BRASS_SH = (160, 112, 42, 255)

# id -> (punta, luz de la punta, sombra de la punta, extra)
TYPES = {
    "normal": ((176, 112, 70, 255), (214, 152, 104, 255), (128, 76, 46, 255), None),
    "balas_venenosas": ((120, 204, 40, 255), (186, 240, 96, 255), (70, 132, 22, 255), "poison"),
    "balas_perforantes": ((86, 92, 104, 255), (150, 158, 172, 255), (52, 56, 66, 255), "ap"),
    "balas_aturdidoras": ((60, 130, 220, 255), (130, 190, 255, 255), (34, 84, 160, 255), "spark"),
}


def S(v):
    return [x * SS for x in v]


def cartridge(d, cx, base, w, h, tip, tip_hi, tip_sh, extra):
    """Un cartucho: vaina de latón (con culote) y proyectil ojival. cx = centro, base = y del suelo."""
    lw = 5.0
    case_h = h * 0.6
    neck = base - case_h
    tip_h = h - case_h
    hw = w / 2
    # --- contorno (se dibuja todo engordado en oscuro y luego el relleno encima)
    ogive = []
    for i in range(0, 21):
        t = i / 20
        a = math.pi * t
        x = cx - hw * 0.92 * math.cos(a)
        y = neck - tip_h * math.sin(a) ** 0.75
        ogive.append((x, y))
    body = [(cx - hw, base - 6), (cx - hw, neck + 4), (cx - hw * 0.92, neck)] + ogive + [(cx + hw * 0.92, neck), (cx + hw, neck + 4), (cx + hw, base - 6)]
    rim = [cx - hw - 3, base - 9, cx + hw + 3, base]
    d.rounded_rectangle(S([rim[0] - lw, rim[1] - lw, rim[2] + lw, rim[3] + lw]), radius=3 * SS, fill=OL)
    d.polygon(S(sum(([p[0] - 0, p[1]] for p in body), [])), fill=OL, outline=OL)
    d.line(S(sum(([p[0], p[1]] for p in body + [body[0]]), [])), fill=OL, width=int(lw * 2 * SS), joint="curve")
    # --- vaina
    d.rectangle(S([cx - hw, neck + 2, cx + hw, base - 6]), fill=BRASS)
    d.rectangle(S([cx + hw * 0.35, neck + 2, cx + hw, base - 6]), fill=BRASS_SH)
    d.rectangle(S([cx - hw * 0.6, neck + 4, cx - hw * 0.3, base - 9]), fill=BRASS_HI)
    # culote
    d.rounded_rectangle(S([rim[0], rim[1], rim[2], rim[3]]), radius=2 * SS, fill=BRASS_SH)
    d.line(S([cx - hw, base - 9, cx + hw, base - 9]), fill=OL, width=int(2.5 * SS))
    # --- proyectil
    d.polygon(S(sum(([p[0], p[1]] for p in [(cx - hw * 0.92, neck + 1)] + ogive + [(cx + hw * 0.92, neck + 1)]), [])), fill=tip)
    shade = [(cx + hw * 0.25, neck + 1)] + [p for p in ogive if p[0] >= cx + hw * 0.25] + [(cx + hw * 0.92, neck + 1)]
    d.polygon(S(sum(([p[0], p[1]] for p in shade), [])), fill=tip_sh)
    d.line(S([cx - hw * 0.5, neck - 2, cx - hw * 0.35, neck - tip_h * 0.7]), fill=tip_hi, width=int(3 * SS))
    # unión vaina-proyectil
    d.line(S([cx - hw, neck + 2, cx + hw, neck + 2]), fill=OL, width=int(3 * SS))
    top = neck - tip_h
    if extra == "ap":     # perforante: anillo de acero endurecido
        d.line(S([cx - hw * 0.8, neck - tip_h * 0.38, cx + hw * 0.8, neck - tip_h * 0.38]), fill=(205, 210, 220, 255), width=int(3 * SS))
    elif extra == "poison":  # venenosa: banda morada oscura
        d.line(S([cx - hw * 0.88, neck - tip_h * 0.22, cx + hw * 0.88, neck - tip_h * 0.22]), fill=(70, 30, 80, 255), width=int(3 * SS))
    elif extra == "spark":  # aturdidora: banda blanca
        d.line(S([cx - hw * 0.88, neck - tip_h * 0.22, cx + hw * 0.88, neck - tip_h * 0.22]), fill=(230, 240, 255, 255), width=int(3 * SS))
    return top


def emblem(d, kind):
    """Pequeño distintivo arriba a la derecha (gota de veneno, rayo, escudo roto…)."""
    if kind == "poison":  # gota verde ácido con burbujas
        drop = [(102, 4)] + [(102 - 12 * math.sin(a), 28 + 12 * math.cos(a)) for a in [i * math.pi / 10 for i in range(-7, 8)]]
        d.line(S(sum(([x, y] for x, y in drop + [drop[0]]), [])), fill=OL, width=int(7 * SS), joint="curve")
        d.polygon(S(sum(([x, y] for x, y in drop), [])), fill=(126, 222, 46, 255))
        d.polygon(S(sum(([x, y] for x, y in drop if x >= 103), [])) + S([103, 40]), fill=(76, 150, 26, 255))
        d.ellipse(S([94, 24, 100, 30]), fill=(220, 255, 170, 255))
        for bx, by, r in [(116, 8, 4.5), (122, 20, 3)]:  # burbujas
            d.ellipse(S([bx - r - 2, by - r - 2, bx + r + 2, by + r + 2]), fill=OL)
            d.ellipse(S([bx - r, by - r, bx + r, by + r]), fill=(170, 240, 90, 255))
    elif kind == "spark":
        pts = [(108, 8), (96, 28), (105, 28), (98, 44), (116, 22), (107, 22), (114, 8)]
        d.line(S(sum(([x, y] for x, y in pts + [pts[0]]), [])), fill=OL, width=int(7 * SS), joint="curve")
        d.polygon(S(sum(([x, y] for x, y in pts), [])), fill=(255, 226, 80, 255))
    elif kind == "ap":
        d.polygon(S([104, 8, 118, 14, 116, 30, 104, 40, 92, 30, 90, 14]), fill=OL)
        d.polygon(S([104, 12, 114, 17, 112, 29, 104, 36, 96, 29, 94, 17]), fill=(150, 158, 172, 255))
        d.line(S([98, 14, 110, 34]), fill=OL, width=int(4 * SS))


def icon(id_):
    tip, hi, sh, extra = TYPES[id_]
    im = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # dos de atrás algo más bajos y a los lados, el del centro delante
    cartridge(d, 38, 112, 24, 70, tip, hi, sh, extra)
    cartridge(d, 90, 112, 24, 70, tip, hi, sh, extra)
    cartridge(d, 64, 120, 28, 86, tip, hi, sh, extra)
    if extra:
        emblem(d, extra)
    return im.resize((N, N), Image.LANCZOS)


for k in TYPES:
    icon(k).save(f"{OUT}/{k}.png")
print("ok")
