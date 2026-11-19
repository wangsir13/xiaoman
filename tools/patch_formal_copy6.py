import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

REPLACEMENTS = {
    "Xiaoman/Views/BackupView.swift": [
        (
            "提示：免费证书 7 天过期，续签时用同一个 Bundle ID 覆盖安装不会丢数据；只有卸载重装才会清空，所以「删 App 之前先备份」是最省心的习惯。",
            "提示：免费证书 7 天过期。续签时使用同一 Bundle ID 覆盖安装不会丢失数据；仅卸载重装会清空数据，建议在卸载前先导出备份。",
        ),
    ],
    "Xiaoman/Views/HomeView.swift": [
        ("还没有记录", "暂无记录"),
    ],
    "Xiaoman/Views/LedgerListView.swift": [
        ("还没有记录", "暂无记录"),
    ],
}

changed = 0
for name, pairs in REPLACEMENTS.items():
    path = pathlib.Path(name)
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        if old in text:
            text = text.replace(old, new)
            changed += 1
        else:
            print("  miss:", name, "|", old[:24])
    path.write_text(text, encoding="utf-8")

print("替换:", changed)
