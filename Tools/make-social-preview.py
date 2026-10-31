# Draws docs/images/social-preview.png (1280 by 640), the image to upload as the repository's social preview. Needs Pillow.
from PIL import Image, ImageDraw, ImageFont, ImageFilter
W, H = 1280, 640
top, bot = (112, 138, 176), (58, 80, 118)
im = Image.new("RGB", (W, H)); px = im.load()
for y in range(H):
    t = y / (H - 1); c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    for x in range(W): px[x, y] = c
im = im.convert("RGBA")
cx, cy = 330, 320
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0)); gd = ImageDraw.Draw(glow)
for r in range(260, 0, -4): gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(250, 206, 170, int(70 * (1 - r / 260) ** 2)))
im = Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(16)))
SS = 3; fw, fh = W * SS, H * SS; fcx, fcy = cx * SS, cy * SS
def petals(n, L, Wd, fill, outline, off=0.0):
    layer = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    for k in range(n):
        pt = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        ImageDraw.Draw(pt).ellipse([fcx - Wd, fcy - L, fcx + Wd, fcy], fill=fill, outline=outline, width=5 * SS)
        layer = Image.alpha_composite(layer, pt.rotate(-(k + off) / n * 360, center=(fcx, fcy), resample=Image.BICUBIC))
    return layer
u = SS * 3.2
fl = petals(8, int(58 * u), int(15 * u), (150, 178, 226, 110), (205, 222, 252, 240))
fl = Image.alpha_composite(fl, petals(8, int(44 * u), int(12 * u), (226, 168, 204, 125), (250, 210, 228, 240), 0.5))
fl = Image.alpha_composite(fl, petals(8, int(29 * u), int(9 * u), (248, 214, 150, 140), (255, 234, 180, 245)))
for r in range(int(14 * u), 0, -1):
    h = Image.new("RGBA", (fw, fh), (0, 0, 0, 0)); ImageDraw.Draw(h).ellipse([fcx - r, fcy - r, fcx + r, fcy + r], fill=(255, 214, 162, int(60 + 120 * (1 - r / (14 * u)))))
    fl = Image.alpha_composite(fl, h)
im = Image.alpha_composite(im, fl.resize((W, H), Image.LANCZOS))
d = ImageDraw.Draw(im)
f1 = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 132)
f2 = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia Italic.ttf", 40)
f3 = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 28)
d.text((640, 215), "Tarn", font=f1, fill=(255, 255, 255, 245))
d.text((642, 375), "Focus rounds. Slow breathing.", font=f2, fill=(236, 242, 252, 235))
d.text((642, 438), "A free, open source Mac menu bar app.", font=f3, fill=(226, 236, 250, 215))
im.convert("RGB").save("docs/images/social-preview.png")
