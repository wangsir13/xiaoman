import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

path = pathlib.Path("Xiaoman/Views/SettingsView.swift")
text = path.read_text(encoding="utf-8")

old = (
    "        do {\n"
    "            let text = try await ImageOCR.recognizeText(in: image)\n"
    "            await store.enqueueSmart(text: text)\n"
    "        } catch {\n"
    '            store.flash("识别失败：\\(error.localizedDescription)")\n'
    "        }    }\n"
)

new = "        await store.enqueueVision(image)\n    }\n"

if old not in text:
    print("pattern not found")
    sys.exit(1)

path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("patched")
