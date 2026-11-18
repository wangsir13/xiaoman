import Foundation

enum CSVExporter {

    static func makeCSV(from items: [Transaction]) -> String {
        var lines: [String] = [
            "日期,时间,方向,金额,商户,分类,来源,备注,原始识别文本"
        ]

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm:ss"

        for item in items {
            let columns: [String] = [
                dayFormatter.string(from: item.occurredAt),
                timeFormatter.string(from: item.occurredAt),
                item.direction.title,
                Money.plain(item.amountCents),
                item.merchant,
                item.category,
                item.source.title,
                item.note,
                item.rawText.replacingOccurrences(of: "\n", with: " ")
            ]
            lines.append(columns.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    /// 写一个带 UTF-8 BOM 的临时文件，Excel / Numbers 打开都不会乱码
    static func writeTemporaryFile(from items: [Transaction], prefix: String = "xiaoman") -> URL? {
        let csv = "\u{FEFF}" + makeCSV(from: items)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(prefix)-\(formatter.string(from: Date())).csv"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ value: String) -> String {
        let needsQuote = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuote else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
