import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

path = pathlib.Path("Xiaoman/Views/SettingsView.swift")
text = path.read_text(encoding="utf-8")

old = '''                Label(currentProvider.supportsVision
                      ? "截图直接交给模型读，不经过 OCR"
                      : "先本地 OCR，再把文字交给模型复核",
                      systemImage: currentProvider.supportsVision ? "eye" : "text.viewfinder")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
'''
new = '''                Label("截图直接交给模型读；接口不接受图片时自动改用 OCR",
                      systemImage: "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
'''
if old not in text:
    print("miss: status label")
    sys.exit(1)
text = text.replace(old, new, 1)

old_footer = '''        if currentProvider.supportsVision {
            return "Key 在 \\(url) 申请，只存在本机。"
                + "截图将直接发送至所选服务商进行识别（\\(currentProvider.visionHint)）；关闭开关即恢复完全离线。"
        }
'''
new_footer = '''        if currentProvider.supportsVision {
            return "Key 在 \\(url) 申请，只存在本机。"
                + "截图将直接发送至所选服务商进行识别（\\(currentProvider.visionHint)）；关闭开关即恢复完全离线。"
        }
'''
text = text.replace(old_footer, new_footer, 1)

path.write_text(text, encoding="utf-8")
print("settings patched")
