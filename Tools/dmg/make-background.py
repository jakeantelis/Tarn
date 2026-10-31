# Draws the disk image background to match Tarn's calm Breathe look (run once; the PNGs and TIFF are committed).
# Needs Pillow. The mid tone blue keeps Finder's icon labels readable in both light and dark appearance.
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os, subprocess
W, H = 660, 400
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

    cx, cy = w / 2, 70 * scale
    # a gentle glow behind the flower
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for r in range(150 * scale, 0, -3 * scale):
        a = int(70 * (1 - r / (150 * scale)) ** 2)
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 226, 196, a))
    im = Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(8 * scale)))

    # ripples, like the full screen Breathe view: faint rings on their own layer so the alpha blends
    rings = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rings)
    for k, rr in enumerate((46, 62)):
        r = rr * scale
        rd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(235, 242, 255, 60 - k * 20), width=scale)
    im = Image.alpha_composite(im, rings)

    # the flower: overlapping translucent petals in the Breathe colors
    petals = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pd = ImageDraw.Draw(petals)
    cols = [(244, 214, 168, 120), (226, 178, 206, 120)]
    n = 10
    for k in range(n):
        ang = k / n * 2 * math.pi
        length, width = 34 * scale, 11 * scale
        pt = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(pt).ellipse([cx - width, cy - length - 6 * scale, cx + width, cy + 4 * scale], fill=cols[k % 2])
        pt = pt.rotate(-math.degrees(ang), center=(cx, cy), resample=Image.BICUBIC)
        petals = Image.alpha_composite(petals, pt)
    im = Image.alpha_composite(im, petals)
    d = ImageDraw.Draw(im, "RGBA")
    r = 5 * scale
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 240, 214, 235))

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
    centered("Drag Tarn into Applications", 132, font(25), (255, 255, 255, 240), tracking=0.8)
    centered("Then open Tarn. Look for the small flower in your menu bar.", 172, font(14, italic=True), (236, 242, 252, 215), tracking=0.2)

    # a quiet arrow between the two icons
    y = 270 * scale
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
