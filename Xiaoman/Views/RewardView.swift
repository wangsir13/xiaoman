import SwiftUI
import UIKit

/// 打赏页：支付宝 / 微信两个收款码，切换查看，可分享或存到相册
struct RewardView: View {

    private enum Channel: String, CaseIterable, Identifiable {
        case alipay = "支付宝"
        case wechat = "微信"
        var id: String { rawValue }
        var imageName: String { self == .alipay ? "AlipayQR" : "WechatQR" }
        var accent: Color { self == .alipay ? Color(hex: "1677FF") : Color(hex: "07C160") }
    }

    @State private var channel: Channel = .alipay
    @State private var sharePayload: SharePayload?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Picker("打赏方式", selection: $channel) {
                        ForEach(Channel.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    codeCard

                    Button {
                        shareCurrentImage()
                    } label: {
                        Label("分享 / 存到相册", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)

                    Text("两个码都是个人收款码，扫任意一个都行，金额随意。谢谢你愿意支持这个小工具 🙏")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("请我喝杯咖啡")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: [payload.url])
        }
    }

    private var codeCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: channel == .alipay ? "a.circle.fill" : "message.fill")
                    .foregroundStyle(channel.accent)
                Text("\(channel.rawValue)收款码")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
            }

            Image(channel.imageName)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.hairline)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                .id(channel)
                .transition(.opacity)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
        .animation(.smooth(duration: 0.25), value: channel)
    }

    private func shareCurrentImage() {
        guard let image = UIImage(named: channel.imageName),
              let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xiaoman-reward-\(channel.imageName).png")
        do {
            try data.write(to: url, options: .atomic)
            sharePayload = SharePayload(url: url)
        } catch {
            // 写临时文件失败就不弹分享，页面上仍可直接扫
        }
    }
}
