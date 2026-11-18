# 出包、签名、安装

本文解决三件事：**ipa 从哪来**、**怎么签名**、**7 天之后怎么办**。

---

## 一、为什么需要签名

iOS 不允许安装未经签名的 App。任何 ipa 装进 iPhone 前都必须被一份**有效的 Apple 签名**包起来，签名里绑定：

- 一个 Apple ID（免费或付费开发者账号）
- 一个 Bundle ID
- 一份描述文件（provisioning profile），里面写明了有效期和设备 UDID

所以 CI 产出的 `Xiaoman-unsigned.ipa` 只是「打好包的二进制」，最后一公里的签名必须在你自己的电脑/手机上用你自己的 Apple ID 完成。这不是缺了什么步骤，而是苹果的设计。

---

## 二、出 ipa

### 方式 1：GitHub Actions（不需要 Mac，推荐）

1. 新建一个 GitHub 仓库（Public 更省 Actions 额度，Private 也行）。
2. 把本目录内容（`project.yml`、`Support/`、`Xiaoman/`、`.github/` 等）推到仓库根目录。注意 `.github/workflows/build-ipa.yml` 必须以这个路径存在，名字别改。
3. 仓库 → **Actions** → 左侧 **Build unsigned IPA** → **Run workflow**。
4. 运行结束后，在该次运行页面底部 **Artifacts** 下载 `Xiaoman-unsigned-ipa`，解压得到 `Xiaoman-unsigned.ipa`。

工作流做的事：`macos-26` runner（自带 iOS 26 SDK，工作流会先校验 SDK ≥ 26）→ 装 XcodeGen → 生成 `.xcodeproj` → `xcodebuild` 关掉签名编 Release → 把 `.app` 塞进 `Payload/` 打包成 ipa → 上传 artifact。

> 注意：App 的部署目标是 **iOS 26.0**（用到 App Intents 直传截图和 Liquid Glass），所以你的 iPhone 必须升到 iOS 26 才能装。

额度参考：Public 仓库的 Actions 免费；Private 仓库每月 2000 分钟，macOS runner 按 10 倍计费，一次构建约 4 分钟 → 算 40 分钟额度，够跑 50 次。

想改版本号，改 `project.yml` 里的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`，或者改工作流里加 `-xcconfig`。

### 方式 2：本地 Mac

```bash
brew install xcodegen
cd xiaoman
xcodegen generate

# 出未签名 ipa
xcodebuild -project Xiaoman.xcodeproj -scheme Xiaoman \
  -configuration Release -destination "generic/platform=iOS" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/Xiaoman.app Payload/
rm -rf Payload/Xiaoman.app/_CodeSignature
zip -qry -X Xiaoman-unsigned.ipa Payload
```

或者直接在 Xcode 里选真机、选自己的 Team、Run，能跑起来就说明代码没问题。

---

## 三、签名方式对比

| 方式 | 需要电脑 | 有效期 | 自动续签 | 适合谁 |
| --- | --- | --- | --- | --- |
| **AltStore**（Windows/Mac） | 是，且要同一 Wi-Fi | 7 天 | 需 AltServer 常开 | 大多数人，最稳 |
| **SideStore** | 只需一次电脑 | 7 天 | 是（装 StosVPN 后手机自己续） | 不想开电脑 |
| **Sideloadly** | 是 | 7 天 | 否 | 临时装一次 |
| **TrollStore** | 否 | 永久 | 不需要 | iOS 14.0–16.6.1 / 17.0 且能装 TrollStore 的设备 |
| **个人开发者证书**（$99/年） | 是 | 1 年 | 不需要 | 长期用、想省心 |
| **企业证书 / 共享证书** | 否 | 随时被封 | — | 不建议：掉签就废，且有风险 |
| **爱思助手 / PP 助手** | 是 | 7 天 | 部分支持 | 已经装了这些工具的人 |

自签场景下，Apple ID 免费证书的硬限制：

- 有效期 **7 天**
- 同时最多 **3 个**自签 App
- 每周最多注册 **10 个** App ID
- 不能推送（无 `aps-environment`）、不能 iCloud、不能用 App Groups
- 第一次安装后要在「设置 → 通用 → VPN与设备管理」里信任证书

以上限制都不影响本 App：它不推送、不 iCloud、不联网。

---

## 四、AltStore 详细步骤（Windows）

1. 从 [altstore.io](https://altstore.io/) 下载 Windows 版 AltServer 和 **iTunes**、**iCloud** 的桌面版（注意：要 Apple 官网下载的版本，Microsoft Store 版不行）。
2. 装好后运行 AltServer，任务栏托盘图标 → **Install AltStore** → 选你的 iPhone → 输入 Apple ID。
   - 这一步会在手机上装一个叫 AltStore 的 App，同时把 AltStore 自己的签名搞定。
   - 首次需要在手机上「设置 → 通用 → VPN与设备管理 → 信任」。
3. 手机和电脑连同一个 Wi-Fi，AltStore 里登录同一个 Apple ID（AltStore 设置里）。
4. 把 `Xiaoman-unsigned.ipa` 传到手机（隔空投送、iCloud Drive、微信文件传输都行），在 AltStore 的 **My Apps** 页点左上角 **+**，选这个 ipa。
5. 等进度条走完，桌面出现「小满」→ 打开 → 允许。
6. 手机信任证书：「设置 → 通用 → VPN与设备管理 → Apple Development: 你的邮箱 → 信任」。

之后每 7 天，AltStore 会在同一 Wi-Fi 下自动续签。**续签是覆盖安装，数据不会丢**；但如果你手动删掉 App 再装，沙盒被清空，历史账目就没了。所以要么别删，要么先导出 CSV。

---

## 五、SideStore（不想让电脑一直开着）

SideStore 是 AltStore 的分支，签名在手机上完成，通过一个本地 VPN（StosVPN）把签名请求转给 Apple。

流程：

1. 电脑上一次性的 AltServer 操作，把 **SideStore** 装到手机（用的是 SideStore 自己的 ipa，不是我们的）。
2. 手机装 **StosVPN**（App Store 有），打开并保持连接。
3. SideStore 里登录 Apple ID → 导入 `Xiaoman-unsigned.ipa` → 安装。
4. 之后 SideStore 会在后台自己续签，7 天一次，不需要电脑。

StosVPN 是个本地回环 VPN，不开就无法续签。iOS 会显示 VPN 图标，属于正常现象。

---

## 六、TrollStore（永久，但有版本门槛）

TrollStore 利用系统级漏洞（CoreTrust）让 App 永久有效、不占 3 个限额、不需要证书。

支持范围（会变，装之前自己查 [github.com/opa334/TrollStore](https://github.com/opa334/TrollStore)）：

- iOS 14.0 beta 2 – 15.5 beta 4
- iOS 15.6 beta 1 – 16.6.1（部分版本需要特定安装方法）
- iOS 17.0

装法概要：先装 TrollStore Helper（走 Safari 安装或 JIT 方案）→ TrollStore 里导入 ipa → **Install**。

装完不需要续签，也不需要信任证书。**但 TrollStore 安装的 App 同样无法使用 iCloud/推送**——本 App 不需要这些，所以完全够用。

---

## 七、常见错误

| 报错 / 现象 | 原因 | 处理 |
| --- | --- | --- |
| 「无法安装此 App，因为无法验证其完整性」 | ipa 没签名，或签名在中途失败 | 用它签名工具重签，别直接装未签名 ipa |
| 「未受信任的开发者」 | 证书没在设置里信任 | 设置 → 通用 → VPN与设备管理 → 信任 |
| 装了但打不开，闪退 | 签名时 Bundle ID 冲突，或证书过期 | 换一个 Bundle ID 重新签名 |
| AltStore 提示「Could not connect to AltServer」 | 手机电脑不同 Wi-Fi；防火墙拦了 | 同一网络；Windows 防火墙放行 AltServer；或换 USB 方式 |
| 7 天后打开就闪退 | 描述文件过期 | 打开 AltStore/SideStore 续签，或重新装一次（覆盖装不丢数据） |
| SideStore 续签失败 | StosVPN 没开 | 打开 StosVPN 再点 Refresh All |
| Actions 里找不到 artifact | 没登录 GitHub；或构建失败 | 登录后看运行日志 |
| 构建失败在 `xcodegen` | 仓库路径不对（`project.yml` 不在根目录） | 把 `xiaoman/` 的内容放到仓库根，而不是把 `xiaoman/` 整个目录放进去 |
| 构建失败在 `xcodebuild` | 代码有编译错误 | 看日志里的 `error:` 行；本地有 Mac 的话直接 Xcode 打开更快 |

---

## 八、换机、升级、别丢数据

数据在 App 沙盒里，只有两种情况会丢：

1. 卸载 App（包括「删除 App」后重装）
2. 手机重置 / 换新机且没恢复备份

所以：

- **续签 = 覆盖安装**，不丢数据。
- 换机前：App 里「设置 → 备份与恢复 → 导出到「文件」」存一份 JSON；新手机装好后「从备份恢复」就能整套搬回来。
- 想定期备份：用「备份与恢复」导 JSON（含全部账目、资产、预算、自定义分类），或用「导出 CSV」拿去 Excel 分析，也可以从 Xcode 设备容器下载 `Application Support/Xiaoman/*.json`。

如果你想加别的备份方式，改 `LedgerStore.save()` 顺手往 Documents 写一份即可。
