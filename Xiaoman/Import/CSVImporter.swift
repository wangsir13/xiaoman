import Foundation

/// 把微信 / 支付宝 / 银行导出的账单（CSV、xlsx、zip）转成 Transaction
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
        case unsupportedFile

        var errorDescription: String? {
            switch self {
            case .unsupportedEncoding:
                return "文件编码无法识别。请使用微信或支付宝原始导出的 CSV 或 xlsx 文件。"
            case .noHeader:
                return "没找到表头。要用微信「账单 → 常见问题 → 下载账单」或支付宝「账单 → 开具交易流水」导出的文件。"
            case .empty:
                return "文件里没有能识别的账单行。"
            case .unsupportedFile:
                return "这个格式暂时不支持。可以选 CSV、xlsx，或者微信导出的 zip。"
            }
        }
    }

    // MARK: - 入口

    /// 按扩展名分派：csv / txt / xlsx / zip
    static func parse(data: Data, fileName: String) throws -> [Row] {
        let ext = (fileName as NSString).pathExtension.lowercased()

        switch ext {
        case "xlsx":
            let matrix = try XLSXReader.rows(from: data)
            return try parseMatrix(matrix, sourceHint: fileName)

        case "zip":
            let entries = try ZipArchive.entries(in: data)
            if let csv = entries.first(where: { $0.name.lowercased().hasSuffix(".csv") }) {
                let inner = try ZipArchive.extract(csv, from: data)
                guard let text = decode(inner) else { throw CSVError.unsupportedEncoding }
                return try parse(text)
            }
            if let xlsx = entries.first(where: { $0.name.lowercased().hasSuffix(".xlsx") }) {
                let inner = try ZipArchive.extract(xlsx, from: data)
                let matrix = try XLSXReader.rows(from: inner)
                return try parseMatrix(matrix, sourceHint: fileName)
            }
            throw CSVError.unsupportedFile

        case "xls", "numbers", "pdf":
            throw CSVError.unsupportedFile

        default:
            guard let text = decode(data) else { throw CSVError.unsupportedEncoding }
            return try parse(text)
        }
    }

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

        let matrix = lines.map { fields(of: $0) }
        return try parseMatrix(matrix, sourceHint: text)
    }

    /// 行 × 列 的通用入口：CSV 和 xlsx 都走这里
    static func parseMatrix(_ matrix: [[String]], sourceHint: String) throws -> [Row] {
        guard !matrix.isEmpty else { throw CSVError.empty }

        guard let headerIndex = matrix.firstIndex(where: isHeaderRow) else {
            throw CSVError.noHeader
        }

        let header = matrix[headerIndex]

        let flat = matrix.prefix(headerIndex + 8).map { $0.joined(separator: " ") }.joined(separator: " ")
        let hint = flat + " " + sourceHint
        let isWechat = hint.contains("微信")
        let isAlipay = hint.contains("支付宝")
        let isMeituan = hint.contains("美团")
        let source: BillSource = isWechat ? .wechat : (isAlipay ? .alipay : (isMeituan ? .meituan : .other))

        let dateColumn = index(in: header, keywords: ["交易时间", "交易创建时间", "付款时间", "记账时间", "日期", "时间"])
        // 「实付金额」要排在「金额」前面，否则会先命中「订单金额」
        let amountColumn = index(in: header, keywords: ["实付金额", "订单金额", "金额(元)", "交易金额", "金额"])
        let directionColumn = index(in: header, keywords: ["收/支", "收支", "收付", "资金方向", "收支类型"])
        let merchantColumn = index(in: header, keywords: ["交易对方", "订单标题", "对方", "商户名称", "商户", "收款方", "交易对象"])
        let noteColumn = index(in: header, keywords: ["商品", "备注", "说明", "交易类型", "商品说明"])

        guard let dateColumn, let amountColumn else { throw CSVError.noHeader }

        var rows: [Row] = []
        for cells in matrix[(headerIndex + 1)...] {
            guard cells.count > max(dateColumn, amountColumn) else { continue }

            let dateCell = cells[dateColumn].trimmingCharacters(in: .whitespaces)
            guard let date = parseDate(dateCell) else { continue }

            let amountCell = cells[amountColumn]
            guard let cents = Money.cents(from: amountCell), cents != 0 else { continue }

            var direction: Direction = .expense
            if let directionColumn, cells.count > directionColumn {
                let flag = cells[directionColumn]
                if flag.contains("收入") || flag.contains("入账") || flag.contains("收入/") {
                    direction = .income
                } else if flag.contains("不计") {
                    continue
                } else if flag.contains("支出") {
                    direction = .expense
                }
            } else if amountCell.contains("+") {
                direction = .income
            } else if amountCell.contains("-") {
                direction = .expense
            }

            var merchant = ""
            if let merchantColumn, cells.count > merchantColumn {
                merchant = clean(cells[merchantColumn])
            }

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
                rawText: "账单导入 · \(row.merchant)"
            )
            item.assetID = store.guessAsset(in: row.merchant + " " + row.note)
            return item
        }
    }

    // MARK: - 小工具

    private static func isHeaderRow(_ cells: [String]) -> Bool {
        let compact = cells.joined().replacingOccurrences(of: " ", with: "")
        let hasAmount = compact.contains("金额")
        // 美团那种表头写的是「交易创建时间」，还会带「收/支」列，不能只认「交易时间」
        let hasDate = compact.contains("时间")
            || compact.contains("日期")
            || compact.contains("交易对方")
            || compact.contains("收/支")
        return hasAmount && hasDate && cells.count >= 3
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
        var text = value
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "订单详情", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 美团有些标题尾巴带「-4502391563334320787」这种内部编号
        if let range = text.range(of: #"-[0-9]{8,}$"#, options: .regularExpression) {
            text = String(text[text.startIndex..<range.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            "yyyy年M月d日",
            "M/d/yy H:mm",
            "M/d/yy"
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

        // xlsx 里日期可能被存成 Excel 序列号（1900 起算的天数，小数部分是时间）
        if let serial = Double(text), serial > 25_000, serial < 80_000 {
            let seconds = (serial - 25_569) * 86_400
            return Date(timeIntervalSince1970: seconds)
        }

        return nil
    }
}
