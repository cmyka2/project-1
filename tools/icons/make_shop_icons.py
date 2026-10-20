"""Generates the 512x512 shop icons (clover theme) in assets/shop-icons.
Upload them on the Creator Dashboard as the gamepass / developer product images, then paste the
rbxassetid into MonetizationConfig `image`. Run: python3 tools/icons/make_shop_icons.py"""
import math, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "shop-icons")
S = 512
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
if not os.path.exists(FONT):
    FONT = None


def font(size):
    return ImageFont.truetype(FONT, size) if FONT else ImageFont.load_default()


def background(top, bottom):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / (S - 1)
        gd.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([8, 8, S - 8, S - 8], radius=96, fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([8, 8, S - 8, S - 8], radius=96, outline=(0, 0, 0, 255), width=16)
    # soft shine
    shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shine).ellipse([40, 20, S - 40, 230], fill=(255, 255, 255, 50))
    img.alpha_composite(shine.filter(ImageFilter.GaussianBlur(20)))
    return img


def clover(img, cx, cy, r, leaf=(70, 200, 80), dark=(30, 110, 40), leaves=4):
    d = ImageDraw.Draw(img)
    # stem
    d.line([(cx, cy), (cx + r * 0.5, cy + r * 1.6)], fill=(0, 0, 0), width=int(r * 0.32))
    d.line([(cx, cy), (cx + r * 0.5, cy + r * 1.6)], fill=dark, width=int(r * 0.18))
    for k in range(leaves):
        a = math.radians(45 + k * 360 / leaves)
        lx, ly = cx + math.cos(a) * r * 0.62, cy + math.sin(a) * r * 0.62
        # heart-ish leaf = two circles + outline
        for side in (-1, 1):
            b = a + side * math.radians(28)
            ox, oy = lx + math.cos(b) * r * 0.2, ly + math.sin(b) * r * 0.2
            rr = r * 0.48
            d.ellipse([ox - rr - 8, oy - rr - 8, ox + rr + 8, oy + rr + 8], fill=(0, 0, 0))
    for k in range(leaves):
        a = math.radians(45 + k * 360 / leaves)
        lx, ly = cx + math.cos(a) * r * 0.62, cy + math.sin(a) * r * 0.62
        for side in (-1, 1):
            b = a + side * math.radians(28)
            ox, oy = lx + math.cos(b) * r * 0.2, ly + math.sin(b) * r * 0.2
            rr = r * 0.48
            d.ellipse([ox - rr, oy - rr, ox + rr, oy + rr], fill=leaf)
        d.line([(cx, cy), (cx + math.cos(a) * r * 0.9, cy + math.sin(a) * r * 0.9)], fill=dark, width=10)
    d.ellipse([cx - 18, cy - 18, cx + 18, cy + 18], fill=dark)


def label(img, txt, y, size, fill=(255, 255, 255)):
    d = ImageDraw.Draw(img)
    f = font(size)
    w = d.textlength(txt, font=f)
    d.text(((S - w) / 2, y), txt, font=f, fill=fill, stroke_width=max(6, size // 9), stroke_fill=(0, 0, 0))


def bolt(img, x, y, s, color=(255, 230, 60)):
    pts = [(x, y), (x + s * 0.55, y), (x + s * 0.3, y + s * 0.42), (x + s * 0.62, y + s * 0.42), (x + s * 0.05, y + s * 1.05), (x + s * 0.2, y + s * 0.55), (x - s * 0.08, y + s * 0.55)]
    d = ImageDraw.Draw(img)
    d.polygon(pts, fill=color, outline=(0, 0, 0), width=8)


def crown(img, cx, y, w, color=(255, 205, 50)):
    d = ImageDraw.Draw(img)
    h = w * 0.55
    pts = [(cx - w / 2, y + h), (cx - w / 2, y + h * 0.25), (cx - w / 4, y + h * 0.6), (cx, y), (cx + w / 4, y + h * 0.6), (cx + w / 2, y + h * 0.25), (cx + w / 2, y + h)]
    d.polygon(pts, fill=color, outline=(0, 0, 0), width=10)
    for px in (cx - w / 2, cx, cx + w / 2):
        d.ellipse([px - 16, (y if px == cx else y + h * 0.25) - 16, px + 16, (y if px == cx else y + h * 0.25) + 16], fill=(255, 80, 120), outline=(0, 0, 0), width=5)


def arrows(img, cx, cy, r, color=(120, 200, 255)):
    d = ImageDraw.Draw(img)
    for start in (20, 200):
        d.arc([cx - r, cy - r, cx + r, cy + r], start, start + 140, fill=(0, 0, 0), width=34)
        d.arc([cx - r, cy - r, cx + r, cy + r], start, start + 140, fill=color, width=20)
        a = math.radians(start + 140)
        tx, ty = cx + math.cos(a) * r, cy + math.sin(a) * r
        n = a + math.pi / 2
        pts = [(tx + math.cos(n) * 34, ty + math.sin(n) * 34), (tx + math.cos(a) * 28, ty + math.sin(a) * 28), (tx - math.cos(a) * 28, ty - math.sin(a) * 28)]
        d.polygon(pts, fill=color, outline=(0, 0, 0), width=6)


def die(img, x, y, s, color=(255, 255, 255)):
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([x, y, x + s, y + s], radius=s // 5, fill=color, outline=(0, 0, 0), width=8)
    for px, py in ((0.28, 0.28), (0.5, 0.5), (0.72, 0.72)):
        rr = s * 0.09
        d.ellipse([x + s * px - rr, y + s * py - rr, x + s * px + rr, y + s * py + rr], fill=(0, 0, 0))


def potion(img, cx, cy, color=(120, 255, 140)):
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([cx - 30, cy - 150, cx + 30, cy - 80], radius=10, fill=(200, 150, 90), outline=(0, 0, 0), width=8)
    d.ellipse([cx - 120, cy - 100, cx + 120, cy + 140], fill=color, outline=(0, 0, 0), width=10)
    d.ellipse([cx - 80, cy - 60, cx - 20, cy], fill=(255, 255, 255, 160))


def globe(img, cx, cy, r):
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(60, 140, 230), outline=(0, 0, 0), width=10)
    d.ellipse([cx - r * 0.45, cy - r, cx + r * 0.45, cy + r], outline=(0, 0, 0), width=6)
    d.line([(cx - r, cy), (cx + r, cy)], fill=(0, 0, 0), width=6)
    d.polygon([(cx - r * 0.6, cy - r * 0.5), (cx - r * 0.1, cy - r * 0.6), (cx - r * 0.2, cy + r * 0.1), (cx - r * 0.7, cy)], fill=(90, 200, 90))


def backpack(img, cx, cy):
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([cx - 110, cy - 120, cx + 110, cy + 130], radius=50, fill=(220, 130, 60), outline=(0, 0, 0), width=10)
    d.rounded_rectangle([cx - 70, cy - 10, cx + 70, cy + 90], radius=20, fill=(190, 100, 40), outline=(0, 0, 0), width=8)
    d.arc([cx - 60, cy - 180, cx + 60, cy - 80], 180, 360, fill=(0, 0, 0), width=18)


def save(img, name):
    img.save(os.path.join(OUT, name + ".png"))


G1, G2 = (120, 240, 120), (20, 120, 50)
# gamepasses
img = background(G1, G2); clover(img, 256, 210, 120); label(img, "2X LUCK", 380, 86); save(img, "lucky")
img = background((90, 255, 200), (10, 110, 80)); clover(img, 180, 200, 95, leaf=(60, 230, 120)); clover(img, 330, 200, 95, leaf=(255, 220, 70), dark=(150, 110, 20)); label(img, "3X LUCK", 380, 86); save(img, "super_lucky")
img = background((255, 230, 120), (190, 120, 10)); crown(img, 256, 70, 300); clover(img, 256, 300, 70); label(img, "VIP", 390, 96); save(img, "vip")
img = background((255, 250, 150), (210, 150, 20)); clover(img, 200, 210, 100); bolt(img, 300, 80, 200); label(img, "QUICK", 390, 86); save(img, "quick_roll")
img = background((150, 210, 255), (30, 90, 180)); arrows(img, 256, 210, 150); clover(img, 256, 200, 70); label(img, "AUTO", 390, 90); save(img, "auto_roll")
img = background((220, 170, 255), (100, 40, 170)); die(img, 70, 120, 130); die(img, 190, 70, 130); die(img, 310, 120, 130); clover(img, 256, 290, 50); label(img, "X3 ROLL", 390, 80); save(img, "triple_roll")
img = background((255, 200, 140), (180, 90, 30)); backpack(img, 256, 220); label(img, "+200", 380, 100); save(img, "big_backpack")
# products
for n, col in ((10, (120, 240, 120)), (100, (80, 255, 170)), (1000, (60, 255, 220))):
    img = background(col, (10, 100, 50)); clover(img, 256, 200, 115); label(img, str(n), 330, 110 if n < 1000 else 96); label(img, "LUCKY ROLLS", 440, 52); save(img, "lucky_%d" % n)
img = background((200, 255, 200), (40, 140, 70)); potion(img, 256, 210); clover(img, 256, 230, 55); label(img, "2X 15 MIN", 390, 70); save(img, "luck_potion")
img = background((140, 255, 230), (20, 110, 120)); globe(img, 256, 200, 140); clover(img, 340, 270, 60); label(img, "SERVER 2X", 390, 70); save(img, "server_luck")
print("wrote", len(os.listdir(OUT)), "icons to", os.path.abspath(OUT))
