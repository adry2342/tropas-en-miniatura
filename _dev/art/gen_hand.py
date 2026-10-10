"""Puño del soldado (mismo estilo que el sprite: trazo grueso oscuro y colores planos).
Visto de lado: muñeca a la izquierda, nudillos a la derecha, pulgar arriba.
Sale a la mitad de escala del sprite original (como las demás piezas). Centro = punto de agarre.
Uso: python gen_hand.py <out_dir>"""
import sys
from PIL import Image, ImageDraw
OUT = sys.argv[1]
SS = 4                      # supermuestreo
N = 104                     # lienzo final (px, escala de pieza)
OUTL = (34, 20, 14, 255)
SKIN = (226, 147, 100, 255)
SHADE = (196, 116, 76, 255)
CREASE = (150, 82, 52, 255)
LW = 9                      # trazo (px de pieza)

def S(*v): return [x * SS for x in v]

def fist(back=False):
    im = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    skin = (214, 136, 92, 255) if back else SKIN
    shade = (184, 106, 68, 255) if back else SHADE
    # silueta: cuerpo del puño + pulgar
    body = S(18, 24, 90, 84)
    thumb = S(14, 14, 62, 46)
    for box, r in ((body, 26), (thumb, 16)):
        d.rounded_rectangle([box[0] - LW * SS, box[1] - LW * SS, box[2] + LW * SS, box[3] + LW * SS], radius=(r + LW) * SS, fill=OUTL)
    d.rounded_rectangle(body, radius=26 * SS, fill=skin)
    # sombra inferior
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ds = ImageDraw.Draw(sh)
    ds.rounded_rectangle(body, radius=26 * SS, fill=shade)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rectangle(S(0, 66, N, N), fill=255)
    im.paste(sh, (0, 0), Image.composite(sh, Image.new("RGBA", im.size), mask).getchannel("A"))
    d = ImageDraw.Draw(im)
    # dedos: pliegues en la parte delantera
    for y in (44, 57, 70):
        d.line(S(66, y, 86, y), fill=CREASE, width=4 * SS)
        d.ellipse(S(84, y - 2, 88, y + 2), fill=CREASE)
    # pulgar por encima (con su contorno inferior)
    d.rounded_rectangle(thumb, radius=16 * SS, fill=skin)
    d.arc(S(14, 18, 62, 48), 25, 155, fill=OUTL, width=5 * SS)
    return im.resize((N, N), Image.LANCZOS)

fist(False).save(f"{OUT}/hand_front.png")
fist(True).save(f"{OUT}/hand_back.png")
