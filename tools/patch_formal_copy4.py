import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

REPLACEMENTS = {
    "Xiaoman/Views/SettingsView.swift": [
        (
            "DeepSeek 只有文本模型，会先 OCR 再交给它复核；想直接读图请换 OpenAI / Claude / 豆包。",
            "DeepSeek 仅提供文本模型，将先执行 OCR 再进行文字复核；如需直接识图，请改用 OpenAI / Claude / 豆包。",
        ),
        (
            "在快捷指令里给它起名「记一笔」，之后对 Siri 说「嘿 Siri，记一笔」就能直接说账单。",
            "在快捷指令中将其命名为「记一笔」，即可通过「嘿 Siri，记一笔」语音录入账单。",
        ),
        (
            "把 \\(store.transactions.count) 笔账、\\(store.assets.count) 个资产、预算和分类打包成一个 JSON。续签或换手机前导一份，换回来时直接恢复。",
            "将 \\(store.transactions.count) 笔账目、\\(store.assets.count) 个资产、预算与分类导出为一个 JSON 文件；续签或更换设备前导出，恢复时直接导入。",
        ),
        (
            "把以前记的账一次补齐。微信：「我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单」；支付宝：「我的 → 账单 → 右上角 → 开具交易流水」。导出后选那个 CSV / xlsx（或微信给的 zip）文件。",
            "可批量补录历史账单。微信：「我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单」；支付宝：「我的 → 账单 → 右上角 → 开具交易流水」。导出后选择对应的 CSV / xlsx（或微信导出的 zip）文件。",
        ),
    ],
    "Xiaoman/Views/AssetsView.swift": [
        (
            "期初余额可以是负数，例如储蓄卡透支；键盘上的减号可以直接输入。",
            "期初余额可为负数（如储蓄卡透支），可直接输入减号。",
        ),
    ],
    "Xiaoman/Views/ImportReviewView.swift": [
        (
            "识别结果仅供参考，保存前请核对金额。原始文字会随账目一起存档，方便以后回溯。",
            "识别结果仅供参考，保存前请核对金额。原始文本将随账目一并存档，便于日后追溯。",
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
            missing.append((name, old[:28]))
            continue
        text = text.replace(old, new)
        changed += 1
    path.write_text(text, encoding="utf-8")

print("替换:", changed)
for name, sample in missing:
    print("  miss:", name, "|", sample)
