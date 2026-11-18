"""把支付宝 / 微信收款码裁成「只有二维码」，去掉收款人姓名、手机号等个人信息。

做法：先用背景色（蓝 / 绿）把二维码外面那张白卡的边界量出来，再按比例裁出纯二维码，
不再包含海报顶部的标语和卡片底部的姓名。

用法：python tools/crop_qrcodes.py
"""

import os
import sys

from PIL import Image
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Xiaoman", "Assets.xcassets")

SRCS = {
    "AlipayQR": (
        r"C:\Users\32008\.dsh\attachments\v1\objects\21\2111e4b9333ada845a289a6bfed1f745fde39e25ceb0d233dcc3eb323548acf7",
        "blue",
    ),
    "WechatQR": (
        r"C:\Users\32008\.dsh\attachments\v1\objects\58\588030c2e2d7d9c10319b8cf31eb811432a30cea4c2df27e96d640f95d489bbf",
        "green",
    ),
}

BASE_WIDTH = {"AlipayQR": 560, "WechatQR": 448}
JPEG_QUALITY = 90


def card_box(path, kind):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(int)
    h, w, _ = a.shape
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    if kind == "blue":
        bg = (b > 150) & (b > r + 40)
    else:
        bg = (g > 120) & (g > r + 40) & (g > b + 20)
    fg = ~bg

    rows = []
    for y in range(h):
        row = fg[y]
        cur = best_len = best_start = 0
        start = 0
        for x in range(w):
            if row[x]:
                if cur == 0:
                    start = x
                cur += 1
                if cur > best_len:
                    best_len, best_start = cur, start
            else:
                cur = 0
        rows.append((best_start, best_len))

    # 取出现次数最多的「行内最长连续前景长度」当作卡片宽度（去掉整宽的标题带）
    from collections import Counter
    lengths = [l for _, l in rows if 0.4 * w < l < 0.95 * w]
    if not lengths:
        return None
    mode = Counter(round(l / 10) * 10 for l in lengths).most_common(1)[0][0]
    card_rows = [y for y, (_, l) in enumerate(rows) if abs(l - mode) <= max(12, 0.03 * w)]
    if not card_rows:
        return None
    y0, y1 = min(card_rows), max(card_rows)
    x0 = min(rows[y][0] for y in card_rows)
    x1 = max(rows[y][0] + rows[y][1] for y in card_rows)
    return im, (x0, y0, x1, y1)


def crop_qr(name, src, kind):
    found = card_box(src, kind)
    if not found:
        print("!! 没找到二维码白卡：", name)
        return False
    im, (x0, y0, x1, y1) = found
    card_w, card_h = x1 - x0, y1 - y0

    # 在卡片里找二维码本体：连续且「深色像素够多」的行 / 列区间（跳过下面的姓名文字）
    import numpy as np

    gray = np.asarray(im.convert("L")).astype(int)
    dark = gray[y0:y1, x0:x1] < 100
    row_counts = dark.sum(axis=1)
    col_counts = dark.sum(axis=0)
    row_thr = max(4, int(card_w * 0.02))
    col_thr = max(4, int(card_h * 0.02))

    def longest_run(counts, thr):
        best = (0, 0)
        start = None
        for i, c in enumerate(counts):
            if c >= thr:
                if start is None:
                    start = i
                if i - start > best[1] - best[0]:
                    best = (start, i)
            else:
                start = None
        return best

    ry0, ry1 = longest_run(row_counts, row_thr)
    rx0, rx1 = longest_run(col_counts, col_thr)
    if ry1 <= ry0 or rx1 <= rx0:
        print("!! 找不到二维码本体：", name)
        return False

    pad = int(round(max(rx1 - rx0, ry1 - ry0) * 0.02))
    left = x0 + max(0, rx0 - pad)
    top = y0 + max(0, ry0 - pad)
    right = x0 + min(card_w, rx1 + pad)
    bottom = y0 + min(card_h, ry1 + pad)

    side = max(right - left, bottom - top)
    cx = (left + right) // 2
    cy = (top + bottom) // 2
    left = max(0, cx - side // 2)
    top = max(0, cy - side // 2)
    box = (left, top, left + side, top + side)
    qr = im.crop(box)
    print(f"  {name}: 白卡 {card_w}x{card_h} → 二维码 {rx1-rx0}x{ry1-ry0} → 裁出 ({left},{top}) {side}x{side}")

    out_dir = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(out_dir, exist_ok=True)
    base_w = BASE_WIDTH[name]

    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        target = base_w * scale
        path = os.path.join(out_dir, f"{name}{suffix}.jpg")
        qr.resize((target, target), Image.LANCZOS).save(
            path, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True
        )
        print(f"    {os.path.basename(path)} {target}x{target} {os.path.getsize(path)} bytes")

    contents = {
        "images": [
            {"filename": f"{name}.jpg", "idiom": "universal", "scale": "1x"},
            {"filename": f"{name}@2x.jpg", "idiom": "universal", "scale": "2x"},
            {"filename": f"{name}@3x.jpg", "idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    import json

    with open(os.path.join(out_dir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, ensure_ascii=False, indent=2)

    for old in os.listdir(out_dir):
        if old.endswith(".png"):
            os.remove(os.path.join(out_dir, old))
    return True


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    ok = True
    for name, (src, kind) in SRCS.items():
        if not os.path.exists(src):
            print("!! 源图不存在：", src)
            ok = False
            continue
        ok = crop_qr(name, src, kind) and ok
    print("完成" if ok else "有失败项")
