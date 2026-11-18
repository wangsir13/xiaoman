"""生成 1024x1024 的 App 图标（RGB，无 alpha，iOS 会自动裁圆角）。"""

import os
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Xiaoman", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png",
)

TOP = (47, 78, 222)
BOTTOM = (124, 58, 214)


def gradient(width, height, top, bottom):
    image = Image.new("RGB", (width, height))
    pixels = image.load()
    for y in range(height):
        t = y / (height - 1)
        r = round(top[0] + (bottom[0] - top[0]) * t)
        g = round(top[1] + (bottom[1] - top[1]) * t)
        b = round(top[2] + (bottom[2] - top[2]) * t)
        for x in range(width):
            pixels[x, y] = (r, g, b)
    return image


def pick_font(size):
    candidates = [
        r"C:\Windows\Fonts\msyhbd.ttc",
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\arialbd.ttf",
        r"C:\Windows\Fonts\seguisb.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def main():
    image = gradient(SIZE, SIZE, TOP, BOTTOM)
    draw = ImageDraw.Draw(image, "RGBA")

    # 一张「截图卡片」的轮廓
    margin = 210
    card = [margin, margin - 30, SIZE - margin, SIZE - margin + 30]
    draw.rounded_rectangle(card, radius=90, outline=(255, 255, 255, 150), width=14)

    # 卡片顶部的小短横，像截图里的标题
    draw.rounded_rectangle(
        [SIZE // 2 - 70, margin + 55, SIZE // 2 + 70, margin + 71],
        radius=8, fill=(255, 255, 255, 120),
    )

    # 人民币符号
    font = pick_font(340)
    text = "\u00a5"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(
        ((SIZE - tw) / 2 - bbox[0], (SIZE - th) / 2 - bbox[1] - 10),
        text, font=font, fill=(255, 255, 255, 255),
    )

    image = image.convert("RGB")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    image.save(OUT, "PNG")
    print("saved", OUT, image.size, image.mode)


if __name__ == "__main__":
    main()
