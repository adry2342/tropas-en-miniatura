# Cámaras criogénicas (capa de atrás + cristal delantero), 212×458, perspectiva coherente:
# todas las elipses centradas en el mismo eje y con la misma proporción (vista ligeramente desde arriba).
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import sys, math
S = 4                     # supersampling
W, H = 212, 458
CX = 106
RATIO = 0.27              # alto/ancho de las elipses (misma cámara para todo)
PIPE_TOP = 38            # las tuberías salen de la barandilla de la pared (no tapan el letrero)

def big(v): return int(round(v * S))

def new(): return Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))

def ell_box(cx, cy, rx, ry=None):
    ry = rx * RATIO if ry is None else ry
    return [big(cx - rx), big(cy - ry), big(cx + rx), big(cy + ry)]

def vgrad(w, h, stops):
    """stops: [(t, (r,g,b,a))] → array h×w×4 vertical"""
    t = np.linspace(0, 1, h)[:, None]
    out = np.zeros((h, w, 4))
    ts = [s[0] for s in stops]
    for c in range(4):
        vals = [s[1][c] for s in stops]
        out[:, :, c] = np.interp(t, ts, vals)
    return out

def hshade(w, h, stops):
    t = np.linspace(0, 1, w)[None, :]
    out = np.zeros((h, w, 4))
    ts = [s[0] for s in stops]
    for c in range(4):
        out[:, :, c] = np.interp(t, ts, [s[1][c] for s in stops])
    return out

def paste_masked(img, arr, mask):
    """arr: H×W×4 float (0..255) full size; mask: L image same size"""
    layer = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    m = np.array(mask).astype(float) / 255.0
    a = np.array(layer).astype(float)
    a[:, :, 3] *= m
    layer = Image.fromarray(a.astype(np.uint8), "RGBA")
    img.alpha_composite(layer)

def cyl_mask(cx, y_top, y_bot, rx, ry=None):
    """Cilindro: elipse arriba + rectángulo + elipse abajo"""
    ry = rx * RATIO if ry is None else ry
    m = Image.new("L", (W * S, H * S), 0)
    d = ImageDraw.Draw(m)
    d.rectangle([big(cx - rx), big(y_top), big(cx + rx), big(y_bot)], fill=255)
    d.ellipse(ell_box(cx, y_bot, rx, ry), fill=255)
    d.ellipse(ell_box(cx, y_top, rx, ry), fill=255)
    return m

def ell_mask(cx, cy, rx, ry=None):
    m = Image.new("L", (W * S, H * S), 0)
    ImageDraw.Draw(m).ellipse(ell_box(cx, cy, rx, ry), fill=255)
    return m

def metal_side(rx, base=(70, 78, 90), hi=(150, 160, 175), dark=(28, 32, 40)):
    """Sombreado horizontal de metal cilíndrico (luz desde arriba-izquierda)."""
    full = np.zeros((H * S, W * S, 4))
    x0, x1 = big(CX - rx), big(CX + rx)
    w = x1 - x0
    seg = hshade(w, H * S, [(0, dark + (255,)), (0.18, base + (255,)), (0.32, hi + (255,)),
                            (0.5, base + (255,)), (0.85, dark + (255,)), (1, (18, 20, 26, 255))])
    full[:, x0:x1] = seg
    return full

def arc(d, cx, cy, rx, start, end, fill, width, ry=None):
    d.arc(ell_box(cx, cy, rx, ry), start, end, fill=fill, width=big(width))

# ---------------------------------------------------------------- geometría
CAP_TOP, CAP_BOT, CAP_RX = 72, 104, 56
GL_TOP, GL_BOT, GL_RX = 106, 372, 50
BASE_TOP, BASE_BOT, BASE_RX = 377, 412, 58

def build_back():
    img = new()
    d = ImageDraw.Draw(img)
    # Tuberías del techo
    for px in (CX - 22, CX + 22):
        pm = Image.new("L", img.size, 0)
        ImageDraw.Draw(pm).rounded_rectangle([big(px - 6), big(PIPE_TOP), big(px + 6), big(CAP_TOP)], radius=big(2), fill=255)
        arr = np.zeros((H * S, W * S, 4))
        x0, x1 = big(px - 6), big(px + 6)
        arr[:, x0:x1] = hshade(x1 - x0, H * S, [(0, (30, 34, 42, 255)), (0.35, (120, 130, 145, 255)), (1, (26, 30, 38, 255))])
        paste_masked(img, arr, pm)
        for yy in (PIPE_TOP, PIPE_TOP + 18):
            d.rounded_rectangle([big(px - 8), big(yy), big(px + 8), big(yy + 5)], radius=big(1.5), fill=(52, 58, 68, 255))
    # Cable lateral (de la tapa a la base, por la derecha)
    cable = new()
    cd = ImageDraw.Draw(cable)
    pts = [(CX + CAP_RX - 6, CAP_BOT - 6)]
    for i in range(1, 21):
        t = i / 20
        y = (CAP_BOT - 6) + t * ((BASE_TOP + 6) - (CAP_BOT - 6))
        x = CX + CAP_RX - 4 + 4 * math.sin(t * math.pi)
        pts.append((x, y))
    cd.line([(big(x), big(y)) for x, y in pts], fill=(20, 22, 26, 255), width=big(5), joint="curve")
    cd.line([(big(x - 1), big(y)) for x, y in pts], fill=(150, 40, 36, 255), width=big(2), joint="curve")
    img.alpha_composite(cable)

    # Pared trasera del interior del cristal (oscura, teal) — todo el cilindro
    inner = cyl_mask(CX, GL_TOP, GL_BOT, GL_RX)
    arr = vgrad(W * S, H * S, [(0, (8, 30, 42, 255)), (GL_TOP / H, (10, 38, 54, 255)),
                                ((GL_TOP + 60) / H, (14, 62, 84, 255)), (GL_BOT / H, (22, 120, 150, 255)), (1, (22, 120, 150, 255))])
    shade = hshade(W * S, H * S, [(0, (0, 0, 0, 0)), (0.2, (0, 0, 0, 0)), (0.5, (0, 0, 0, 0)), (0.85, (0, 0, 0, 0)), (1, (0, 0, 0, 0))])
    # oscurecer bordes laterales (curvatura)
    xs = np.linspace(-1, 1, 2 * big(GL_RX))
    edge = np.clip(1 - 0.55 * (xs ** 4), 0, 1)
    x0 = big(CX - GL_RX)
    arr[:, x0:x0 + len(xs), :3] *= edge[None, :, None]
    paste_masked(img, arr, inner)
    # Costillas verticales de la pared trasera
    for k in range(-3, 4):
        x = CX + GL_RX * 0.8 * math.sin(k * 0.42)
        d.line([big(x), big(GL_TOP + 16), big(x), big(GL_BOT - 4)], fill=(60, 170, 200, 40), width=big(1.2))
    # Luz que sube desde la base (halo)
    glow = new()
    gd = ImageDraw.Draw(glow)
    gd.ellipse(ell_box(CX, GL_BOT - 30, GL_RX - 6, 70), fill=(80, 220, 255, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(big(16)))
    m = inner
    ga = np.array(glow).astype(float)
    ga[:, :, 3] *= np.array(m) / 255.0
    img.alpha_composite(Image.fromarray(ga.astype(np.uint8)))
    # Burbujas
    rng = np.random.default_rng(7)
    for _ in range(14):
        bx = CX + rng.uniform(-GL_RX * 0.75, GL_RX * 0.75)
        by = rng.uniform(GL_TOP + 40, GL_BOT - 20)
        r = rng.uniform(1.2, 3.0)
        d.ellipse([big(bx - r), big(by - r), big(bx + r), big(by + r)], outline=(170, 240, 255, 110), width=big(0.8))
    # Arco trasero del aro superior e inferior del cristal (mitad de atrás)
    arc(d, CX, GL_TOP, GL_RX, 180, 360, (90, 104, 120, 255), 4)
    arc(d, CX, GL_BOT, GL_RX, 180, 360, (60, 200, 230, 200), 3)

    # ---------------- Base (cilindro) ----------------
    bm = cyl_mask(CX, BASE_TOP, BASE_BOT, BASE_RX)
    paste_masked(img, metal_side(BASE_RX, base=(54, 60, 70), hi=(110, 120, 134), dark=(22, 25, 31)), bm)
    # cara superior de la base
    top = ell_mask(CX, BASE_TOP, BASE_RX)
    paste_masked(img, vgrad(W * S, H * S, [(0, (70, 78, 90, 255)), (1, (70, 78, 90, 255))]), top)
    d.ellipse(ell_box(CX, BASE_TOP, BASE_RX), outline=(120, 130, 145, 255), width=big(1.5))
    # Plataforma luminosa (disco) dentro del cristal
    disc = new()
    dd = ImageDraw.Draw(disc)
    dd.ellipse(ell_box(CX, GL_BOT, GL_RX - 2), fill=(30, 110, 140, 255))
    dd.ellipse(ell_box(CX, GL_BOT, GL_RX - 14), fill=(70, 200, 235, 255))
    dd.ellipse(ell_box(CX, GL_BOT - 1, GL_RX - 30), fill=(170, 245, 255, 255))
    disc = disc.filter(ImageFilter.GaussianBlur(big(1.2)))
    img.alpha_composite(disc)
    d.ellipse(ell_box(CX, GL_BOT, GL_RX), outline=(110, 235, 255, 255), width=big(2))
    # Zócalo inferior (rejillas)
    for i in range(5):
        x = CX - 20 + i * 10
        d.rounded_rectangle([big(x - 3), big(BASE_BOT + 6), big(x + 3), big(BASE_BOT + 14)], radius=big(1), fill=(14, 16, 20, 255))
    # Placa CRIO + luz de estado
    d.rounded_rectangle([big(CX - 50), big(BASE_TOP + 22), big(CX - 20), big(BASE_TOP + 36)], radius=big(2), fill=(206, 160, 40, 255))
    try:
        f = ImageFont.truetype("DejaVuSans-Bold.ttf", big(7))
    except Exception:
        f = ImageFont.load_default()
    d.text((big(CX - 35), big(BASE_TOP + 28)), "CRIO", font=f, fill=(30, 24, 8, 255), anchor="mm")
    d.ellipse([big(CX + 28), big(BASE_TOP + 24), big(CX + 36), big(BASE_TOP + 32)], fill=(70, 230, 110, 255))
    # brillo de la luz verde
    gl = new()
    ImageDraw.Draw(gl).ellipse([big(CX + 24), big(BASE_TOP + 20), big(CX + 40), big(BASE_TOP + 36)], fill=(70, 255, 120, 110))
    img.alpha_composite(gl.filter(ImageFilter.GaussianBlur(big(3))))

    # aro de neón bajo la tapa: la mitad de atrás queda tapada por la tapa; la delantera va en el cristal
    neon = new()
    ImageDraw.Draw(neon).arc(ell_box(CX, CAP_BOT + 2, CAP_RX - 6), 0, 360, fill=(90, 240, 255, 255), width=big(3))
    img.alpha_composite(neon.filter(ImageFilter.GaussianBlur(big(2.5))))
    img.alpha_composite(neon)
    # ---------------- Tapa superior (cilindro) ----------------
    cm = cyl_mask(CX, CAP_TOP, CAP_BOT, CAP_RX)
    paste_masked(img, metal_side(CAP_RX, base=(56, 62, 74), hi=(118, 128, 142), dark=(22, 25, 31)), cm)
    topm = ell_mask(CX, CAP_TOP, CAP_RX)
    paste_masked(img, vgrad(W * S, H * S, [(0, (40, 45, 54, 255)), ((CAP_TOP - 20) / H, (48, 54, 64, 255)),
                                            ((CAP_TOP + 22) / H, (80, 88, 100, 255)), (1, (80, 88, 100, 255))]), topm)
    d.ellipse(ell_box(CX, CAP_TOP, CAP_RX), outline=(130, 140, 155, 255), width=big(1.5))
    # cúpula interior + luz roja
    d.ellipse(ell_box(CX, CAP_TOP - 2, CAP_RX * 0.55), fill=(34, 38, 46, 255), outline=(90, 98, 110, 255), width=big(1))
    d.ellipse(ell_box(CX, CAP_TOP - 3, 9), fill=(220, 40, 40, 255))
    rl = new()
    ImageDraw.Draw(rl).ellipse(ell_box(CX, CAP_TOP - 3, 16), fill=(255, 60, 50, 140))
    img.alpha_composite(rl.filter(ImageFilter.GaussianBlur(big(3))))
    # remaches de la banda de la tapa
    for k in range(-5, 6):
        a = k / 6 * math.pi / 2
        x = CX + CAP_RX * 0.92 * math.sin(a)
        y = (CAP_TOP + CAP_BOT) / 2 + 4 + CAP_RX * RATIO * math.cos(a) * 0.9
        d.ellipse([big(x - 1.4), big(y - 1.4), big(x + 1.4), big(y + 1.4)], fill=(20, 22, 28, 255))
    # luz naranja lateral
    d.ellipse([big(CX - CAP_RX + 12), big(CAP_BOT - 4), big(CX - CAP_RX + 20), big(CAP_BOT + 4)], fill=(255, 150, 40, 255))
    return img

def build_front():
    img = new()
    d = ImageDraw.Draw(img)
    # Cristal delantero: mitad frontal del cilindro (de arco inferior a arco inferior)
    m = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(m)
    md.rectangle([big(CX - GL_RX), big(GL_TOP), big(CX + GL_RX), big(GL_BOT)], fill=255)
    md.ellipse(ell_box(CX, GL_BOT, GL_RX), fill=255)
    # recorta la mitad trasera del óvalo de arriba (el cristal empieza en el arco delantero)
    md.ellipse(ell_box(CX, GL_TOP, GL_RX), fill=0)
    md.rectangle([big(CX - GL_RX), 0, big(CX + GL_RX), big(GL_TOP)], fill=0)
    # quita la parte trasera del óvalo de abajo (por debajo solo queda el arco delantero)
    lower = Image.new("L", img.size, 0)
    ImageDraw.Draw(lower).rectangle([0, big(GL_BOT), W * S, H * S], fill=255)
    lm = np.array(lower) > 0
    # restituye el arco superior delantero (mitad de abajo del óvalo superior)
    up = Image.new("L", img.size, 0)
    ud = ImageDraw.Draw(up)
    ud.ellipse(ell_box(CX, GL_TOP, GL_RX), fill=255)
    ud.rectangle([0, 0, W * S, big(GL_TOP)], fill=0)
    um = np.array(up)
    mm = np.maximum(np.array(m), 0)
    mm = np.where(um > 0, 0, mm)
    mask = Image.fromarray(mm.astype(np.uint8))
    # color: tinte cian translúcido, más opaco en los bordes (fresnel)
    arr = np.zeros((H * S, W * S, 4))
    x0, x1 = big(CX - GL_RX), big(CX + GL_RX)
    xs = np.linspace(-1, 1, x1 - x0)
    fres = 0.10 + 0.45 * np.abs(xs) ** 3
    arr[:, x0:x1, 0] = 150
    arr[:, x0:x1, 1] = 225
    arr[:, x0:x1, 2] = 245
    arr[:, x0:x1, 3] = 255 * fres[None, :]
    paste_masked(img, arr, mask)
    # reflejos verticales
    hl = new()
    hd = ImageDraw.Draw(hl)
    def strip(xc, wdt, alpha, blur):
        layer = new()
        ImageDraw.Draw(layer).rectangle([big(xc - wdt / 2), big(GL_TOP + 14), big(xc + wdt / 2), big(GL_BOT - 6)], fill=(255, 255, 255, alpha))
        layer = layer.filter(ImageFilter.GaussianBlur(big(blur)))
        la = np.array(layer).astype(float)
        la[:, :, 3] *= np.array(mask) / 255.0
        img.alpha_composite(Image.fromarray(la.astype(np.uint8)))
    strip(CX - GL_RX * 0.52, 10, 120, 3)
    strip(CX - GL_RX * 0.38, 3, 150, 0.8)
    strip(CX + GL_RX * 0.62, 5, 60, 2)
    # Aro superior del cristal (arco delantero) y aro inferior, metálicos con remaches
    for cy in (GL_TOP, GL_BOT):
        d.arc(ell_box(CX, cy, GL_RX + 1), 0, 180, fill=(30, 34, 42, 255), width=big(7))
        d.arc(ell_box(CX, cy - 1, GL_RX + 1), 10, 170, fill=(120, 132, 148, 255), width=big(2))
        for k in range(-4, 5):
            a = k / 5 * math.pi / 2
            x = CX + GL_RX * math.sin(a)
            y = cy + GL_RX * RATIO * math.cos(a)
            d.ellipse([big(x - 1.3), big(y - 1.3), big(x + 1.3), big(y + 1.3)], fill=(150, 160, 175, 255))
    # Montantes laterales
    for sx in (-1, 1):
        x = CX + sx * (GL_RX - 1)
        d.rounded_rectangle([big(x - 3.5), big(GL_TOP - 2), big(x + 3.5), big(GL_BOT + 2)], radius=big(2), fill=(34, 38, 46, 255))
        d.line([big(x - 1.5 * sx), big(GL_TOP + 2), big(x - 1.5 * sx), big(GL_BOT - 2)], fill=(110, 122, 138, 255), width=big(1))
    # Media luna delantera del neón de la tapa (por delante del cristal)
    neon = new()
    ImageDraw.Draw(neon).arc(ell_box(CX, CAP_BOT + 2, CAP_RX - 6), 15, 165, fill=(110, 245, 255, 255), width=big(3))
    img.alpha_composite(neon.filter(ImageFilter.GaussianBlur(big(2.5))))
    img.alpha_composite(neon)
    return img

def down(img): return img.resize((W, H), Image.LANCZOS)

out = sys.argv[1]
back = down(build_back()); front = down(build_front())
back.save(out + "/cryo_tube_back.png"); front.save(out + "/cryo_tube_front.png")
comp = Image.new("RGBA", (W * 2 + 20, H), (30, 36, 44, 255))
b2 = back.copy(); comp.alpha_composite(b2, (0, 0)); comp.alpha_composite(front, (0, 0))
comp.alpha_composite(back, (W + 20, 0))
try:
    sp = Image.open(sys.argv[2]).convert("RGBA")
    sp.thumbnail((100, 180))
    comp.alpha_composite(sp, (W + 20 + 58 + (100 - sp.width) // 2, 175 + 180 - sp.height))
except Exception as e:
    print(e)
comp.alpha_composite(front, (W + 20, 0))
comp.save(out + "/cryo_preview.png")
print("ok")
