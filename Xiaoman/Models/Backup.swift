import Foundation

/// 整份账本的备份文件结构（一个 JSON 装下所有东西）
struct BackupEnvelope: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var transactions: [Transaction]
    var assets: [Asset]
    var plan: BudgetPlan
    var customCategories: [CategoryItem]

    static func stamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: date)
    }
}
