# Draws the disk image background to match Tarn's calm Breathe look (run once; the PNGs and TIFF are committed).
# Needs Pillow. The mid tone blue keeps Finder's icon labels readable in both light and dark appearance.
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os, subprocess
W, H = 660, 440
S = 2   # draw once at 2x, then also make the 1x version

def make(scale):
    w, h = W * scale, H * scale
    # soft vertical dusk gradient
    top, bot = (112, 138, 176), (66, 90, 128)
    base = Image.new("RGB", (w, h))
    px = base.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        for x in range(w): px[x, y] = c
    im = base.convert("RGBA")

    cx, cy = w / 2, 100 * scale
    # a warm glow and one faint ripple behind the flower (kept well clear of the text below)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for r in range(110 * scale, 0, -3 * scale):
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(250, 206, 170, int(60 * (1 - r / (110 * scale)) ** 2)))
    im = Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(8 * scale)))
    ring = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    r0 = 70 * scale
    ImageDraw.Draw(ring).ellipse([cx - r0, cy - r0, cx + r0, cy + r0], outline=(235, 242, 255, 55), width=scale)
    im = Image.alpha_composite(im, ring)

    # soft light halos behind the two icons, so the dark app icon stands out clearly against the blue
    halo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    for hx in (170, 490):
        for r in range(96 * scale, 0, -2 * scale):
            hd.ellipse([hx * scale - r, 312 * scale - r, hx * scale + r, 312 * scale + r],
                       fill=(240, 246, 255, int(120 * (1 - r / (96 * scale)) ** 1.4)))
    im = Image.alpha_composite(im, halo.filter(ImageFilter.GaussianBlur(5 * scale)))

    # the flower, drawn like the app icon: layered outlined petals in blue, rose and gold, with a warm centre.
    # Drawn at 3x and shrunk, so the edges are smooth.
    SS = 3
    fw, fh, fcx, fcy = w * SS, h * SS, cx * SS, cy * SS
    def petal_layer(n, length, width, fill, outline, offset=0.0):
        layer = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        for k in range(n):
            ang = (k + offset) / n * 360
            pt = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
            ImageDraw.Draw(pt).ellipse([fcx - width, fcy - length, fcx + width, fcy], fill=fill, outline=outline, width=int(1.6 * scale * SS))
            layer = Image.alpha_composite(layer, pt.rotate(-ang, center=(fcx, fcy), resample=Image.BICUBIC))
        return layer
    u = scale * SS
    flower = petal_layer(8, 58 * u, 15 * u, (150, 178, 226, 110), (205, 222, 252, 240))
    flower = Image.alpha_composite(flower, petal_layer(8, 44 * u, 12 * u, (226, 168, 204, 125), (250, 210, 228, 240), offset=0.5))
    flower = Image.alpha_composite(flower, petal_layer(8, 29 * u, 9 * u, (248, 214, 150, 140), (255, 234, 180, 245)))
    for r in range(14 * u, 0, -1):
        heart = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        ImageDraw.Draw(heart).ellipse([fcx - r, fcy - r, fcx + r, fcy + r], fill=(255, 214, 162, int(60 + 120 * (1 - r / (14 * u)))))
        flower = Image.alpha_composite(flower, heart)
    im = Image.alpha_composite(im, flower.resize((w, h), Image.LANCZOS))
    d = ImageDraw.Draw(im, "RGBA")

    # A soft, readable serif like the one the app uses for its breathing cues, spaced out a little, so the words feel soft.
    def font(size, italic=False):
        return ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia Italic.ttf" if italic else "/System/Library/Fonts/Supplemental/Georgia.ttf", size * scale)
    def centered(text, y, f, fill, tracking=0.0):
        widths = [d.textlength(ch, font=f) for ch in text]
        total = sum(widths) + tracking * scale * (len(text) - 1)
        x = (w - total) / 2
        for ch, cw in zip(text, widths):
            d.text((x, y * scale), ch, font=f, fill=fill)
            x += cw + tracking * scale
    centered("Double click Tarn to install it", 196, font(25), (255, 255, 255, 240), tracking=0.8)
    centered("It moves into Applications and opens by itself. Or drag it across.", 234, font(14, italic=True), (236, 242, 252, 215), tracking=0.2)

    # a quiet arrow between the two icons
    y = 312 * scale
    x0, x1 = 268 * scale, 392 * scale
    arrow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arrow)
    ad.line([(x0, y), (x1, y)], fill=(255, 255, 255, 150), width=2 * scale)
    ad.line([(x1 - 11 * scale, y - 9 * scale), (x1, y), (x1 - 11 * scale, y + 9 * scale)], fill=(255, 255, 255, 150), width=2 * scale, joint="curve")
    im = Image.alpha_composite(im, arrow)
    return im.convert("RGB")

here = os.path.dirname(os.path.abspath(__file__))
make(1).save(f"{here}/background.png")
make(2).save(f"{here}/background@2x.png")
subprocess.check_call(["tiffutil", "-cathidpicheck", f"{here}/background.png", f"{here}/background@2x.png", "-out", f"{here}/background.tiff"])
