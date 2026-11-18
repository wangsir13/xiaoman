"""给小满 App 生成 1024x1024 图标候选（4 个方向）。

输出到 tools/icon-candidates/：
  xiaoman-a-wheat.png    麦穗·晨光
  xiaoman-b-ring.png     满环
  xiaoman-c-seal.png     朱印·满
  xiaoman-d-type.png     字标·小满
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W = 1024
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon-candidates")

GOLD_LIGHT = (255, 232, 182)
GOLD = (232, 183, 90)
GOLD_DEEP = (170, 118, 42)

FONT_LI = r"C:\Windows\Fonts\SIMLI.TTF"
FONT_XING = r"C:\Windows\Fonts\STXINGKA.TTF"


def vgrad(size, top, bottom):
    w, h = size
    strip = Image.new("RGB", (1, h))
    px = strip.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return strip.resize((w, h), Image.BILINEAR)


def glow(base, center, radius, color, alpha):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = center
    d.ellipse([x - radius, y - radius, x + radius, y + radius], fill=color + (alpha,))
    base.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius / 2.0)))


def grain_points(cx, cy, length, width, angle_deg):
    """麦粒：一颗沿轴线倾斜的椭圆多边形。"""
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    steps = 34
    for i in range(steps):
        t = 2 * math.pi * i / steps
        # 上尖下圆：用 |sin| 的偏斜让一头更尖
        u = length / 2 * math.cos(t)
        v = width / 2 * math.sin(t)
        pts.append((cx + u * ca - v * sa, cy + u * sa + v * ca))
    return pts


def wheat_ear(draw, cx, base_y, height, fill=GOLD, pairs=8, angle=46, grain_scale=1.0):
    top = base_y - height
    width = max(2, int(height * 0.007))
    draw.line([(cx, base_y), (cx, top + height * 0.04)], fill=fill, width=width)

    ear_len = height * 0.70
    for i in range(pairs):
        t = i / (pairs - 1)
        y = top + height * 0.09 + ear_len * t
        shrink = 1.0 - 0.28 * t
        glen = height * 0.135 * shrink * grain_scale
        gwid = height * 0.052 * shrink * grain_scale
        for side in (-1, 1):
            ang = side * (angle - 8 * t)
            gx = cx + side * 1.05 * gwid
            draw.polygon(grain_points(gx, y, glen, gwid, ang), fill=fill)

    # 顶端那颗
    draw.polygon(grain_points(cx, top + height * 0.055, height * 0.128 * grain_scale,
                              height * 0.05 * grain_scale, 0), fill=fill)


def finish(image, path):
    small = image.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    os.makedirs(OUT_DIR, exist_ok=True)
    small.save(path, "PNG", optimize=True)
    print("saved", path, small.size)


# ---------------------------------------------------------------- A 麦穗·晨光
def make_a():
    canvas = vgrad((W, W), (22, 70, 48), (7, 26, 19)).convert("RGBA")
    glow(canvas, (W * 0.76, W * 0.18), W * 0.50, (250, 208, 128), 52)
    glow(canvas, (W * 0.20, W * 0.86), W * 0.42, (80, 190, 150), 22)

    # 柔和投影
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    wheat_ear(sd, W * 0.50, W * 0.895, W * 0.70, fill=(0, 0, 0), angle=46)
    shadow = shadow.filter(ImageFilter.GaussianBlur(W * 0.018))
    shadow.putalpha(shadow.split()[3].point(lambda v: int(v * 0.45)))
    canvas.alpha_composite(shadow, (0, int(W * 0.012)))

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    wheat_ear(d, W * 0.235, W * 0.875, W * 0.50, fill=GOLD_DEEP, pairs=7, angle=44, grain_scale=0.95)
    wheat_ear(d, W * 0.765, W * 0.875, W * 0.54, fill=GOLD_DEEP, pairs=7, angle=44, grain_scale=0.95)
    wheat_ear(d, W * 0.50, W * 0.895, W * 0.70, fill=GOLD, pairs=8, angle=46)
    canvas.alpha_composite(layer)
    finish(canvas, os.path.join(OUT_DIR, "xiaoman-a-wheat.png"))


# ---------------------------------------------------------------- B 满环
def make_b():
    canvas = vgrad((W, W), (11, 36, 27), (5, 19, 14)).convert("RGBA")
    glow(canvas, (W * 0.5, W * 0.46), W * 0.40, (232, 183, 90), 30)

    ring = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(ring)
    d.ellipse([W * 0.20, W * 0.20, W * 0.80, W * 0.80], fill=255)
    d.ellipse([W * 0.272, W * 0.272, W * 0.728, W * 0.728], fill=0)
    ring = ring.filter(ImageFilter.GaussianBlur(W * 0.0012))

    grad = vgrad((W, W), (255, 236, 196), (188, 132, 50)).convert("RGBA")
    tinted = Image.composite(grad, Image.new("RGBA", (W, W), (0, 0, 0, 0)), ring)
    canvas.alpha_composite(tinted.filter(ImageFilter.GaussianBlur(W * 0.02)))
    canvas.alpha_composite(tinted)

    # 环内一束麦穗
    inner = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    idraw = ImageDraw.Draw(inner)
    wheat_ear(idraw, W * 0.5, W * 0.655, W * 0.30, fill=GOLD_LIGHT, pairs=7, angle=44)
    canvas.alpha_composite(inner)
    finish(canvas, os.path.join(OUT_DIR, "xiaoman-b-ring.png"))


# ---------------------------------------------------------------- C 朱印·满
def make_c():
    canvas = vgrad((W, W), (16, 42, 32), (6, 20, 15)).convert("RGBA")

    pad = W * 0.205
    red = (166, 44, 38)
    seal = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(seal)
    d.rounded_rectangle([pad, pad, W - pad, W - pad], radius=W * 0.07, fill=red + (255,))

    inset = W * 0.028
    d.rounded_rectangle(
        [pad + inset, pad + inset, W - pad - inset, W - pad - inset],
        radius=W * 0.05,
        outline=(250, 240, 224, 80),
        width=max(2, int(W * 0.0032)),
    )

    rnd = random.Random(11)
    for _ in range(140):
        x = rnd.uniform(pad, W - pad)
        y = rnd.uniform(pad, W - pad)
        r = rnd.uniform(W * 0.0015, W * 0.0055)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(138, 30, 26, 100))

    font = ImageFont.truetype(FONT_LI, int(W * 0.42))
    d.text((W * 0.5, W * 0.505), "满", font=font, fill=(251, 245, 233, 255), anchor="mm")

    canvas.alpha_composite(seal.filter(ImageFilter.GaussianBlur(W * 0.012)))
    canvas.alpha_composite(seal)
    finish(canvas, os.path.join(OUT_DIR, "xiaoman-c-seal.png"))


# ---------------------------------------------------------------- D 字标·小满
def make_d():
    canvas = vgrad((W, W), (14, 38, 29), (5, 16, 12)).convert("RGBA")
    glow(canvas, (W * 0.5, W * 0.34), W * 0.40, (232, 183, 90), 26)

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(FONT_XING, int(W * 0.30))
    d.text((W * 0.5, W * 0.47), "小满", font=font, fill=(255, 231, 186, 255), anchor="mm")
    d.line([(W * 0.35, W * 0.675), (W * 0.65, W * 0.675)],
           fill=(232, 183, 90, 210), width=max(2, int(W * 0.005)))
    r = W * 0.011
    d.ellipse([W * 0.5 - r, W * 0.73 - r, W * 0.5 + r, W * 0.73 + r], fill=(232, 183, 90, 210))

    canvas.alpha_composite(layer)
    finish(canvas, os.path.join(OUT_DIR, "xiaoman-d-type.png"))


if __name__ == "__main__":
    make_a()
    make_b()
    make_c()
    make_d()
