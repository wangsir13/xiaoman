import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

REPLACEMENTS = {
    "Xiaoman/Security/AppLock.swift": [
        ("解锁你的记账本", "验证以解锁账本"),
    ],
    "Xiaoman/Views/ShortcutGuideView.swift": [
        ("先给手机设置一个锁屏密码，才能开账本锁", "请先在系统中设置锁屏密码，方可启用账本锁。"),
        ("快捷指令里「询问是否运行」关掉，否则每次都要点确认。", "请在快捷指令中关闭「运行前询问」，否则每次执行均需确认。"),
        ("截屏动作要在「小满记账」之前，顺序反了会拿不到图片。", "「截屏」动作须置于「小满记账」之前，顺序颠倒将无法获取图像。"),
        ("打开 App 首页，能看到这笔账，并且资产余额已经扣减。", "打开应用首页可查看该笔账目，资产余额已同步扣减。"),
        ("截图直接交给 App，不存文件", "截图直接交给应用，不产生中间文件"),
    ],
    "Xiaoman/Views/SettingsView.swift": [
        ("把握度 ≥ 80% 且不重复时直接入账，其余先进待确认列表。", "置信度 ≥ 80% 且不重复时直接入账，其余进入待确认列表。"),
        ("还没设置月度预算，打开 App 的「预算」页填一个数。", "尚未设置月度预算，请在「预算」页配置。"),
        ("跟随系统最省心；深色模式下玻璃和光斑的层次更明显。", "跟随系统设置。深色模式下玻璃与光斑层次更明显。"),
        ("通知被关闭了，去系统设置里打开「小满」的通知。", "通知权限已关闭，请在系统设置中开启「小满」的通知。"),
    ],
    "Xiaoman/Views/RewardView.swift": [
        ("支付宝 / 微信收款码，随意扫", "支付宝 / 微信收款码"),
    ],
    "Xiaoman/Views/AboutView.swift": [
        ("昵称已复制，去酷安搜「\\(coolapkName)」", "昵称已复制，可在酷安搜索「\\(coolapkName)」"),
        ("没装邮件 App，地址已复制", "未检测到邮件应用，地址已复制"),
        ("酷安没装，昵称已复制，去 App Store 搜「酷安」", "未检测到酷安，昵称已复制，可在 App Store 搜索「酷安」"),
    ],
    "Xiaoman/Views/MonthReportView.swift": [
        ("图片只在本机生成，不会上传。发朋友圈、发群里都行。", "图像仅在本机生成，不会上传。"),
        ("这张图渲染失败了，换成浅一点的内容再试。", "图像渲染失败，请更换内容后重试。"),
    ],
    "Xiaoman/Views/BackupView.swift": [
        ("这个备份是空的（0 字节）。", "备份文件为空（0 字节）。"),
        ("这个备份是空的（0 字节），可能 iCloud 还没下载完。", "备份文件为空（0 字节），可能尚未从 iCloud 下载完成。"),
        ("选一个之前导出的 xiaoman-backup-*.json，会覆盖当前数据。", "选择此前导出的 xiaoman-backup-*.json，将覆盖当前数据。"),
    ],
    "Xiaoman/Views/CSVImportView.swift": [
        ("这个文件是空的（0 字节）。", "文件为空（0 字节）。"),
    ],
    "Xiaoman/Views/HomeView.swift": [
        ("这个月还没有支出记录。", "本月暂无支出记录。"),
        ("超支 \\(Money.plain(-today.remainingCents))，明天额度先扣", "超支 \\(Money.plain(-today.remainingCents))，将从明日额度扣除"),
        ("读出今天还能花多少，以及本月剩余预算。", "查询今日剩余额度与本月剩余预算。"),
    ],
    "Xiaoman/Models/Backup.swift": [
        ("文件里没有任何账目或资产，不像小满的备份", "文件中不含任何账目或资产，不是有效的备份文件"),
    ],
    "Xiaoman/Import/AIParser.swift": [
        ("模型没给出内容。", "模型未返回内容。"),
    ],
}

changed = 0
missing = []

for name, pairs in REPLACEMENTS.items():
    path = pathlib.Path(name)
    if not path.exists():
        missing.append((name, "文件不存在"))
        continue
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        if old not in text:
            missing.append((name, old[:28]))
            continue
        text = text.replace(old, new)
        changed += 1
    path.write_text(text, encoding="utf-8")

print("替换:", changed)
if missing:
    print("未找到:")
    for name, sample in missing:
        print("  -", name, "|", sample)
