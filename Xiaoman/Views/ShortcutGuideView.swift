import SwiftUI
import UIKit

struct ShortcutGuideView: View {

    @State private var copied = false

    private let textTemplate = "xiaoman://record?text="

    var body: some View {
        ZStack {
            AuroraBackground()
            List {
                introSection
                stepsSection
                voiceSection
                checkBudgetSection
                textSection
                pitfallSection
                checkSection
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Theme.cardFill)
        }
        .navigationTitle("快捷指令教程")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("截图直接交给应用，不产生中间文件")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("应用内置两个系统动作：「小满记账」与「文本记账」。快捷指令将截屏图像直接传给应用，由应用内部完成识别并写入账本，全程不产生中间文件，也无需切换应用。")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stepsSection: some View {
        Section("三步配好") {
            stepRow(
                number: 1,
                title: "新建快捷指令",
                detail: "打开「快捷指令」→ 右下角「+」→ 添加动作，先搜「截屏」并加入。"
            )
            stepRow(
                number: 2,
                title: "接上「小满记账」",
                detail: "再搜「小满记账」，选择 App 图标那个动作，把它排在「截屏」后面。上一步的图片会自动接进来，不需要额外设置变量。"
            )
            stepRow(
                number: 3,
                title: "绑到轻点背面",
                detail: "设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下 → 选刚做的快捷指令。"
            )
        }
    }

    private var voiceSection: some View {
        Section("语音记账") {
            stepRow(
                number: 1,
                title: "新建快捷指令，先加「听写文本」",
                detail: "搜索「听写文本」，语言选择中文（普通话），即可将语音转为文字。"
            )
            stepRow(
                number: 2,
                title: "再接「文本记账」",
                detail: "搜索「文本记账」，将上一步的文本传入「账单文字」。包含金额与商户的完整语句识别率最高。"
            )
            stepRow(
                number: 3,
                title: "要不要改成 Siri",
                detail: "在快捷指令中将其命名为「记一笔」，即可通过「嘿 Siri，记一笔」语音录入账单。"
            )
        }
    }

    private var checkBudgetSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("桌面看额度：查今日额度")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("App 里还有一个「查今日额度」动作，返回今天还能花多少、本月还剩多少。做成快捷指令后可以加到主屏，也能放进「今天」视图，效果接近小组件。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("把动作加进快捷指令 → 打开「在快捷指令中显示结果」→ 长按快捷指令选「添加到主屏幕」。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var textSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("另一种用法：文本记账")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("若仅需传递文本，可使用「文本记账」动作；也可通过下方 URL 从其他应用唤起。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(textTemplate)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = textTemplate
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        Text(copied ? "已复制" : "复制")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private var pitfallSection: some View {
        Section("容易踩的坑") {
            bullet("请在快捷指令中关闭「运行前询问」，否则每次执行均需确认。")
            bullet("「截屏」动作须置于「小满记账」之前，顺序颠倒将无法获取图像。")
            bullet("金额或商户识别存疑时进入「待确认」，不会自动入账，可在确认页修改。")
            bullet("若截图时金额被系统弹窗或通知横幅遮挡，识别将失败。")
            bullet("同一笔重复截一次不会重复记账（指纹去重）。")
        }
    }

    private var checkSection: some View {
        Section("验收清单") {
            bullet("轻点背面两次 → 触发截屏 → 顶部显示「已记账 ¥xx」。")
            bullet("打开应用首页可查看该笔账目，资产余额已同步扣减。")
            bullet("若未扣除资产，表示未能识别对应账户，可在确认页手动选择。")
        }
    }

    private func stepRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(width: 24, height: 24)
                .background(Theme.accent.opacity(0.35), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
