import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

# 口语 -> 书面语。只改用户看得见的文案，键名 / 日志类字符串不动。
REPLACEMENTS = {
    "Xiaoman/Import/CSVImporter.swift": [
        (
            "这个文件既不是 UTF-8 也不是 GBK，读不出来。用微信/支付宝原始导出的 CSV 或 xlsx 试试。",
            "文件编码无法识别。请使用微信或支付宝原始导出的 CSV 或 xlsx 文件。",
        ),
    ],
    "Xiaoman/Intents/RecordIntent.swift": [
        ("这张截图没读出金额，打开 App 手动记一笔吧。", "未能从截图中识别到金额，请在应用内手动记录。"),
        (
            "已识别 \\(outcome.summary)，等你确认（把握度 \\(outcome.confidence)）。",
            "已识别 \\(outcome.summary)，等待确认（置信度：\\(outcome.confidence)）。",
        ),
        (
            "没能确认金额，已放到待确认列表，打开 App 手动填一下。",
            "未能确认金额，已加入待确认列表，请在应用内补充。",
        ),
        ("已识别 \\(outcome.summary)，等你在 App 里确认。", "已识别 \\(outcome.summary)，等待在应用内确认。"),
    ],
    "Xiaoman/Views/AboutView.swift": [
        (
            "用着不顺手、识别不准、想要什么功能，都可以直接发邮件。",
            "使用中遇到的问题、识别偏差或功能建议，均可通过邮件反馈。",
        ),
        (
            "账目只存在这台手机上，没有账号、没有云端。默认完全离线；只有你自己打开「AI 复核」并填了 Key，才会把账单文字发给你选的那家模型服务商（DeepSeek / GPT / Claude / 豆包）。",
            "账目仅保存在本机，无账号体系、无云端存储。默认完全离线；仅在用户主动开启「AI 复核」并填写 Key 后，才会将账单文字发送至所选模型服务商。",
        ),
    ],
    "Xiaoman/Views/AssetsView.swift": [
        (
            "借款：别人欠你的（你借出去的）填正数，你欠别人的填负数，两种都允许。",
            "借款：他人欠款（借出）填正数，本人欠款（借入）填负数，两者均可。",
        ),
    ],
    "Xiaoman/Views/BudgetView.swift": [
        (
            "点一下把今天之前的额度清空：之前的日期不再占额度、也不往后结转，今天重新从「月预算 ÷ 天数」的 \\(Money.display(baseDaily)) 开始。",
            "重置后，今日之前的日期不再占用额度或产生结转，今日额度恢复为「月预算 ÷ 天数」= \\(Money.display(baseDaily))。",
        ),
    ],
    "Xiaoman/Views/CSVImportView.swift": [
        (
            "这个文件是空的（0 字节）。如果它在 iCloud 里，先点一下让它下载完再选。",
            "文件为空（0 字节）。若文件位于 iCloud，请待下载完成后再选择。",
        ),
        ("（表头没认出来，换个文件试试）", "（未能识别表头，请更换文件）"),
    ],
    "Xiaoman/Views/HomeView.swift": [
        (
            "快捷指令里加一个动作：「小满记账」→ 识别截图，双击手机背面就能自动入账；也可以点右上角 + 手动记一笔。",
            "在快捷指令中添加「小满记账」动作并绑定轻点背面，截图后将自动入账；也可点击右上角 + 手动新增。",
        ),
    ],
    "Xiaoman/Views/LedgerListView.swift": [
        ("换个关键词试试。", "请尝试其他关键词。"),
    ],
    "Xiaoman/Views/RewardView.swift": [
        (
            "两个码都是个人收款码，扫任意一个都行，金额随意。谢谢你愿意支持这个小工具 🙏",
            "以上均为个人收款码，可任选其一扫码，金额不限。感谢支持。",
        ),
    ],
    "Xiaoman/Views/SettingsView.swift": [
        ("这张图读不出来，换一张试试", "无法读取该图像，请更换后重试。"),
        (
            "每次识别结果都会先放进待确认列表，由你核对后保存。",
            "每次识别结果均先进入待确认列表，核对后保存。",
        ),
        (
            "截图会直接发给你选的这家服务商来读（\\(currentProvider.visionHint)），关掉开关就完全离线。",
            "截图将直接发送至所选服务商进行识别（\\(currentProvider.visionHint)）；关闭开关即恢复完全离线。",
        ),
        (
            "账目只存在这台手机上，没有账号。默认不联网；只有你自己打开上面的 AI 复核并填了 Key，才会把账单文字发给你选的那家大模型服务商。",
            "账目仅保存在本机，无账号体系。默认不联网；仅在开启 AI 复核并填写 Key 后，才会将账单内容发送至所选服务商。",
        ),
    ],
    "Xiaoman/Views/ShortcutGuideView.swift": [
        (
            "App 里带了两个系统动作：「小满记账」和「文本记账」。快捷指令把截屏画面的图片直接传给 App，App 内部识别完就落库，全程不落盘、不用切 App。",
            "应用内置两个系统动作：「小满记账」与「文本记账」。快捷指令将截屏图像直接传给应用，由应用内部完成识别并写入账本，全程不产生中间文件，也无需切换应用。",
        ),
        (
            "搜「文本记账」，把上一步的文字作为「账单文字」传进去。说「星巴克 28.5」这种带金额的句子识别率最高。",
            "搜索「文本记账」，将上一步的文本传入「账单文字」。包含金额与商户的完整语句识别率最高。",
        ),
        (
            "如果只想复制账单文字，用「文本记账」动作，把文字传进去即可；也可以用下面这条 URL 从别的 App 跳进来。",
            "若仅需传递文本，可使用「文本记账」动作；也可通过下方 URL 从其他应用唤起。",
        ),
        (
            "金额或商户识别不准时会进「待确认」，不会自动入账，确认页可以改。",
            "金额或商户识别存疑时进入「待确认」，不会自动入账，可在确认页修改。",
        ),
        (
            "截图时如果系统弹窗、通知横幅把金额挡住了，识别会失败。",
            "若截图时金额被系统弹窗或通知横幅遮挡，识别将失败。",
        ),
        (
            "轻点背面两下 → 屏幕闪一下截屏 → 顶部出现「已记账 ¥xx」的提示。",
            "轻点背面两次 → 触发截屏 → 顶部显示「已记账 ¥xx」。",
        ),
        (
            "如果没扣资产，说明没识别出是哪个账户，可以去确认页手动选。",
            "若未扣除资产，表示未能识别对应账户，可在确认页手动选择。",
        ),
        (
            "搜「听写文本」，语言选中文（普通话）。它会把你说的「午饭二十八」转成文字。",
            "搜索「听写文本」，语言选择中文（普通话），即可将语音转为文字。",
        ),
    ],
}

changed = 0
missing = []

for name, pairs in REPLACEMENTS.items():
    path = pathlib.Path(name)
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        if old not in text:
            missing.append((name, old[:30]))
            continue
        text = text.replace(old, new)
        changed += 1
    path.write_text(text, encoding="utf-8")

# 预算重置按钮：从大按钮改为小号文字按钮
budget = pathlib.Path("Xiaoman/Views/BudgetView.swift")
text = budget.read_text(encoding="utf-8")
old_button = (
    "                    Button {\n"
    "                        clearBeforeToday()\n"
    "                    } label: {\n"
    '                        Label("清空今日前预算", systemImage: "arrow.counterclockwise")\n'
    "                            .font(.system(size: 14, weight: .semibold, design: .rounded))\n"
    "                            .padding(.horizontal, 16)\n"
    "                            .padding(.vertical, 9)\n"
    "                    }\n"
    "                    .buttonStyle(.glass)\n"
)
new_button = (
    "                    Button {\n"
    "                        clearBeforeToday()\n"
    "                    } label: {\n"
    '                        Label("重置", systemImage: "arrow.counterclockwise")\n'
    "                            .font(.system(size: 12, weight: .medium, design: .rounded))\n"
    "                            .padding(.horizontal, 10)\n"
    "                            .padding(.vertical, 5)\n"
    "                    }\n"
    "                    .buttonStyle(.glass)\n"
    "                    .controlSize(.small)\n"
    "                    .fixedSize()\n"
)
if old_button in text:
    text = text.replace(old_button, new_button, 1)
    changed += 1
else:
    missing.append(("Xiaoman/Views/BudgetView.swift", "重置按钮"))
budget.write_text(text, encoding="utf-8")

print("替换:", changed)
if missing:
    print("未找到:")
    for name, sample in missing:
        print("  -", name, sample)
