"""小满 App 图标终稿（字标版）：浅色 / 深色 / 着色三套，1024x1024、无 alpha。

用法：python tools/make_icon_final.py
输出：Xiaoman/Assets.xcassets/AppIcon.appiconset/AppIcon-1024{,-dark,-tinted}.png
预览同时写到 tools/icon-candidates/。
"""

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W = 1024
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_SET = os.path.join(ROOT, "Xiaoman", "Assets.xcassets", "AppIcon.appiconset")
PREVIEW = os.path.join(ROOT, "tools", "icon-candidates")

FONT_XING = r"C:\Windows\Fonts\STXINGKA.TTF"

INK_LIGHT = (255, 233, 190)   # 深色底上的暖白字
INK_DARK = (28, 62, 48)       # 浅色底上的墨绿字
GOLD = (232, 183, 90)


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


def wordmark(canvas, ink, line_color, dot_color, glow_alpha=0):
    if glow_alpha:
        glow(canvas, (W * 0.5, W * 0.34), W * 0.42, GOLD, glow_alpha)

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    font = ImageFont.truetype(FONT_XING, int(W * 0.30))
    d.text((W * 0.5, W * 0.455), "小满", font=font, fill=ink + (255,), anchor="mm")

    d.line([(W * 0.352, W * 0.668), (W * 0.648, W * 0.668)],
           fill=line_color, width=max(2, int(W * 0.0045)))
    r = W * 0.0105
    d.ellipse([W * 0.5 - r, W * 0.722 - r, W * 0.5 + r, W * 0.722 + r], fill=dot_color)

    canvas.alpha_composite(layer)


def make_light():
    canvas = vgrad((W, W), (252, 249, 241), (232, 223, 204)).convert("RGBA")
    glow(canvas, (W * 0.22, W * 0.14), W * 0.44, (255, 255, 255), 70)
    glow(canvas, (W * 0.84, W * 0.90), W * 0.40, (206, 188, 152), 36)
    wordmark(canvas, INK_DARK, (28, 62, 48, 150), (28, 62, 48, 170))
    return canvas


def make_dark():
    canvas = vgrad((W, W), (14, 38, 29), (5, 16, 12)).convert("RGBA")
    wordmark(canvas, INK_LIGHT, (232, 183, 90, 200), (232, 183, 90, 210), glow_alpha=26)
    return canvas


def make_tinted():
    canvas = vgrad((W, W), (30, 30, 32), (12, 12, 13)).convert("RGBA")
    wordmark(canvas, (246, 246, 248), (246, 246, 248, 170), (246, 246, 248, 200))
    return canvas


def save(canvas, name):
    flat = canvas.convert("RGB")
    os.makedirs(ICON_SET, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    path = os.path.join(ICON_SET, name)
    flat.save(path, "PNG", optimize=True)
    flat.save(os.path.join(PREVIEW, name), "PNG", optimize=True)
    print("saved", name, flat.size, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    save(make_light(), "AppIcon-1024.png")
    save(make_dark(), "AppIcon-1024-dark.png")
    save(make_tinted(), "AppIcon-1024-tinted.png")
