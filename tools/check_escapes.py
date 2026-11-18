import io, os, sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
BACKSLASH = chr(92)
root = r"C:\Users\32008\Desktop\deepseek\xiaoman\Xiaoman"

for dirpath, _, filenames in os.walk(root):
    for name in sorted(filenames):
        if not name.endswith(".swift"):
            continue
        path = os.path.join(dirpath, name)
        text = io.open(path, encoding="utf-8").read()
        for i, line in enumerate(text.split("\n"), 1):
            if BACKSLASH in line:
                print("%s:%d: %s" % (os.path.relpath(path, root), i, line.strip()))
