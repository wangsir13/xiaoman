import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

path = pathlib.Path("Xiaoman/Views/SettingsView.swift")
text = path.read_text(encoding="utf-8")

# 1. 开关标题随「能不能读图」变化
old_toggle = (
    '            Toggle(isOn: $aiEnabled) {\n'
    '                Label("用大模型复核识别结果", systemImage: "sparkles")\n'
    '            }\n'
)
new_toggle = (
    '            Toggle(isOn: $aiEnabled) {\n'
    '                Label(currentProvider.supportsVision ? "用大模型直接读截图" : "用大模型复核识别结果",\n'
    '                      systemImage: "sparkles")\n'
    '            }\n'
)

# 2. 在服务商 Picker 之后插一行「识别方式」
anchor = (
    '                .onChange(of: aiProviderRaw) { _ in\n'
    '                    aiModel = ""\n'
    '                    aiEndpoint = ""\n'
    '                    aiMessage = nil\n'
    '                }\n'
)
insert = anchor + (
    '\n'
    '                Label(currentProvider.supportsVision\n'
    '                      ? "截图直接交给模型读，不经过 OCR"\n'
    '                      : "先本地 OCR，再把文字交给模型复核",\n'
    '                      systemImage: currentProvider.supportsVision ? "eye" : "text.viewfinder")\n'
    '                    .font(.system(size: 12))\n'
    '                    .foregroundStyle(.secondary)\n'
)

# 3. 页脚说明：读图模式会发图片
old_footer = (
    '        return "Key 在 \\(url) 申请，只存在本机，只发给这一家。识别时会发账单文字，不发图片。"\n'
)
new_footer = (
    '        if currentProvider.supportsVision {\n'
    '            return "Key 在 \\(url) 申请，只存在本机。"\n'
    '                + "截图会直接发给你选的这家服务商来读（\(currentProvider.visionHint)），关掉开关就完全离线。"\n'
    '        }\n'
    '        return "Key 在 \\(url) 申请，只存在本机，只发给这一家。识别时会发账单文字，不发图片。"\n'
)

for old, new, name in [
    (old_toggle, new_toggle, "toggle"),
    (anchor, insert, "status"),
    (old_footer, new_footer, "footer"),
]:
    if old not in text:
        print("missing:", name)
        sys.exit(1)
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
print("patched settings")
