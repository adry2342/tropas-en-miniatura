# Arte del Códice como libro: tapa de cuero militar, doble página de pergamino, portada cerrada y hojas sueltas.
# Coordenadas lógicas (las del juego): libro 1040×600. Se pinta a K× para nitidez.
import numpy as np, math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
K = 2
BW, BH = 1040, 600
SPINE = 520
LP = (40, 26, 517, 570)     # página izquierda (x0, y0, x1, y1)
RP = (523, 26, 1000, 570)   # página derecha
FONTS = sys.argv[2]
OUT = sys.argv[1]
rng = np.random.default_rng(42)

def k(v): return int(round(v * K))
def kb(b): return [k(v) for v in b]

def noise(w, h, scale, seed):
    r = np.random.default_rng(seed)
    small = r.random((max(2, h // scale), max(2, w // scale)))
    im = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.array(im).astype(float) / 255.0

def fractal(w, h, seed, octaves=((80, .5), (24, .3), (6, .15), (2, .05))):
    acc = np.zeros((h, w))
    for i, (sc, a) in enumerate(octaves):
        acc += noise(w, h, max(1, k(sc)), seed + i) * a
    return acc / sum(a for _, a in octaves)

def to_img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

def leather(w, h, base=(58, 54, 36), seed=1):
    n = fractal(w, h, seed)
    grain = noise(w, h, 1, seed + 9)
    arr = np.zeros((h, w, 4))
    for c in range(3):
        arr[:, :, c] = base[c] * (0.72 + 0.5 * n) + (grain - 0.5) * 10
    arr[:, :, 3] = 255
    # arrugas finas
    cr = noise(w, h, k(3), seed + 20)
    creases = np.clip((np.abs(cr - 0.5) < 0.012) * 1.0, 0, 1)
    arr[:, :, :3] *= (1 - 0.18 * creases[:, :, None])
    return arr

def vignette(arr, strength=0.45, power=2.2):
    h, w = arr.shape[:2]
    y = np.linspace(-1, 1, h)[:, None]
    x = np.linspace(-1, 1, w)[None, :]
    d = np.clip((np.abs(x) ** power + np.abs(y) ** power) ** (1 / power), 0, 1.4)
    arr[:, :, :3] *= (1 - strength * np.clip(d - 0.35, 0, 1) ** 1.5)[:, :, None]
    return arr

def parchment(w, h, seed, gutter_side):
    """gutter_side: 'right' (página izq: lomo a la derecha) o 'left'"""
    n = fractal(w, h, seed)
    fine = noise(w, h, 1, seed + 5)
    blot = fractal(w, h, seed + 30, ((140, .6), (50, .4)))
    arr = np.zeros((h, w, 4))
    base = np.array([239, 226, 192])
    for c in range(3):
        arr[:, :, c] = base[c] * (0.9 + 0.12 * n) - (blot > 0.62) * (blot - 0.62) * 120 * (1.0 if c == 2 else 0.6) + (fine - 0.5) * 8
    arr[:, :, 3] = 255
    # bordes envejecidos
    y = np.linspace(0, 1, h)[:, None]
    x = np.linspace(0, 1, w)[None, :]
    edge = np.minimum(np.minimum(x, 1 - x) * w, np.minimum(y, 1 - y) * h) / K
    burn = np.clip(1 - edge / 26.0, 0, 1) ** 2
    rough = fractal(w, h, seed + 50, ((10, .6), (3, .4)))
    burn = np.clip(burn * (0.6 + 0.8 * rough), 0, 1)
    arr[:, :, 0] -= burn * 55
    arr[:, :, 1] -= burn * 70
    arr[:, :, 2] -= burn * 85
    # sombra del lomo + curvatura de la hoja
    g = x if gutter_side == "left" else (1 - x)
    gutter = np.exp(-g * w / K / 26.0) * 0.55 + np.exp(-g * w / K / 90.0) * 0.18
    arr[:, :, :3] *= (1 - gutter)[:, :, None] if gutter.ndim == 2 else (1 - gutter)[..., None]
    hilite = np.exp(-((g - 0.32) ** 2) / 0.02) * 0.04
    arr[:, :, :3] *= (1 + hilite)[..., None]
    return arr

def round_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return m

def apply_mask(img, m):
    a = np.array(img).astype(float)
    a[:, :, 3] *= np.array(m).astype(float) / 255.0
    return to_img(a)

def shadow(size, box, radius, blur, alpha=150, off=(0, 0)):
    s = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(s).rounded_rectangle([box[0] + off[0], box[1] + off[1], box[2] + off[0], box[3] + off[1]], radius=radius, fill=(0, 0, 0, alpha))
    return s.filter(ImageFilter.GaussianBlur(blur))

def stitch(d, box, r, color, dash=7, gap=5, width=2):
    x0, y0, x1, y1 = box
    # rectángulo redondeado discontinuo (aprox. por tramos rectos)
    segs = [((x0 + r, y0), (x1 - r, y0)), ((x1, y0 + r), (x1, y1 - r)), ((x1 - r, y1), (x0 + r, y1)), ((x0, y1 - r), (x0, y0 + r))]
    for (ax, ay), (bx, by) in segs:
        L = math.hypot(bx - ax, by - ay)
        t = 0.0
        while t < L:
            t2 = min(L, t + dash)
            d.line([(ax + (bx - ax) * t / L, ay + (by - ay) * t / L), (ax + (bx - ax) * t2 / L, ay + (by - ay) * t2 / L)], fill=color, width=width)
            t += dash + gap

def corner_guard(img, corner, size):
    """Cantonera de latón en una esquina del libro."""
    W, H = img.size
    g = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(g)
    poly = [(0, 0), (size, 0), (0, size)]
    gd.polygon(poly, fill=(176, 138, 62, 255))
    arr = np.array(g).astype(float)
    yy, xx = np.mgrid[0:size, 0:size]
    shade = 1.15 - 0.5 * (xx + yy) / size
    arr[:, :, :3] *= shade[:, :, None]
    g = to_img(arr)
    gd = ImageDraw.Draw(g)
    gd.line([(size * 0.12, size * 0.82), (size * 0.82, size * 0.12)], fill=(110, 80, 30, 255), width=k(1.5))
    for (px, py) in ((size * 0.2, size * 0.2), (size * 0.45, size * 0.14), (size * 0.14, size * 0.45)):
        rr = k(2.6)
        gd.ellipse([px - rr, py - rr, px + rr, py + rr], fill=(230, 200, 120, 255), outline=(90, 64, 24, 255), width=k(0.8))
    if corner == "tr": g = g.transpose(Image.FLIP_LEFT_RIGHT)
    if corner == "bl": g = g.transpose(Image.FLIP_TOP_BOTTOM)
    if corner == "br": g = g.transpose(Image.ROTATE_180)
    pos = {"tl": (0, 0), "tr": (W - size, 0), "bl": (0, H - size), "br": (W - size, H - size)}[corner]
    img.alpha_composite(g, pos)

def page_block(img, page, side):
    """Grosor del bloque de hojas: varias láminas desplazadas hacia fuera y abajo."""
    x0, y0, x1, y1 = page
    for i in range(5, 0, -1):
        dx = (-i if side == "left" else i) * 1.6
        dy = i * 1.4
        col = (214 - i * 9, 198 - i * 10, 160 - i * 10, 255)
        lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(lay).rounded_rectangle(kb((x0 + dx, y0 + dy * 0.4, x1 + dx, y1 + dy)), radius=k(4), fill=col, outline=(150, 128, 92, 255), width=1)
        img.alpha_composite(lay)

# ---------------------------------------------------------------- doble página
W, H = k(BW), k(BH)
spread = Image.new("RGBA", (W, H), (0, 0, 0, 0))
spread.alpha_composite(shadow((W, H), [k(10), k(14), W - k(10), H - k(2)], k(26), k(10), 170, (0, k(6))))
cov = to_img(vignette(leather(W, H, (62, 58, 38), 3), 0.5))
cov = apply_mask(cov, round_mask(W, H, k(22)))
spread.alpha_composite(cov)
d = ImageDraw.Draw(spread)
stitch(d, kb((12, 10, BW - 12, BH - 10)), k(16), (190, 160, 96, 200), dash=k(7), gap=k(5), width=k(1.6))
# lomo
sp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
spd = ImageDraw.Draw(sp)
spd.rectangle(kb((SPINE - 16, 0, SPINE + 16, BH)), fill=(26, 24, 16, 160))
sp = sp.filter(ImageFilter.GaussianBlur(k(6)))
spread.alpha_composite(sp)
for c in ("tl", "tr", "bl", "br"):
    corner_guard(spread, c, k(46))
page_block(spread, LP, "left")
page_block(spread, RP, "right")
for page, side, seed in ((LP, "right", 11), (RP, "left", 12)):
    x0, y0, x1, y1 = kb(page)
    p = to_img(parchment(x1 - x0, y1 - y0, seed, side))
    p = apply_mask(p, round_mask(x1 - x0, y1 - y0, k(4)))
    p.save(f"{OUT}/book_page_{'left' if side == 'right' else 'right'}.png")
    spread.alpha_composite(p, (x0, y0))
# sombra central (pliegue)
fold = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(fold).rectangle(kb((SPINE - 3, 26, SPINE + 3, 570)), fill=(40, 28, 14, 200))
spread.alpha_composite(fold.filter(ImageFilter.GaussianBlur(k(2.5))))
spread.save(f"{OUT}/book_spread.png")

# ---------------------------------------------------------------- portada cerrada (mitad derecha + lomo)
CW, CH = k(BW - SPINE + 24), k(BH)
cover = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
cover.alpha_composite(shadow((CW, CH), [k(6), k(10), CW - k(8), CH - k(2)], k(22), k(9), 170, (k(4), k(6))))
# páginas asomando por el borde
ImageDraw.Draw(cover).rounded_rectangle(kb((30, 18, BW - SPINE + 24 - 6, BH - 14)), radius=k(6), fill=(222, 206, 166, 255), outline=(150, 128, 92, 255), width=k(1))
lc = to_img(vignette(leather(CW - k(12), CH - k(8), (66, 61, 40), 7), 0.55))
lc = apply_mask(lc, round_mask(CW - k(12), CH - k(8), k(20)))
cover.alpha_composite(lc, (0, 0))
cd = ImageDraw.Draw(cover)
# banda del lomo
band = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
bd = ImageDraw.Draw(band)
bd.rectangle(kb((0, 0, 34, BH - 4)), fill=(30, 28, 18, 150))
for yy in (70, 120, BH - 120, BH - 70):
    bd.rectangle(kb((4, yy - 4, 32, yy + 4)), fill=(150, 120, 60, 200))
cover.alpha_composite(band.filter(ImageFilter.GaussianBlur(k(1.2))))
stitch(cd, kb((48, 12, BW - SPINE + 24 - 26, BH - 16)), k(14), (190, 160, 96, 210), dash=k(7), gap=k(5), width=k(1.6))
for c in ("tr", "br"):
    corner_guard(cover, c, k(46))
# Marco dorado repujado
def gold_text(img, xy, text, font, fill=(222, 182, 92, 255), anchor="mm"):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((xy[0] + k(1.5), xy[1] + k(2)), text, font=font, fill=(10, 8, 4, 200), anchor=anchor)
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(k(1.2))))
    hi = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(hi).text((xy[0] - k(0.6), xy[1] - k(0.8)), text, font=font, fill=(255, 236, 170, 200), anchor=anchor)
    img.alpha_composite(hi)
    ImageDraw.Draw(img).text(xy, text, font=font, fill=fill, anchor=anchor)

cx = (k(34) + CW - k(12)) // 2
fr = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
fd = ImageDraw.Draw(fr)
fd.rounded_rectangle(kb((78, 50, BW - SPINE + 24 - 58, BH - 54)), radius=k(10), outline=(196, 158, 76, 255), width=k(2.5))
fd.rounded_rectangle(kb((88, 60, BW - SPINE + 24 - 68, BH - 64)), radius=k(8), outline=(150, 118, 54, 255), width=k(1))
cover.alpha_composite(fr)
# Emblema: estrella en círculo con alas
em_y = k(230)
emb = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
ed = ImageDraw.Draw(emb)
R = k(62)
ed.ellipse([cx - R, em_y - R, cx + R, em_y + R], outline=(208, 168, 82, 255), width=k(5))
ed.ellipse([cx - R + k(10), em_y - R + k(10), cx + R - k(10), em_y + R - k(10)], outline=(160, 124, 56, 255), width=k(1.5))
pts = []
for i in range(10):
    a = -math.pi / 2 + i * math.pi / 5
    rr = R * 0.72 if i % 2 == 0 else R * 0.3
    pts.append((cx + rr * math.cos(a), em_y + rr * math.sin(a)))
ed.polygon(pts, fill=(214, 174, 86, 255))
for sgn in (-1, 1):
    for j in range(3):
        x0 = cx + sgn * (R + k(8) + j * k(14))
        ed.polygon([(x0, em_y - k(10) + j * k(3)), (x0 + sgn * k(26), em_y - k(16) + j * k(5)), (x0 + sgn * k(20), em_y + k(2)), (x0, em_y + k(4))], fill=(196, 158, 76, 255))
sh = emb.copy()
sh_arr = np.array(sh).astype(float); sh_arr[:, :, :3] = 8
sh = to_img(sh_arr).filter(ImageFilter.GaussianBlur(k(1.5)))
cover.alpha_composite(sh, (k(1.5), k(2)))
cover.alpha_composite(emb)
fT = ImageFont.truetype(f"{FONTS}/Cinzel.ttf", k(52)); fT.set_variation_by_name("Bold")
fS = ImageFont.truetype(f"{FONTS}/EBGaramond-Italic.ttf", k(20))
fM = ImageFont.truetype(f"{FONTS}/Cinzel.ttf", k(13)); fM.set_variation_by_name("Bold")
gold_text(cover, (cx, k(372)), "CÓDICE", fT)
cd = ImageDraw.Draw(cover)
cd.line([cx - k(110), k(408), cx + k(110), k(408)], fill=(196, 158, 76, 255), width=k(1.5))
gold_text(cover, (cx, k(432)), "Manual de campo", fS, fill=(214, 182, 110, 255))
gold_text(cover, (cx, k(500)), "TROPAS EN MINIATURA", fM, fill=(186, 152, 84, 255))
cover.save(f"{OUT}/book_cover.png")
print("ok")
