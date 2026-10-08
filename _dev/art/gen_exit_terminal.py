# Cartel de SALIDA (vuelve al menú) y marco del terminal de especialidades.
import numpy as np, math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont
OUT, FONTS = sys.argv[1], sys.argv[2]
K = 2
def k(v): return int(round(v * K))

# ------------------------------------------------ cartel de salida 200×84 (coords de la sala)
W, H = 200, 84
img = Image.new("RGBA", (k(W), k(H)), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
# soportes al techo
for x in (40, 160):
    d.rectangle([k(x - 2), 0, k(x + 2), k(14)], fill=(50, 56, 64, 255))
# halo verde
glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
ImageDraw.Draw(glow).rounded_rectangle([k(6), k(12), k(W - 6), k(H - 6)], radius=k(8), fill=(40, 255, 120, 120))
img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(k(6))))
d = ImageDraw.Draw(img)
d.rounded_rectangle([k(10), k(14), k(W - 10), k(H - 10)], radius=k(6), fill=(36, 42, 48, 255))
d.rounded_rectangle([k(14), k(18), k(W - 14), k(H - 14)], radius=k(4), fill=(18, 160, 80, 255))
# brillo interior (luz desde dentro)
pan = Image.new("RGBA", img.size, (0, 0, 0, 0))
ImageDraw.Draw(pan).rounded_rectangle([k(20), k(22), k(W - 20), k(40)], radius=k(3), fill=(140, 255, 180, 70))
img.alpha_composite(pan.filter(ImageFilter.GaussianBlur(k(3))))
d = ImageDraw.Draw(img)
# pictograma: persona corriendo hacia una puerta (genérico) + flecha izquierda
ink = (235, 255, 240, 255)
# puerta
d.rectangle([k(24), k(26), k(44), k(62)], outline=ink, width=k(2.5))
# figura
cx, cy = 58, 34
d.ellipse([k(cx - 4), k(cy - 8), k(cx + 4), k(cy)], fill=ink)
d.line([(k(cx), k(cy + 1)), (k(cx - 3), k(cy + 14))], fill=ink, width=k(4))              # tronco
d.line([(k(cx - 3), k(cy + 14)), (k(cx - 11), k(cy + 22)), (k(cx - 14), k(cy + 21))], fill=ink, width=k(3.5))
d.line([(k(cx - 3), k(cy + 14)), (k(cx + 4), k(cy + 20)), (k(cx + 3), k(cy + 28))], fill=ink, width=k(3.5))
d.line([(k(cx - 1), k(cy + 4)), (k(cx - 9), k(cy + 8))], fill=ink, width=k(3))
d.line([(k(cx - 1), k(cy + 4)), (k(cx + 7), k(cy + 9))], fill=ink, width=k(3))
f = ImageFont.truetype(f"{FONTS}/Cinzel.ttf", k(19)); f.set_variation_by_name("Bold")
d.text((k(122), k(37)), "SALIDA", font=f, fill=ink, anchor="mm")
fs = ImageFont.truetype(f"{FONTS}/ShareTechMono.ttf", k(10))
d.text((k(122), k(54)), "◄ MENÚ PRINCIPAL", font=fs, fill=(200, 255, 215, 255), anchor="mm")
img.resize((W, H), Image.LANCZOS).save(f"{OUT}/exit_sign.png")

# ------------------------------------------------ marco del terminal 1040×620, pantalla (44,48)-(996,548)
W, H = 1040, 620
SX0, SY0, SX1, SY1 = 44, 48, 996, 548
img = Image.new("RGBA", (k(W), k(H)), (0, 0, 0, 0))
sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
ImageDraw.Draw(sh).rounded_rectangle([k(14), k(20), k(W - 14), k(H - 2)], radius=k(30), fill=(0, 0, 0, 190))
img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(k(10))))
# carcasa metálica con degradado vertical + ruido
body = np.zeros((k(H), k(W), 4))
t = np.linspace(0, 1, k(H))[:, None]
r = np.random.default_rng(3).random((k(H), k(W)))
base = 62 - 26 * t
body[:, :, 0] = base + 4 + r * 6
body[:, :, 1] = base + 8 + r * 6
body[:, :, 2] = base + 10 + r * 6
body[:, :, 3] = 255
bimg = Image.fromarray(np.clip(body, 0, 255).astype(np.uint8), "RGBA")
m = Image.new("L", img.size, 0)
ImageDraw.Draw(m).rounded_rectangle([k(8), k(8), k(W - 8), k(H - 8)], radius=k(28), fill=255)
img.paste(bimg, (0, 0), m)
d = ImageDraw.Draw(img)
d.rounded_rectangle([k(8), k(8), k(W - 8), k(H - 8)], radius=k(28), outline=(120, 132, 146, 255), width=k(2))
d.rounded_rectangle([k(16), k(16), k(W - 16), k(H - 16)], radius=k(22), outline=(20, 24, 30, 255), width=k(2))
# franjas de peligro a los lados de la placa
for i in range(10):
    x = 330 + i * 9
    d.polygon([(k(x), k(18)), (k(x + 5), k(18)), (k(x + 1), k(36)), (k(x - 4), k(36))], fill=(214, 168, 40, 255))
    x2 = 620 + i * 9
    d.polygon([(k(x2), k(18)), (k(x2 + 5), k(18)), (k(x2 + 1), k(36)), (k(x2 - 4), k(36))], fill=(214, 168, 40, 255))
d.rounded_rectangle([k(430), k(16), k(610), k(38)], radius=k(4), fill=(26, 30, 36, 255), outline=(150, 160, 172, 255), width=k(1))
fm = ImageFont.truetype(f"{FONTS}/ShareTechMono.ttf", k(12))
d.text((k(520), k(27)), "TERMINAL · ESPECIALIDADES", font=fm, fill=(214, 220, 228, 255), anchor="mm")
# tornillos
for (x, y) in ((30, 30), (W - 30, 30), (30, H - 30), (W - 30, H - 30)):
    d.ellipse([k(x - 7), k(y - 7), k(x + 7), k(y + 7)], fill=(150, 158, 168, 255), outline=(30, 34, 40, 255), width=k(1.2))
    d.line([(k(x - 4), k(y - 4)), (k(x + 4), k(y + 4))], fill=(50, 54, 60, 255), width=k(1.6))
# rebaje alrededor de la pantalla
d.rounded_rectangle([k(SX0 - 12), k(SY0 - 12), k(SX1 + 12), k(SY1 + 12)], radius=k(22), fill=(14, 16, 20, 255), outline=(90, 100, 112, 255), width=k(2))
# hueco de la pantalla (transparente)
hole = Image.new("L", img.size, 0)
ImageDraw.Draw(hole).rounded_rectangle([k(SX0), k(SY0), k(SX1), k(SY1)], radius=k(16), fill=255)
a = np.array(img); a[:, :, 3] = np.where(np.array(hole) > 0, 0, a[:, :, 3]); img = Image.fromarray(a)
d = ImageDraw.Draw(img)
# panel inferior: rejilla, leds
for i in range(14):
    x = 70 + i * 10
    d.rounded_rectangle([k(x), k(566), k(x + 5), k(592)], radius=k(2), fill=(18, 20, 24, 255))
for i, col in enumerate([(80, 255, 140), (80, 255, 140), (255, 180, 60)]):
    x = 250 + i * 22
    g = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse([k(x - 8), k(571), k(x + 8), k(587)], fill=col + (120,))
    img.alpha_composite(g.filter(ImageFilter.GaussianBlur(k(3))))
    ImageDraw.Draw(img).ellipse([k(x - 4), k(575), k(x + 4), k(583)], fill=col + (255,))
d = ImageDraw.Draw(img)
d.text((k(520), k(580)), "MANDO CENTRAL · MÓDULO DE ADIESTRAMIENTO", font=ImageFont.truetype(f"{FONTS}/ShareTechMono.ttf", k(11)), fill=(140, 150, 162, 255), anchor="mm")
img.resize((W, H), Image.LANCZOS).save(f"{OUT}/terminal_frame.png")
print("ok")
