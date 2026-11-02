#!/usr/bin/env python3
"""Makes the Dock icon choices in Resources/Icons from full-size square icon art.
Usage: Tools/make-icon-variants.py <folder with slate.png sage.png dusk.png sand.png night.png>
Each is placed on the same soft tile and shadow as the standard Tarn icon."""
import sys
from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
def tile(art):
    s = SIZE
    inset = round(s * 0.06)
    inner = s - 2 * inset
    art = art.convert("RGBA").resize((inner * 4, inner * 4), Image.LANCZOS)
    mask = Image.new("L", art.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, art.width - 1, art.height - 1), radius=round(art.width * 0.215), fill=255)
    art.putalpha(mask)
    art = art.resize((inner, inner), Image.LANCZOS)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (inset, inset + round(s * 0.012)), art.getchannel("A"))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(s * 0.015)))
    out.alpha_composite(art, (inset, inset))
    return out

src = sys.argv[1]
for name in ("slate", "sage", "dusk", "sand", "night"):
    tile(Image.open(f"{src}/{name}.png")).save(f"Resources/Icons/{name}.png", optimize=True)
