"""Monta hojas de fotogramas a partir de _dev/art_tmp/motion/f_XX.png (de _dev/motion_preview.tscn).
Uso (desde _dev/art_tmp/motion): python ../../art/motion_sheet.py <situaciones,separadas,por,comas> <cada_n_fotogramas> <salida.png>"""
import sys
from PIL import Image, ImageDraw
CW, CH = 215, 212
names = ["apunta arriba","apunta abajo","anda","dispara","recarga","cambia arma","granada","muere","pistola anda+disp","cuchillo","bazuca","escopeta anda","enemigo anda","jefe anda"]
frames = [Image.open("f_%02d.png" % i).convert("RGB") for i in range(16)]
k = frames[0].height / 648.0
frames = [f.resize((round(f.width / k), round(f.height / k)), Image.LANCZOS) for f in frames]
idx = [int(a) for a in sys.argv[1].split(",")]
pick = list(range(0, 16, int(sys.argv[2]) if len(sys.argv) > 2 else 1))
out = Image.new("RGB", (len(pick) * CW + 120, len(idx) * CH), (40, 40, 40))
d = ImageDraw.Draw(out)
for r, s in enumerate(idx):
    col, row = s % 5, s // 5
    for c, f in enumerate(pick):
        out.paste(frames[f].crop((col * CW, row * CH, col * CW + CW, row * CH + CH)), (120 + c * CW, r * CH))
    d.text((4, r * CH + 90), names[s], fill=(255, 255, 255))
out.save(sys.argv[3] if len(sys.argv) > 3 else "../sheet.png")
