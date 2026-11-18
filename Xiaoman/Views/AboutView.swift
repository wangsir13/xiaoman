import SwiftUI
import UIKit

/// 关于：制作人信息、打赏入口、反馈渠道、版本信息
struct AboutView: View {

    private let email = "3200825024@qq.com"
    private let coolapkName = "阿甘左一"
    private let version = "1.0.0"

    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 16) {
                    producerCard
                    supportCard
                    feedbackCard
                    infoCard
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect(.regular.tint(Theme.accent.opacity(0.35)), in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: toast)
    }

    // MARK: - 制作人

    private var producerCard: some View {
        GlassCard(padding: 18) {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    Image("ProducerAvatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                        .overlay {
                            Circle().strokeBorder(Theme.hairline, lineWidth: 1)
                        }
                        .shadow(color: Theme.accent.opacity(0.35), radius: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("hy")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("制作人 · 独立开发")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 10))
                            Text("酷安 · \(coolapkName)")
                                .font(.system(size: 12, design: .rounded))
                        }
                        .foregroundStyle(Theme.accent)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Button {
                        copy(coolapkName, hint: "昵称已复制，去酷安搜「\(coolapkName)」")
                    } label: {
                        Label("复制昵称", systemImage: "doc.on.doc")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)

                    Button {
                        openCoolapk()
                    } label: {
                        Label("打开酷安", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    // MARK: - 打赏

    private var supportCard: some View {
        NavigationLink {
            RewardView()
        } label: {
            GlassCard(padding: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "FF9F0A"), Color(hex: "FF453A")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 42)
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("请我喝杯咖啡")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("支付宝 / 微信收款码，随意扫")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 反馈

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "反馈与建议")

            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("用着不顺手、识别不准、想要什么功能，都可以直接发邮件。")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accent)
                        Text(email)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        Button {
                            sendMail()
                        } label: {
                            Label("发邮件", systemImage: "paperplane.fill")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.glassProminent)

                        Button {
                            copy(email, hint: "邮箱已复制")
                        } label: {
                            Label("复制地址", systemImage: "doc.on.doc")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    // MARK: - 版本信息

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "版本")

            GlassCard(padding: 16) {
                VStack(spacing: 10) {
                    infoRow("版本", "\(version) (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"))")
                    Divider().opacity(0.2)
                    infoRow("Bundle ID", "com.xiaoman.app")
                    Divider().opacity(0.2)
                    infoRow("最低系统", "iOS 26.0")
                    Divider().opacity(0.2)
                    infoRow("URL Scheme", "xiaoman://")
                    Divider().opacity(0.2)
                    infoRow("数据位置", "本机 Application Support/Xiaoman")
                }
            }

            Text("账目只存在这台手机上，没有账号、没有云端。默认完全离线；只有你自己打开「AI 复核」并填了 Key，才会把账单文字发给你选的那家模型服务商（DeepSeek / GPT / Claude / 豆包）。")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - 动作

    private func copy(_ text: String, hint: String) {
        UIPasteboard.general.string = text
        showToast(hint)
    }

    private func openCoolapk() {
        guard let url = URL(string: "coolapk://") else { return }
        // 不查 canOpenURL（那需要 LSApplicationQueriesSchemes），直接试打开，失败再退回复制
        UIApplication.shared.open(url) { ok in
            guard !ok else { return }
            DispatchQueue.main.async {
                copy(coolapkName, hint: "酷安没装，昵称已复制，去 App Store 搜「酷安」")
            }
        }
    }

    private func sendMail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "小满 反馈（\(version)）"),
            URLQueryItem(name: "body", value: "\n\n—\n设备：\(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion)")
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url) { ok in
            guard !ok else { return }
            DispatchQueue.main.async {
                copy(email, hint: "没装邮件 App，地址已复制")
            }
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run { toast = nil }
        }
    }
}
