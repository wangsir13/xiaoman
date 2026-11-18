import Foundation

/// 读 xlsx（Excel 2007+ / 微信支付宝账单导出）里的第一张工作表，转成「行 × 列」的字符串矩阵。
///
/// 不依赖任何第三方库：xlsx 是 zip，先解出 sharedStrings.xml 与 worksheets/sheet1.xml，
/// 再用 XMLParser 走一遍。日期、金额都保持原始文本，交给 CSVImporter 现有规则去解析。
enum XLSXReader {

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func rows(from data: Data) throws -> [[String]] {
        let shared = try sharedStrings(in: data)
        let sheetData = try firstSheet(in: data)
        return try parseSheet(sheetData, shared: shared)
    }

    // MARK: - 定位并读取内部文件

    private static func firstSheet(in data: Data) throws -> Data {
        let all = try ZipArchive.entries(in: data)
        let candidates = all
            .map(\.name)
            .filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") && !$0.contains("_rels") }
            .sorted()

        guard let name = candidates.first(where: { $0 == "xl/worksheets/sheet1.xml" }) ?? candidates.first else {
            throw Failure(message: "这个 xlsx 里没有工作表")
        }
        guard let sheet = try ZipArchive.file(named: name, in: data) else {
            throw Failure(message: "读不出工作表内容")
        }
        return sheet
    }

    private static func sharedStrings(in data: Data) throws -> [String] {
        guard let xml = try ZipArchive.file(named: "xl/sharedStrings.xml", in: data) else {
            return []
        }
        let delegate = SharedStringsDelegate()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse() else {
            throw Failure(message: "共享字符串表解析失败")
        }
        return delegate.items
    }

    private static func parseSheet(_ xml: Data, shared: [String]) throws -> [[String]] {
        let delegate = SheetDelegate(shared: shared)
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse() else {
            throw Failure(message: "工作表解析失败")
        }
        return delegate.rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    // MARK: - sharedStrings

    private final class SharedStringsDelegate: NSObject, XMLParserDelegate {
        var items: [String] = []
        private var current = ""
        private var insideText = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if elementName == "si" {
                current = ""
            } else if elementName == "t" {
                insideText = true
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if insideText {
                current += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            if elementName == "t" {
                insideText = false
            } else if elementName == "si" {
                items.append(current)
            }
        }
    }

    // MARK: - 工作表

    private final class SheetDelegate: NSObject, XMLParserDelegate {
        private let shared: [String]
        var rows: [[String]] = []

        private var currentRow: [String] = []
        private var currentColumn = 0
        private var widestColumn = 0
        private var cellType = ""
        private var cellValue = ""
        private var insideValue = false

        init(shared: [String]) {
            self.shared = shared
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName {
            case "row":
                currentRow = []
                currentColumn = 0
            case "c":
                cellType = attributeDict["t"] ?? ""
                cellValue = ""
                if let reference = attributeDict["r"] {
                    currentColumn = Self.columnIndex(of: reference)
                }
            case "v":
                insideValue = true
            case "is":
                insideValue = true
            case "t":
                if cellType == "inlineStr" {
                    insideValue = true
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if insideValue {
                cellValue += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch elementName {
            case "v", "is", "t":
                insideValue = false
            case "c":
                let text = resolve(cellValue)
                while currentRow.count < currentColumn {
                    currentRow.append("")
                }
                if currentRow.count == currentColumn {
                    currentRow.append(text)
                } else {
                    currentRow[currentColumn] = text
                }
                widestColumn = max(widestColumn, currentColumn + 1)
            case "row":
                while currentRow.count < widestColumn {
                    currentRow.append("")
                }
                rows.append(currentRow)
                currentRow = []
            default:
                break
            }
        }

        private func resolve(_ raw: String) -> String {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            switch cellType {
            case "s":
                if let index = Int(text), index >= 0, index < shared.count {
                    return shared[index]
                }
                return ""
            case "b":
                return text == "1" ? "TRUE" : "FALSE"
            case "inlineStr", "str":
                return text
            default:
                return text
            }
        }

        /// A1 → 0，AB12 → 27
        static func columnIndex(of reference: String) -> Int {
            var value = 0
            for character in reference.uppercased() {
                guard let ascii = character.asciiValue, ascii >= 65, ascii <= 90 else { break }
                value = value * 26 + Int(ascii - 64)
            }
            return max(0, value - 1)
        }
    }
}
