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
                Text("截图直接交给 App，不存文件")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("App 里带了两个系统动作：「小满记账」和「文本记账」。快捷指令把截屏画面的图片直接传给 App，App 内部识别完就落库，全程不落盘、不用切 App。")
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
                detail: "搜「听写文本」，语言选中文（普通话）。它会把你说的「午饭二十八」转成文字。"
            )
            stepRow(
                number: 2,
                title: "再接「文本记账」",
                detail: "搜「文本记账」，把上一步的文字作为「账单文字」传进去。说「星巴克 28.5」这种带金额的句子识别率最高。"
            )
            stepRow(
                number: 3,
                title: "要不要改成 Siri",
                detail: "在快捷指令里给它起名「记一笔」，之后对 Siri 说「嘿 Siri，记一笔」就能直接说账单。"
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
                Text("如果只想复制账单文字，用「文本记账」动作，把文字传进去即可；也可以用下面这条 URL 从别的 App 跳进来。")
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
            bullet("快捷指令里「询问是否运行」关掉，否则每次都要点确认。")
            bullet("截屏动作要在「小满记账」之前，顺序反了会拿不到图片。")
            bullet("金额或商户识别不准时会进「待确认」，不会自动入账，确认页可以改。")
            bullet("截图时如果系统弹窗、通知横幅把金额挡住了，识别会失败。")
            bullet("同一笔重复截一次不会重复记账（指纹去重）。")
        }
    }

    private var checkSection: some View {
        Section("验收清单") {
            bullet("轻点背面两下 → 屏幕闪一下截屏 → 顶部出现「已记账 ¥xx」的提示。")
            bullet("打开 App 首页，能看到这笔账，并且资产余额已经扣减。")
            bullet("如果没扣资产，说明没识别出是哪个账户，可以去确认页手动选。")
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
