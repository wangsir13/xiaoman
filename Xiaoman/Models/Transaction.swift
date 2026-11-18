import Foundation

// MARK: - 收支方向

enum Direction: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        }
    }

    var sign: String {
        switch self {
        case .expense: return "-"
        case .income: return "+"
        }
    }
}

// MARK: - 账单来源

enum BillSource: String, Codable, CaseIterable, Identifiable {
    case wechat
    case alipay
    case unionpay
    case meituan
    case jd
    case bank
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wechat: return "微信"
        case .alipay: return "支付宝"
        case .unionpay: return "云闪付"
        case .meituan: return "美团"
        case .jd: return "京东"
        case .bank: return "银行"
        case .other: return "其他"
        }
    }

    /// URL 参数里用的短名，例如 ?src=wechat
    static func named(_ raw: String?) -> BillSource? {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "wechat", "wx", "weixin": return .wechat
        case "alipay", "zfb": return .alipay
        case "unionpay", "up", "ysf", "银联": return .unionpay
        case "meituan", "mt": return .meituan
        case "jd", "jingdong": return .jd
        case "bank", "yh": return .bank
        case "other": return .other
        default: return nil
        }
    }
}

// MARK: - 金额工具（一律用「分」存储，避免浮点误差）

enum Money {

    /// 1234 -> "12.34"
    static func plain(_ cents: Int) -> String {
        let negative = cents < 0
        let value = abs(cents)
        let body = "\(value / 100)." + String(format: "%02d", value % 100)
        return negative ? "-" + body : body
    }

    /// 1234 -> "¥12.34"
    static func display(_ cents: Int) -> String {
        (cents < 0 ? "-¥" : "¥") + plain(abs(cents))
    }

    /// 把任意用户/OCR 文本转成分；"¥1,234.5" -> 123450
    static func cents(from raw: String) -> Int? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }

        text = text.replacingOccurrences(of: "¥", with: "")
        text = text.replacingOccurrences(of: "￥", with: "")
        text = text.replacingOccurrences(of: " ", with: "")
        text = text.replacingOccurrences(of: "元", with: "")

        // "1,234.56" 当作千分位；"12,34" 当作小数点
        if text.contains(".") {
            text = text.replacingOccurrences(of: ",", with: "")
        } else {
            text = text.replacingOccurrences(of: ",", with: ".")
        }

        // 负号要在过滤掉符号之前记住：欠款、信用卡欠额都是负数
        let isNegative = text.contains("-") || text.contains("−") || text.contains("－")
        let filtered = text.filter { "0123456789.".contains($0) }
        if filtered.isEmpty || filtered == "." { return nil }
        guard let decimal = Decimal(string: filtered) else { return nil }

        let scaled = NSDecimalNumber(decimal: decimal * 100)
        let rounded = scaled.rounding(accordingToBehavior: nil)
        let cents = rounded.intValue
        return isNegative ? -abs(cents) : cents
    }
}

// MARK: - 一条账

struct Transaction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var amountCents: Int
    var direction: Direction = .expense
    var merchant: String = ""
    var category: String = CategoryCatalog.defaultName
    var source: BillSource = .other
    var occurredAt: Date = Date()
    var note: String = ""
    var rawText: String = ""
    var createdAt: Date = Date()
    var fingerprint: String = ""
    /// 这笔钱从哪个资产出 / 进（nil 表示没绑定资产）
    var assetID: UUID?
    /// 固定支出（房租、话费、订阅…）：照常记账，但不占用当月每日预算。用可选类型兼容老数据。
    var isFixed: Bool?

    init(
        id: UUID = UUID(),
        amountCents: Int,
        direction: Direction = .expense,
        merchant: String = "",
        category: String = CategoryCatalog.defaultName,
        source: BillSource = .other,
        occurredAt: Date = Date(),
        note: String = "",
        rawText: String = "",
        createdAt: Date = Date(),
        fingerprint: String = "",
        assetID: UUID? = nil,
        isFixed: Bool? = nil
    ) {
        self.id = id
        self.amountCents = amountCents
        self.direction = direction
        self.merchant = merchant
        self.category = category
        self.source = source
        self.occurredAt = occurredAt
        self.note = note
        self.rawText = rawText
        self.createdAt = createdAt
        self.fingerprint = fingerprint
        self.assetID = assetID
        self.isFixed = isFixed
    }

    /// 老数据里没有这个字段，按「普通支出」处理
    var isFixedFlag: Bool { isFixed ?? false }

    /// 对资产余额的影响：支出为负、收入为正
    var signedCents: Int {
        direction == .expense ? -amountCents : amountCents
    }

    var amountText: String { Money.plain(amountCents) }
    var displayAmount: String { direction.sign + Money.plain(amountCents) }
    var title: String { merchant.isEmpty ? "未识别商户" : merchant }

    /// 去重指纹：来源 + 金额 + 商户 + 分钟级时间
    static func makeFingerprint(
        source: BillSource,
        amountCents: Int,
        merchant: String,
        date: Date
    ) -> String {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = [
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0
        ].map(String.init).joined(separator: "-")
        let name = merchant
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        return "\(source.rawValue)|\(amountCents)|\(name)|\(stamp)"
    }
}
