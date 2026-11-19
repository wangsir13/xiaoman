import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

REPLACEMENTS = {
    "Xiaoman/Intents/RecordIntent.swift": [
        ("读出今天还能花多少，以及本月剩余预算。", "查询今日剩余额度与本月剩余预算。"),
        ("还没设置月度预算，打开 App 的「预算」页填一个数。", "尚未设置月度预算，请在「预算」页配置。"),
    ],
    "Xiaoman/Views/AboutView.swift": [
        ("支付宝 / 微信收款码，随意扫", "支付宝 / 微信收款码"),
    ],
    "Xiaoman/Views/BudgetView.swift": [
        ("超支 \\(Money.plain(-today.remainingCents))，明天额度先扣", "超支 \\(Money.plain(-today.remainingCents))，将从明日额度扣除"),
        ("通知被关闭了，去系统设置里打开「小满」的通知。", "通知权限已关闭，请在系统设置中开启「小满」的通知。"),
    ],
    "Xiaoman/Views/MonthReportView.swift": [
        ("这个月还没有支出记录。", "本月暂无支出记录。"),
    ],
    "Xiaoman/Views/SettingsView.swift": [
        ("这台设备还没设置锁屏密码，所以暂时用不了；先去系统设置里加一个密码。", "本机尚未设置锁屏密码，暂无法启用；请在系统设置中设置密码。"),
        ("先给手机设置一个锁屏密码，才能开账本锁", "请先在系统设置中设置锁屏密码，方可启用账本锁。"),
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
