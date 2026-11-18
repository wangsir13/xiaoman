import Foundation

/// 一条「待确认」的识别结果。用户在确认页里可以直接改，改完再落库。
struct ImportDraft: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var amountText: String = ""
    var direction: Direction = .expense
    var merchant: String = ""
    var category: String = CategoryCatalog.defaultName
    var source: BillSource = .other
    var occurredAt: Date = Date()
    var note: String = ""
    var rawText: String = ""
    var confidence: Double = 0
    var isDuplicate: Bool = false
    var imageFileName: String?
    /// 识别文本里猜出来的资产，识别不到就是 nil，用户在确认页手选
    var assetID: UUID?
    var assetName: String = ""

    var amountCents: Int? {
        Money.cents(from: amountText)
    }

    var isValid: Bool {
        guard let cents = amountCents else { return false }
        return cents > 0
    }

    var confidenceText: String {
        if confidence >= 0.85 { return "高" }
        if confidence >= 0.6 { return "中" }
        return "低"
    }

    var summaryLine: String {
        let amount = amountCents.map { Money.display($0) } ?? "未识别金额"
        let name = merchant.isEmpty ? "未识别商户" : merchant
        return "\(amount) · \(name)"
    }
}
