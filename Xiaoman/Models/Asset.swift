import Foundation

/// 资产类型。信用卡和借款是负债，其余是资产。
enum AssetKind: String, Codable, CaseIterable, Identifiable {
    case bankCard
    case creditCard
    case wallet
    case loan
    case cash
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bankCard: return "银行卡"
        case .creditCard: return "信用卡"
        case .wallet: return "电子钱包"
        case .loan: return "借款欠款"
        case .cash: return "现金"
        case .other: return "其他"
        }
    }

    var symbol: String {
        switch self {
        case .bankCard: return "creditcard"
        case .creditCard: return "creditcard.fill"
        case .wallet: return "wallet.bifold"
        case .loan: return "arrow.down.left.circle"
        case .cash: return "banknote"
        case .other: return "square.stack.3d.up"
        }
    }

    /// 负债类资产：余额为负代表欠款，显示时要反过来读
    var isLiability: Bool {
        self == .creditCard || self == .loan
    }
}

/// 一个钱包 / 账户。余额 = 期初余额 + 所有绑定到它的收支（在 LedgerStore 里算，不落库，避免漂移）
struct Asset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var kind: AssetKind = .bankCard
    /// 期初余额（分）。信用卡 / 借款填「已欠金额」，用负数，例如 -150000 表示欠 1500 元
    var openingBalanceCents: Int = 0
    var note: String = ""
    /// OCR 文本里出现这些词就把账绑到这个资产上，例如 ["招商", "尾号1234"]
    var keywords: [String] = []
    var colorHex: String = Asset.palette[0]
    var isArchived: Bool = false
    var createdAt: Date = Date()
    /// 期初余额从什么时候开始生效：这个时间之前的账单不再扣减余额。
    /// nil 表示「从最早开始」（老数据）。改期初余额时会写成当前时间。
    var openingAt: Date?

    static let palette: [String] = [
        "2F4EDE", "7C3AD6", "0EA5A5", "E4572E", "E0A800",
        "3B82F6", "DB2777", "10B981", "6366F1", "F59E0B"
    ]

    var symbol: String { kind.symbol }

    /// 期初余额的展示文本
    var openingText: String { Money.plain(openingBalanceCents) }
}
