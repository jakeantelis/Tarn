# Draws the disk image background (run once; the PNG and TIFF are committed). Needs Pillow.
from PIL import Image, ImageDraw, ImageFont
import subprocess, os
W, H = 660, 400
def draw(scale):
    w, h = W * scale, H * scale
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        t = y / h
        c = (int(236 - 26 * t), int(242 - 22 * t), int(248 - 14 * t))
        for x in range(w): px[x, y] = c
    d = ImageDraw.Draw(im)
    f = lambda size, bold=False: ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size * scale, index=1 if bold else 0)
    ink, soft = (40, 58, 82), (92, 110, 134)
    def centered(text, y, font, fill):
        d.text(((w - d.textlength(text, font=font)) / 2, y * scale), text, font=font, fill=fill)
    centered("Drag Tarn into Applications", 34, f(26, True), ink)
    centered("Then open Tarn. Look for the small flower in your menu bar.", 72, f(14), soft)
    # arrow between the two icons
    y = 215 * scale
    d.line([(262 * scale, y), (392 * scale, y)], fill=(79, 120, 168), width=5 * scale)
    d.polygon([(402 * scale, y), (382 * scale, y - 14 * scale), (382 * scale, y + 14 * scale)], fill=(79, 120, 168))
    centered("Free and open source. No account, no tracking.", 352, f(12), soft)
    return im
here = os.path.dirname(os.path.abspath(__file__))
draw(1).save(f"{here}/background.png")
draw(2).save(f"{here}/background@2x.png")
subprocess.check_call(["tiffutil", "-cathidpicheck", f"{here}/background.png", f"{here}/background@2x.png", "-out", f"{here}/background.tiff"])
