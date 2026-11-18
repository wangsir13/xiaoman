# 小满

轻点手机背面两下 → 快捷指令截屏 → **直接把这张截图交给 App**（不存文件、不开 App）→ App 用系统自带的 Vision 离线识别金额、商户、时间、付款方式 → 自动记到对应资产 → 首页看预算和分类饼图。

为一个很具体的需求做的：**不想再手动敲金额，也不想把账单截图上传到任何服务器**。整套流程跑在手机本地，默认不联网（只有你自己在设置里打开 AI 复核、填了某家大模型的 Key，才会联网）。

- 部署目标：**iOS 26.0+**（用 App Intents 直接接收截图对象 + 真 Liquid Glass 界面）
- 依赖：零第三方库（只用 SwiftUI / AppIntents / Vision / UserNotifications）
- 分发：GitHub Actions 出**未签名 ipa**，你自己用 Apple ID 签名安装

---

## 一、它能干什么

| 能做 | 说明 |
| --- | --- |
| 截图直传 | 快捷指令的「小满记账」动作接收图像，App 内部识别，**不需要「存储文件」也不再从相册挑图** |
| 全自动或确认 | 把握度 ≥ 0.8 且不重复就直接入账；否则进「待确认」列表，改完再存 |
| 离线 OCR | Vision 框架，中文优先，飞行模式也能用 |
| 金额 / 商户 / 时间 / 方向 | 规则解析，微信、支付宝、云闪付、美团、京东、银行短信都能吃 |
| 资产账本 | 银行卡 / 信用卡 / 电子钱包 / 借款 / 现金，支出收入自动从对应资产增减 |
| 自动归类 | 「星巴克」→ 餐饮，「地铁」→ 交通；也能自建分类（图标 + 颜色） |
| 预算 | 月预算按天均分，花不完留到第二天，超支从第二天扣；可开「从今日起」，填预算当天才开始计额度，不会把前面几天堆到今天 |
| 饼图 | 本月支出分类占比（环形图）+ 每日柱状图 |
| 重复保护 | 同来源 + 同金额 + 同商户 + 同一分钟会提示「疑似重复」 |
| AI 复核（可选） | 本地规则先解析，再把文字发给所选的大模型（DeepSeek / GPT / Claude / 豆包 / 自定义接口）补字段；不填 Key 就完全离线 |
| 月报长图 | 本月收支 + 分类占比 + 每日柱状排成一张竖图，一键分享 |
| 记账日历 | 一年热力图、连续天数、花得最多的一天 |
| 历史账单导入 | 微信 / 支付宝导出的 CSV 直接吃进来，自动去重 |
| 外观 | 跟随系统 / 浅色 / 深色三档，玻璃卡片和背景光斑两种外观都适配 |
| 图标 | 浅色（米纸红印）/ 深色（墨绿红印）/ 着色三套 1024 图标，随系统外观自动切换 |
| 账本锁 | Face ID / 设备密码解锁，锁屏时看不到任何数字 |
| 备份与恢复 | 整份账本导成一个 JSON，换机或重新签名之前先存一份 |
| 语音记账 | 快捷指令「听写文本 → 文本记账」，说一句「午饭 28」就入账 |
| 本地存储 | JSON 存在 App 沙盒，卸载即清空，没有任何云端 |
| CSV 导出 | 带 UTF-8 BOM，Excel / Numbers 双击不乱码 |
| 关于页 | 制作人信息、打赏收款码（支付宝 / 微信）、反馈邮箱与建议入口 |

**做不到**（受免费自签证书限制，不是代码问题）：

- 不能 iCloud 同步、不能远程推送（本地通知可以）
- 免费证书 7 天到期，需要重新签名（详见 [docs/signing-and-install.md](docs/signing-and-install.md)）
- 不自动读微信/支付宝的账本（那需要它们开放接口，现实中没有）

---

## 二、为什么必须 iOS 26

- **App Intents 接收图像**：`RecordFromScreenshotIntent` 的参数是 `IntentFile`，快捷指令把截图对象直接传进来，App 在内存里 `UIImage(data:)` 就能拿到，**全程不落地**——这是老版本只能「先存文件再扫描」的根本原因。
- **Liquid Glass**：`.glassEffect(_:in:)`、`GlassEffectContainer`、`.buttonStyle(.glass)` 是 iOS 26 才有的 API，界面按新版「健康」App 的层次做的。
- 代价：iPhone 需要 iOS 26；CI 用 `macos-26` runner + iOS 26 SDK（工作流里会校验 SDK 版本，低于 26 直接报错退出）。

---

## 三、三步拿到 ipa

前提：一个 GitHub 账号（免费）。不需要 Mac。

1. 把 `xiaoman/` 这个目录推到一个 GitHub 仓库（目录内容就是这个仓库的根，**`.github/` 必须在根目录**）。
2. 打开仓库的 **Actions** 标签页，左侧选 **Build unsigned IPA**，点 **Run workflow**。
3. 等 3～6 分钟，进这次运行记录，底部 **Artifacts** 下载 `Xiaoman-unsigned-ipa`，解压得到 `Xiaoman-unsigned.ipa`。

工作流文件在 `.github/workflows/build-ipa.yml`，`push` 到 `main` 也会自动跑一次。

> 未签名 ipa 不能直接装进 iPhone，必须先用签名工具用你自己的 Apple ID 签一遍。见下一节。

---

## 四、装到 iPhone

最短路径（Windows 电脑）：

1. 装 [AltStore](https://altstore.io/)（Windows 版需要 iTunes 和 iCloud 的桌面版组件）。
2. AltServer 登录你的 Apple ID。
3. 把下载的 `Xiaoman-unsigned.ipa` 拖进 AltStore，或者用 AltStore 的「+」选择这个文件。
4. 手机上：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书。
5. 打开 App。

免费 Apple ID 的限制：**7 天**后过期、最多同时 3 个自签 App、无远程推送/iCloud。

长期方案（SideStore 自动续签、TrollStore 永久安装、企业证书）和对比表在 [docs/signing-and-install.md](docs/signing-and-install.md)。

首次打开 App 后：

1. 进「设置 → 记账 → 高把握度自动记账」，按自己习惯决定要不要开（默认开）。
2. 进「预算」设一个月预算，打开每日提醒（需要允许通知）。
3. 按 [docs/shortcut-recipes.md](docs/shortcut-recipes.md) 配快捷指令：**新建快捷指令 → 加「截屏」→ 加「小满记账」→ 绑定轻点背面两下**。
4. 回首页，用「设置 → 记账 → 粘贴文本识别一笔」贴一段账单文字，确认能识别出金额和商户；也可以直接对账单截屏跑一遍快捷指令。

---

## 五、工作流程

```
支付成功页
   │  轻点背面两下
   ▼
快捷指令：截屏（拿到 UIImage）
   │
   ▼
动作「小满记账」（App Intent，RecordFromScreenshotIntent）
   │  IntentFile 直接进内存，不写文件、不需要切到 App
   ▼
Vision OCR → BillParser 解析 → 猜资产（关键词命中「微信钱包 / 支付宝 / 银行卡 …」）
   │
   ├─ 把握度 ≥ 0.8 且不重复 → 直接入账 + 顶部提示 + 超支时立刻本地通知
   └─ 否则 → 待确认列表（改金额 / 商户 / 分类 / 资产 / 时间）
   ▼
数据落盘 Application Support/Xiaoman/{transactions,assets,budget,categories}.json
   ▼
首页（本月支出 / 今日预算 / 分类饼图 / 资产余额 / 最近记录）
```

补一条备用通道：`xiaoman://record?text=<URL 编码的账单文字>` 仍然可用（文本记账动作、其他 App、浏览器都能触发），`src / amount / merchant / cat / ts / note` 可覆盖字段。

---

## 六、目录结构

```
xiaoman/
├── project.yml                     # XcodeGen 工程描述（仓库里不放 .xcodeproj）
├── Support/
│   └── Info.plist                  # URL Scheme、竖屏锁定
├── .github/workflows/build-ipa.yml # 云端出未签名 ipa（macos-26 + iOS 26 SDK 校验）
├── Xiaoman/
│   ├── XiaomanApp.swift          # 入口：onOpenURL
│   ├── Intents/RecordIntent.swift  # App Intent：截图 / 文本两个动作 + AppShortcuts
│   ├── Models/                     # Transaction / ImportDraft / Asset / Budget / 分类表
│   ├── Parsing/BillParser.swift    # 核心：正则解析金额、商户、时间、方向
│   ├── Store/LedgerStore.swift     # 4 份 JSON 落盘、待确认队列、资产余额、预算统计
│   ├── Import/DeepLink.swift       # xiaoman:// 深链接
│   ├── OCR/ImageOCR.swift          # Vision 文字识别
│   ├── Notification/BudgetNotifier.swift  # 本地通知（每日剩余 / 超支）
│   ├── Export/                     # CSV 生成 + 系统分享面板
│   ├── Views/                      # 首页、账单、资产、预算、饼图、确认、设置、教程、关于、打赏、备份
│   └── Assets.xcassets/            # App 图标、主题色、作者头像、两个收款码
├── docs/
│   ├── shortcut-recipes.md         # 快捷指令配方与排错
│   └── signing-and-install.md      # 出 ipa、签名、续签
├── XiaomanTests/                 # XCTest（金额、解析、CSV、指纹）
└── tools/
    ├── make_icon.py                # 生成 1024 图标（需要 Pillow）
    ├── make_brand_assets.py        # 生成作者头像与两个收款码的 1x/2x/3x imageset
    ├── parser_check.py             # 用 Python 复刻解析器，拿 12 段真实账单文本跑一遍
    ├── verify.py                   # 静态自检：括号平衡、配置一致性、符号引用
    └── check_escapes.py            # 检查 Swift 正则里的反斜杠有没有写坏
```

工程文件不进版本库：CI 和本地都用 `xcodegen generate` 现生成，避免 `.xcodeproj` 的合并冲突。

---

## 七、识别能力边界

BillParser 是规则解析，不是大模型。它的行为是：

- **金额**优先级：`实付款 / 支付金额 / 合计 …` 后面的数字 → 带 `¥` 的数字 → `xx元` → 单独成行的 `12.34`（支付宝那种带负号的 `-28.50` 也算）→ 全文第一个两位小数。日期、时间、订单号会先被抹掉，不会被当成金额。
- **商户**优先级：`收款方 / 商户全称 / 商家名称` → `付款给 / 转账给` → `来自 / 对方` → `向…消费` → 逐行找最像名字的一行（会砍掉「支付成功」「订单号」这类词，拒绝纯数字和带时间的行）。
- **方向**：出现「收款成功 / 已到账 / 入账 / 退款成功」或 `+¥` 记收入，否则支出。
- **时间**：`2026-11-18 10:22:31` / `11月18日 10:22` / `今天 10:22` / 裸 `10:22`，都没有就用当前时间。
- **资产**：按资产的关键词命中打分（关键词越长权重越高，资产名命中额外加分），取最高分；识别不出就空着，确认页里手选。
- **把握度**：金额 +0.45、来源已知 +0.15、商户 +0.15、时间 +0.05，起点 0.2。低于 0.8 一律进确认页。
- **AI 复核（可选）**：本地规则先跑，再用所选的大模型（DeepSeek / GPT / Claude / 豆包）把原文整段看一遍，补金额/商户/分类/资产/时间。模型给的字段优先，没给的就保留本地结果。入口在「设置 → AI 复核」。

想调规则就改 `Xiaoman/Parsing/BillParser.swift`；改完记得跑 `python tools/check_escapes.py` 看一眼反斜杠——Swift 的 raw string `#"..."#` 里 `\\` 和 `\` 差别很大，这是最容易写错的地方。

---

## 八、隐私

- 默认不联网：不打开「AI 复核」时，代码里不会发任何请求。
- 可选 AI 复核：设置里填了自己某个大模型的 Key 后，才会把**识别出来的文字**（不是图片）发到那家服务商的接口补字段；Key 存在本机，随 App 卸载一起消失。
- 截图不落地：快捷指令把图像对象交给 App Intent，OCR 完就释放，磁盘上没有截图文件。
- 数据只在 App 沙盒：`Application Support/Xiaoman/*.json`。
- 你不导出，数据就不会离开这台手机；换机或卸载前请自己导出 CSV。

---

## 九、本地开发（可选）

需要 Mac + Xcode 26（带 iOS 26 SDK）：

```bash
brew install xcodegen
cd xiaoman
xcodegen generate
open Xiaoman.xcodeproj
```

选自己的开发者账号签名，直接 Run 到真机（模拟器没有「轻点背面」，但可以手动跑快捷指令动作）。

---

## 十、测试与自检

解析器和金额换算是最容易出错的地方（正则、全角半角、带负号的金额、千分位），所以有三层保护：

**1. XCTest 单元测试**（`XiaomanTests/`）

覆盖金额换算与往返、全角归一化、微信 / 支付宝 / 银行 / 云闪付 / 美团 / 京东 / 收入 / 无货币符号 / 千分位 / 无金额负例、自动归类、CSV 转义与 BOM、去重指纹。

CI 里会在可用的 iPhone 模拟器上跑一遍（`.github/workflows/build-ipa.yml` 的「运行单元测试」步骤）。这一步设了 `continue-on-error`，**测试挂了也照样出 ipa**，但日志里能看到哪个断言没过。

**2. Python 复刻校验**（`tools/parser_check.py`）

没有 Mac 也能跑。它把 `BillParser.swift` 的规则逐条移植成 Python，喂 12 段真实账单文本，打印每段的金额 / 方向 / 商户 / 分类 / 时间 / 把握度：

```bash
python tools/parser_check.py
```

改 `BillParser.swift` 时请同步改这个脚本——它是你在 Windows 上唯一能"运行"解析器的方式。

**3. 静态自检**（`tools/verify.py`）

```bash
python tools/verify.py
```

检查所有 `.swift` 的括号平衡（带字符串/注释/raw string/插值状态机）、`Info.plist` 与 xcassets 合法性、图标尺寸、`project.yml` 与工作流的名字/部署目标是否互相对得上、App Intent 是否存在、View 里调用的 store 方法与视图是否真有定义。

---

## 十一、许可

个人自用随便改。第三方素材？没有，图标是 `tools/make_icon.py` 用 Pillow 现画的。
