"""工程自检：括号平衡、配置一致性、跨文件符号引用。

Windows 上没法编译 Swift，所以这里用静态检查兜住最常见的低级错误：
1. 每个 .swift 的 () [] {} 是否平衡（跳过字符串、注释、插值）
2. Info.plist / xcassets 的 JSON 是否合法
3. project.yml、工作流、Info.plist 里的名字是否互相对得上
4. Views 里调用的 store 方法是否真的存在
"""

import json
import os
import plistlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PAIRS = {")": "(", "]": "[", "}": "{"}


def swift_files():
    roots = [os.path.join(ROOT, "Xiaoman")]
    tests = os.path.join(ROOT, "XiaomanTests")
    if os.path.isdir(tests):
        roots.append(tests)
    for root in roots:
        for base, _, files in os.walk(root):
            for name in sorted(files):
                if name.endswith(".swift"):
                    yield os.path.join(base, name)


def check_balance(path):
    text = open(path, encoding="utf-8").read()
    stack = []          # [(char, line, tag)]
    contexts = ["normal"]  # normal / string / mlstring / raw<string hashes> / interp
    raw_hashes = 0
    line = 1
    i = 0
    n = len(text)
    errors = []

    while i < n:
        ch = text[i]
        if ch == "\n":
            line += 1

        ctx = contexts[-1]

        if ctx == "normal" or ctx == "interp":
            if ch == "/" and text.startswith("//", i):
                while i < n and text[i] != "\n":
                    i += 1
                continue
            if ch == "/" and text.startswith("/*", i):
                depth = 1
                i += 2
                while i < n and depth > 0:
                    if text[i] == "\n":
                        line += 1
                    if text.startswith("/*", i):
                        depth += 1
                        i += 2
                    elif text.startswith("*/", i):
                        depth -= 1
                        i += 2
                    else:
                        i += 1
                continue
            if text.startswith('"""', i):
                contexts.append("mlstring")
                i += 3
                continue
            if ch == '"':
                contexts.append("string")
                i += 1
                continue
            if ch == "#":
                m = re.match(r'(#+)"', text[i:])
                if m:
                    raw_hashes = len(m.group(1))
                    contexts.append("raw")
                    i += len(m.group(1)) + 1
                    continue
                i += 1
                continue
            if ch in "([{":
                stack.append((ch, line, "normal"))
                i += 1
                continue
            if ch in ")]}":
                if not stack:
                    errors.append(f"第 {line} 行：多出来的 {ch}")
                else:
                    opened, opened_line, tag = stack.pop()
                    if PAIRS[ch] != opened:
                        errors.append(
                            f"第 {line} 行：{ch} 对不上第 {opened_line} 行的 {opened}"
                        )
                    elif tag == "interp":
                        contexts.pop()  # 回到字符串里
                i += 1
                continue
            i += 1
            continue

        if ctx in ("string", "mlstring"):
            if ch == "\\":
                nxt = text[i + 1] if i + 1 < n else ""
                if nxt == "(":
                    stack.append(("(", line, "interp"))
                    contexts.append("interp")
                    i += 2
                    continue
                i += 2
                if nxt == "\n":
                    line += 1
                continue
            if ctx == "string" and ch == '"':
                contexts.pop()
                i += 1
                continue
            if ctx == "mlstring" and text.startswith('"""', i):
                contexts.pop()
                i += 3
                continue
            i += 1
            continue

        if ctx == "raw":
            terminator = '"' + "#" * raw_hashes
            if text.startswith(terminator, i):
                contexts.pop()
                i += len(terminator)
                continue
            if text.startswith("\\" + "#" * raw_hashes + "(", i):
                stack.append(("(", line, "interp"))
                contexts.append("interp")
                i += 2 + raw_hashes
                continue
            i += 1
            continue

        i += 1

    if stack:
        opened, opened_line, _ = stack[-1]
        errors.append(f"第 {opened_line} 行的 {opened} 没有闭合")
    return errors


def check_nsstring_members(path):
    """`xxx as NSString` 得到的变量上，不能再用 String 独有的成员。"""
    text = open(path, encoding="utf-8").read()
    names = set(re.findall(r"let\s+(\w+)\s*=\s*[^\n]*as NSString", text))
    problems = []
    for name in names:
        pattern = rf"\b{re.escape(name)}\.(count|isEmpty|trimmingCharacters|components)\b"
        for match in re.finditer(pattern, text):
            line = text.count("\n", 0, match.start()) + 1
            problems.append(f"第 {line} 行 {name}.{match.group(1)} —— NSString 没有这个成员")
    return problems


def check_workflow_yaml():
    """工作流里 run: | 的块内容必须缩进；顶格出现非顶层键会直接让 YAML 失效（GitHub 会秒失败）。"""
    path = os.path.join(ROOT, ".github", "workflows", "build-ipa.yml")
    if not os.path.exists(path):
        return ["工作流文件不存在"]
    allowed_tops = ("name:", "on:", "jobs:", "env:", "permissions:", "concurrency:", "defaults:", "---")
    problems = []
    for index, line in enumerate(open(path, encoding="utf-8").read().splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[0] in " \t":
            continue
        if line.startswith(allowed_tops):
            continue
        problems.append(f"第 {index} 行顶格出现 `{line[:40]}` —— 块标量里的内容必须缩进，否则 YAML 解析失败")
    # 顶层键之后必须紧跟缩进行，不能有第二个文档
    return problems


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def main():
    problems = []
    swift = list(swift_files())
    print(f"Swift 文件：{len(swift)} 个")

    for path in swift:
        for error in check_balance(path):
            problems.append(f"[括号] {rel(path)} {error}")
        for error in check_nsstring_members(path):
            problems.append(f"[类型] {rel(path)} {error}")

    for error in check_workflow_yaml():
        problems.append(f"[工作流] {error}")

    # ---- 配置文件 ----
    plist_path = os.path.join(ROOT, "Support", "Info.plist")
    with open(plist_path, "rb") as handle:
        info = plistlib.load(handle)
    print(f"Info.plist 解析成功：Bundle ID = {info.get('CFBundleIdentifier')}")

    for json_path in [
        os.path.join(ROOT, "Xiaoman", "Assets.xcassets", "Contents.json"),
        os.path.join(ROOT, "Xiaoman", "Assets.xcassets", "AppIcon.appiconset", "Contents.json"),
        os.path.join(ROOT, "Xiaoman", "Assets.xcassets", "AccentColor.colorset", "Contents.json"),
    ]:
        with open(json_path, encoding="utf-8") as handle:
            json.load(handle)
    print("xcassets JSON 全部合法")

    icon = os.path.join(ROOT, "Xiaoman", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
    if not os.path.exists(icon):
        problems.append("[资源] 缺少 AppIcon-1024.png")
    else:
        with open(icon, "rb") as handle:
            head = handle.read(33)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            problems.append("[资源] AppIcon-1024.png 不是 PNG")
        width = int.from_bytes(head[16:20], "big")
        height = int.from_bytes(head[20:24], "big")
        print(f"AppIcon：{width}x{height}")
        if (width, height) != (1024, 1024):
            problems.append(f"[资源] AppIcon 尺寸应为 1024x1024，实际 {width}x{height}")
        if head[25] not in (2, 6):  # color type: 2=RGB, 6=RGBA
            problems.append("[资源] AppIcon 颜色类型异常")

    # ---- project.yml 和工作流的一致性 ----
    yml = open(os.path.join(ROOT, "project.yml"), encoding="utf-8").read()
    workflow = open(
        os.path.join(ROOT, ".github", "workflows", "build-ipa.yml"), encoding="utf-8"
    ).read()

    if 'INFOPLIST_FILE: Support/Info.plist' not in yml:
        problems.append("[配置] project.yml 的 INFOPLIST_FILE 不是 Support/Info.plist")
    if "-scheme Xiaoman" not in workflow:
        problems.append("[配置] 工作流里的 -scheme 和 project.yml 的 scheme 不一致")
    if "Xiaoman.app" not in workflow:
        problems.append("[配置] 工作流里的 .app 名字和 PRODUCT_NAME 不一致")
    if info.get("CFBundleIdentifier") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
        problems.append("[配置] Info.plist 的 CFBundleIdentifier 应引用 $(PRODUCT_BUNDLE_IDENTIFIER)")

    if "XiaomanTests:" not in yml:
        problems.append("[配置] project.yml 缺少 XiaomanTests target")
    if "$(BUILT_PRODUCTS_DIR)/Xiaoman.app/Xiaoman" not in yml:
        problems.append("[配置] 测试 target 的 TEST_HOST 与 PRODUCT_NAME 不一致")
    if "- XiaomanTests" not in yml:
        problems.append("[配置] scheme 里没有把 XiaomanTests 挂到 test action")
    if "xcodebuild test" not in workflow:
        problems.append("[配置] 工作流里没有跑单元测试")
    if "continue-on-error: true" not in workflow:
        problems.append("[配置] 测试步骤应当 continue-on-error，避免拖累 ipa 产出")

    # ---- v2：iOS 26 + App Intents ----
    if 'iOS: "26.0"' not in yml:
        problems.append('[配置] project.yml 的 deploymentTarget 应为 iOS "26.0"')
    if 'IPHONEOS_DEPLOYMENT_TARGET: "26.0"' not in yml:
        problems.append('[配置] project.yml 的 IPHONEOS_DEPLOYMENT_TARGET 应为 "26.0"')
    if "macos-26" not in workflow:
        problems.append("[配置] 工作流应使用 macos-26 镜像以获得 iOS 26 SDK")
    intents_path = os.path.join(ROOT, "Xiaoman", "Intents", "RecordIntent.swift")
    if not os.path.exists(intents_path):
        problems.append("[配置] 缺少 App Intents 定义 Xiaoman/Intents/RecordIntent.swift")
    else:
        intents_text = open(intents_path, encoding="utf-8").read()
        if "AppShortcutsProvider" not in intents_text:
            problems.append("[配置] RecordIntent.swift 里没有注册 AppShortcutsProvider")
        if ": IntentFile" not in intents_text:
            problems.append("[配置] 截图入参应当是 IntentFile")
    if os.path.exists(os.path.join(ROOT, "Xiaoman", "Store", "LedgerStore.swift")):
        store_src = open(
            os.path.join(ROOT, "Xiaoman", "Store", "LedgerStore.swift"), encoding="utf-8"
        ).read()
        if "importInbox" in store_src:
            problems.append("[配置] LedgerStore 仍然保留截图落盘的 importInbox，应当已删除")

    schemes = [s for s in re.findall(r"^\s{2}(\w+):\s*$", yml, re.M)]
    print(f"project.yml 里出现的顶层小节：{schemes}")

    # URL scheme
    url_types = info.get("CFBundleURLTypes") or []
    registered = {
        scheme
        for entry in url_types
        for scheme in (entry.get("CFBundleURLSchemes") or [])
    }
    if "xiaoman" not in registered:
        problems.append(f"[配置] Info.plist 没注册 xiaoman scheme，实际={registered}")
    else:
        print("URL Scheme：xiaoman 已注册")

    # ---- 跨文件符号 ----
    store_text = open(
        os.path.join(ROOT, "Xiaoman", "Store", "LedgerStore.swift"), encoding="utf-8"
    ).read()
    store_methods = set(re.findall(r"func (\w+)", store_text))
    store_props = set(re.findall(r"var (\w+)", store_text))

    used_methods = set()
    used_props = set()
    for path in swift:
        if path.endswith("LedgerStore.swift"):
            continue
        text = open(path, encoding="utf-8").read()
        used_methods |= set(re.findall(r"store\.(\w+)\(", text))
        used_props |= set(re.findall(r"store\.(\w+)(?![\w(])", text))

    missing = sorted(used_methods - store_methods)
    if missing:
        problems.append(f"[符号] Views 调用了不存在的 store 方法：{missing}")
    else:
        print(f"store 方法引用全部存在：{sorted(used_methods)}")

    # env object 属性
    env_store_props = {"transactions", "pendingDrafts", "banner", "documentsURL"}
    unknown = sorted(used_props - store_props - store_methods)
    if unknown:
        print(f"提示：store 上还有这些被用到的名字（需人工确认）：{unknown}")

    # 定义过的视图类型，检查被引用的 View 是否都有定义
    # SwiftUI / 系统框架自带的容器与控件，不算「未定义的视图」
    system_views = {
        "ScrollView", "TabView", "NavigationStack", "NavigationView", "NavigationLink",
        "List", "Form", "Section", "Group", "Spacer", "Divider",
        "VStack", "HStack", "ZStack", "LazyVStack", "LazyHStack", "LazyVGrid", "LazyHGrid",
        "GeometryReader", "Canvas", "AnyView", "TimelineView",
        "Picker", "Toggle", "Label", "Button", "Menu", "DatePicker", "ColorPicker",
        "ProgressView", "TextEditor", "SecureField", "TextField", "Slider", "Stepper",
        "Chart", "Table", "OutlineGroup", "DisclosureGroup", "ShareLink", "Gauge",
    }

    defined = set()
    for path in swift:
        text = open(path, encoding="utf-8").read()
        defined |= set(re.findall(r"struct (\w+)", text))
        defined |= set(re.findall(r"enum (\w+)", text))
        defined |= set(re.findall(r"final class (\w+)", text))

    referenced = set()
    for path in swift:
        text = open(path, encoding="utf-8").read()
        referenced |= set(re.findall(r"\b([A-Z]\w*View)\(", text))
        referenced |= set(re.findall(r"\b([A-Z]\w*Store)\(\)", text))

    unknown_views = sorted(referenced - defined - system_views)
    if unknown_views:
        problems.append(f"[符号] 引用了未定义的视图：{unknown_views}")
    else:
        print(f"视图引用全部有定义：{len(referenced)} 个")

    print()
    if problems:
        print("发现问题：")
        for item in problems:
            print("  - " + item)
        return 1
    print("全部检查通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
