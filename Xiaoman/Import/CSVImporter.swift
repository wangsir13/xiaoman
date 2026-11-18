import Foundation

/// 把微信 / 支付宝导出的账单 CSV 转成 Transaction
enum CSVImporter {

    struct Row {
        var date: Date
        var cents: Int
        var direction: Direction
        var merchant: String
        var note: String
        var source: BillSource
    }

    enum CSVError: LocalizedError {
        case unsupportedEncoding
        case noHeader
        case empty

        var errorDescription: String? {
            switch self {
            case .unsupportedEncoding:
                return "这个文件既不是 UTF-8 也不是 GBK，读不出来。用微信/支付宝原始导出的 CSV 试试。"
            case .noHeader:
                return "没找到表头。要用微信「账单 → 常见问题 → 下载账单」或支付宝「账单 → 开具交易流水」导出的 CSV。"
            case .empty:
                return "文件里没有能识别的账单行。"
            }
        }
    }

    // MARK: - 解码

    static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8), !text.contains("\u{FFFD}") {
            return text
        }
        // 支付宝导出的 CSV 常见是 GB18030
        let gbEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = String(data: data, encoding: gbEncoding) {
            return text
        }
        return nil
    }

    // MARK: - 解析

    static func parse(_ text: String) throws -> [Row] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw CSVError.empty }

        guard let headerIndex = lines.firstIndex(where: isHeader), headerIndex < lines.count else {
            throw CSVError.noHeader
        }

        let header = fields(of: lines[headerIndex])
        let isWechat = header.contains { $0.contains("微信") } || text.contains("微信支付")
        let isAlipay = header.contains { $0.contains("支付宝") } || text.contains("支付宝")

        let source: BillSource = isWechat ? .wechat : (isAlipay ? .alipay : .other)

        let dateColumn = index(in: header, keywords: ["交易时间", "交易创建时间", "付款时间", "日期", "时间"])
        let amountColumn = index(in: header, keywords: ["金额"])
        let directionColumn = index(in: header, keywords: ["收/支", "收支", "收付"])
        let merchantColumn = index(in: header, keywords: ["交易对方", "对方", "商户名称", "商户", "收款方"])
        let noteColumn = index(in: header, keywords: ["商品", "备注", "说明", "交易类型"])

        guard let dateColumn, let amountColumn else { throw CSVError.noHeader }

        var rows: [Row] = []
        for line in lines[(headerIndex + 1)...] {
            let cells = fields(of: line)
            guard cells.count > max(dateColumn, amountColumn) else { continue }

            let dateCell = cells[dateColumn].trimmingCharacters(in: .whitespaces)
            guard let date = parseDate(dateCell) else { continue }

            let amountCell = cells[amountColumn]
            guard let cents = Money.cents(from: amountCell), cents != 0 else { continue }

            var direction: Direction = .expense
            if let directionColumn, cells.count > directionColumn {
                let flag = cells[directionColumn]
                if flag.contains("收入") || flag.contains("入账") {
                    direction = .income
                } else if flag.contains("不计") {
                    continue
                } else if flag.contains("支出") {
                    direction = .expense
                }
            } else if amountCell.contains("+") {
                direction = .income
            }

            let merchant: String = {
                if let merchantColumn, cells.count > merchantColumn {
                    return clean(cells[merchantColumn])
                }
                return ""
            }()

            var note = ""
            if let noteColumn, cells.count > noteColumn {
                note = clean(cells[noteColumn])
            }

            rows.append(Row(
                date: date,
                cents: abs(cents),
                direction: direction,
                merchant: merchant.isEmpty ? "导入记录" : merchant,
                note: note,
                source: source
            ))
        }

        guard !rows.isEmpty else { throw CSVError.empty }
        return rows
    }

    /// 把行转成可以直接落库的交易（要读 store 的资产关键词，所以在主线程上跑）
    @MainActor
    static func transactions(from rows: [Row], store: LedgerStore) -> [Transaction] {
        rows.map { row in
            var item = Transaction(
                amountCents: row.cents,
                direction: row.direction,
                merchant: row.merchant,
                category: CategoryCatalog.suggest(merchant: row.merchant, source: row.source),
                source: row.source,
                occurredAt: row.date,
                note: row.note,
                rawText: "CSV 导入 · \(row.merchant)"
            )
            item.assetID = store.guessAsset(in: row.merchant + " " + row.note)
            return item
        }
    }

    // MARK: - 小工具

    private static func isHeader(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact.contains("金额") && (compact.contains("交易时间") || compact.contains("日期") || compact.contains("交易对方"))
    }

    private static func index(in header: [String], keywords: [String]) -> Int? {
        for keyword in keywords {
            if let index = header.firstIndex(where: { $0.contains(keyword) }) {
                return index
            }
        }
        return nil
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 处理引号包裹的字段（微信的备注里会有逗号）
    static func fields(of line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false
        var characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if insideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 1
                } else {
                    insideQuotes.toggle()
                }
            } else if character == "," && !insideQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        result.append(current)
        return result.map { $0.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespaces) }
    }

    static func parseDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd",
            "yyyy年M月d日 HH:mm",
            "yyyy年M月d日 HH:mm:ss",
            "yyyy年M月d日"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }
}
