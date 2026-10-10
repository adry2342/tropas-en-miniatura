"""Limpia los restos de brazo bajo las mangas (piel y contorno sueltos) en body/sleeve_*.png.
Los brazos ahora se dibujan por código; sin esto asomaban trocitos cortados bajo la manga.
Uso: python clean_sleeves.py <Assets/Troop>"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

D = sys.argv[1]
# zonas (px de pieza) donde la piel es del brazo y no de la cara/cuello
ZONES = {
    "body.png": [(40, 392, 245, 480), (325, 388, 480, 480)],
    "sleeve_back.png": [(0, 0, 543, 724)],
    "sleeve_front.png": [(0, 0, 543, 724)],
}

def clean(name, zones):
    im = np.array(Image.open(f"{D}/{name}").convert("RGBA")).astype(int)
    r, g, b, a = im[..., 0], im[..., 1], im[..., 2], im[..., 3]
    zone = np.zeros(a.shape, bool)
    for x0, y0, x1, y1 in zones:
        zone[y0:y1, x0:x1] = True
    opaque = a > 40
    skin = opaque & (r > 110) & (r - g > 25) & (g - b > 5)
    dark = opaque & (r < 90) & (g < 70) & (b < 60)
    other = (a > 200) & ~skin & ~dark & ((r - g) < 10)  # tela, cinturón… (no mezclas con piel)
    near_other = ndimage.binary_dilation(other, iterations=5)
    kill = zone & (skin | (dark & ~near_other))
    # bordes semitransparentes de la piel eliminada
    kill |= zone & ndimage.binary_dilation(kill, iterations=1) & ~near_other & opaque
    kill |= zone & (a <= 40) & ~near_other          # halo casi transparente
    im[..., 3][kill] = 0
    Image.fromarray(im.astype(np.uint8)).save(f"{D}/{name}")
    print(name, int(kill.sum()), "px")

for n, z in ZONES.items():
    clean(n, z)


# El brazo trasero tapaba el extremo izquierdo del cinturón: se completa (cinturón que rodea la cadera)
# y se rellena el hueco entre la camiseta y el pantalón.
def patch_belt():
    from PIL import ImageDraw
    p = f"{D}/body.png"
    im = Image.open(p).convert("RGBA")
    SS = 4
    big = Image.new("RGBA", (im.width * SS, im.height * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    S = lambda pts: [(x * SS, y * SS) for x, y in pts]
    OUT = (34, 20, 14, 255)
    BELT = (88, 65, 48, 255)
    PANTS = (180, 160, 123, 255)
    d.polygon(S([(206, 484), (250, 484), (250, 500), (210, 500)]), fill=OUT)        # pantalón bajo el cinturón
    d.polygon(S([(212, 486), (250, 486), (250, 500), (214, 500)]), fill=PANTS)
    d.polygon(S([(213, 457), (250, 457), (250, 489), (205, 489)]), fill=OUT)        # cinturón
    d.polygon(S([(218, 462), (250, 462), (250, 484), (211, 484)]), fill=BELT)
    patch = big.resize(im.size, Image.LANCZOS)
    # solo se pinta donde no había ya pantalón/cinturón propios (a la izquierda de x = 248)
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rectangle([200, 450, 247, 500], fill=255)
    base = im.copy()
    base.alpha_composite(patch)
    im.paste(base, (0, 0), m)
    # agujeros en el contorno izquierdo del tronco (donde pasaba el brazo): se cierran con trazo
    px = im.load()
    for y in range(404, 440):
        xs = [x for x in range(214, 246) if px[x, y][3] > 120]
        if xs:
            for x in range(xs[0], xs[-1]):
                if px[x, y][3] < 200:
                    px[x, y] = (34, 20, 14, 255)
    im.save(p)
    print("belt patched")


patch_belt()
