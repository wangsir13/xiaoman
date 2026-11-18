import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

TAB = chr(9)
fixed = 0

for path in pathlib.Path("Xiaoman").rglob("*.swift"):
    text = path.read_text(encoding="utf-8")
    if TAB not in text:
        continue

    original = text
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if TAB not in line:
            continue
        # 字符串字面量里出现制表符 -> 换成 Swift 的 \t 转义
        if '"' in line:
            lines[index] = line.replace(TAB, "\\t")
        else:
            lines[index] = line.replace(TAB, "    ")
    text = "\n".join(lines)

    if text != original:
        path.write_text(text, encoding="utf-8")
        fixed += 1
        print("fixed:", path)

print("files touched:", fixed)
