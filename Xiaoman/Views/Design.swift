import SwiftUI
import UIKit

// MARK: - 颜色

extension Color {
    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

enum Theme {
    static let income = Color(hex: "34C759")
    static let expense = Color(hex: "FF3B30")
    static let warn = Color(hex: "FF9F0A")
    static let accent = Color(hex: "2F4EDE")

    // 下面几个是「深色用白、浅色用黑」的自适应色，界面在两种外观下都能用
    static let cardFill = dynamic(dark: 0.05, light: 0.045)
    static let cardFillSoft = dynamic(dark: 0.035, light: 0.03)
    static let hairline = dynamic(dark: 0.12, light: 0.10)
    static let track = dynamic(dark: 0.12, light: 0.10)
    static let trackSoft = dynamic(dark: 0.07, light: 0.06)

    private static func dynamic(dark: CGFloat, light: CGFloat) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(dark)
                : UIColor.black.withAlphaComponent(light)
        })
    }
}

// MARK: - 外观

enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 背景：渐变 + 光斑（液态玻璃需要底下的颜色才好看）

struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(colors: baseColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color(hex: "2F4EDE").opacity(scheme == .dark ? 0.55 : 0.30))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: -120, y: -260)
            Circle()
                .fill(Color(hex: "7C3AD6").opacity(scheme == .dark ? 0.45 : 0.24))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 130, y: -120)
            Circle()
                .fill(Color(hex: "0EA5A5").opacity(scheme == .dark ? 0.28 : 0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 110)
                .offset(x: 90, y: 320)
        }
        .ignoresSafeArea()
    }

    private var baseColors: [Color] {
        scheme == .dark
            ? [Color(hex: "0B1020"), Color(hex: "141B34"), Color(hex: "0A0D18")]
            : [Color(hex: "F7F9FF"), Color(hex: "EDF2FD"), Color(hex: "FAFBFE")]
    }
}

// MARK: - 玻璃卡片

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 26
    var tint: Color?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                tint.map { Glass.regular.tint($0.opacity(0.22)) } ?? Glass.regular,
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

/// 低调的玻璃小胶囊，用来放标签 / 数值
struct GlassPill: View {
    var text: String
    var systemImage: String?
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.clear, in: .capsule)
    }
}

// MARK: - 环形进度

struct RingGauge: View {
    var progress: Double
    var lineWidth: CGFloat = 12
    var colors: [Color] = [Color(hex: "4C7DFF"), Color(hex: "8B5CF6")]

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(colors: colors + [colors.first ?? .white], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.5), value: progress)
        }
    }
}

// MARK: - 标题

struct SectionTitle: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - 常用格式化

enum Fmt {
    static func money(_ cents: Int) -> String {
        Money.display(cents)
    }

    static func signed(_ cents: Int) -> String {
        (cents >= 0 ? "+" : "") + Money.display(cents)
    }

    /// 大号数字，把小数部分缩小显示
    static func amountParts(_ cents: Int) -> (integer: String, fraction: String) {
        let negative = cents < 0
        let value = abs(cents)
        let integer = "\(value / 100)"
        let fraction = String(format: "%02d", value % 100)
        return ((negative ? "-" : "") + integer, fraction)
    }

    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 EEEE"
        return formatter
    }()

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
