import Foundation

/// 恢复备份时的可读错误（直接显示在弹窗里，方便判断是文件问题还是字段问题）
enum BackupError: LocalizedError {
    case emptyFile
    case badEnvelope(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "这个文件是空的（0 字节）。可能是还没从 iCloud 下载完，等一会儿再选一次。"
        case .badEnvelope(let detail):
            return "这份备份解析不了：\(detail)"
        }
    }
}

/// 整份账本的备份文件结构（一个 JSON 装下所有东西）
///
/// 解码刻意宽松：老版本导出的备份可能少几个后来才加的字段（version / assets / plan /
/// customCategories），这里一律给默认值，保证「旧备份也能恢复」，只要求 transactions 存在。
struct BackupEnvelope: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var transactions: [Transaction]
    var assets: [Asset]
    var plan: BudgetPlan
    var customCategories: [CategoryItem]

    init(
        transactions: [Transaction],
        assets: [Asset],
        plan: BudgetPlan,
        customCategories: [CategoryItem],
        version: Int = 1,
        exportedAt: Date = Date()
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.transactions = transactions
        self.assets = assets
        self.plan = plan
        self.customCategories = customCategories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        exportedAt = (try? container.decodeIfPresent(Date.self, forKey: .exportedAt)) ?? Date()
        transactions = try container.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
        // 资产 / 预算 / 分类是后加的，老备份里就算格式有出入也允许缺省，不要因此整份恢复失败
        assets = (try? container.decodeIfPresent([Asset].self, forKey: .assets)) ?? []
        plan = (try? container.decodeIfPresent(BudgetPlan.self, forKey: .plan)) ?? BudgetPlan()
        customCategories = (try? container.decodeIfPresent([CategoryItem].self, forKey: .customCategories)) ?? []

        if transactions.isEmpty && assets.isEmpty && customCategories.isEmpty && !plan.isConfigured {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "文件中不含任何账目或资产，不是有效的备份文件"
            ))
        }
    }

    static func stamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: date)
    }
}
