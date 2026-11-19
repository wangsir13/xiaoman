import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

CJK = re.compile("[\u4e00-\u9fff]")
STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

rows = []
for path in sorted(pathlib.Path("Xiaoman").rglob("*.swift")):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if not CJK.search(line):
            continue
        for match in STRING.finditer(line):
            value = match.group(1)
            if CJK.search(value):
                rows.append((path.as_posix(), number, value))

for path, number, value in rows:
    print(f"{path}:{number}\t{value}")

print(f"\n共 {len(rows)} 条中文字符串", file=sys.stderr)
