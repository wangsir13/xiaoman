"""把打赏二维码和作者头像转成 App 内的 imageset（1x/2x/3x）。

源图来自用户提供的三张截图，运行时不再是资源依赖，只在这里生成一次。
"""
import json
import os
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Xiaoman", "Assets.xcassets")

SOURCES = {
    # name: (源文件, 1x 宽度)
    "AlipayQR": (r"C:\Users\32008\.dsh\attachments\v1\objects\21\2111e4b9333ada845a289a6bfed1f745fde39e25ceb0d233dcc3eb323548acf7", 560),
    "WechatQR": (r"C:\Users\32008\.dsh\attachments\v1\objects\58\588030c2e2d7d9c10319b8cf31eb811432a30cea4c2df27e96d640f95d489bbf", 448),
    "ProducerAvatar": (r"C:\Users\32008\.dsh\attachments\v1\objects\8c\8c55d81efcd7472128b8aa1d1cac504bf8683c115f199e4462de63172e95c703", 180),
}

CONTENTS = {
    "images": [
        {"filename": "{name}@1x.jpg", "idiom": "universal", "scale": "1x"},
        {"filename": "{name}@2x.jpg", "idiom": "universal", "scale": "2x"},
        {"filename": "{name}@3x.jpg", "idiom": "universal", "scale": "3x"},
    ],
    "info": {"author": "xcode", "version": 1},
}


def build(name: str, source: str, width_1x: int) -> None:
    folder = os.path.join(ASSETS, name + ".imageset")
    os.makedirs(folder, exist_ok=True)

    image = Image.open(source).convert("RGB")
    ratio = image.height / image.width

    for scale in (1, 2, 3):
        target_w = width_1x * scale
        target_h = int(round(target_w * ratio))
        resized = image.resize((target_w, target_h), Image.LANCZOS)
        out = os.path.join(folder, f"{name}@{scale}x.jpg")
        resized.save(out, "JPEG", quality=88, optimize=True, progressive=True)
        print(f"  {out} {resized.width}x{resized.height}")

    # 清掉上一轮留下的 png，避免 imageset 里混着没被引用的旧文件
    for leftover in os.listdir(folder):
        if leftover.endswith(".png"):
            os.remove(os.path.join(folder, leftover))

    contents = json.loads(json.dumps(CONTENTS))
    for item in contents["images"]:
        item["filename"] = item["filename"].format(name=name)
    with open(os.path.join(folder, "Contents.json"), "w", encoding="utf-8") as handle:
        json.dump(contents, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def main() -> int:
    for name, (source, width) in SOURCES.items():
        if not os.path.exists(source):
            print(f"缺少源文件：{source}")
            return 1
        print(f"{name}:")
        build(name, source, width)
    print("完成")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
