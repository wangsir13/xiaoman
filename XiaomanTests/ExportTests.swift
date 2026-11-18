import XCTest
@testable import Xiaoman

/// CSV 导出：表头、转义、换行
final class CSVExporterTests: XCTestCase {

    private func makeItem(
        amountCents: Int = 1234,
        merchant: String = "麦当劳",
        note: String = "",
        rawText: String = ""
    ) -> Transaction {
        Transaction(
            amountCents: amountCents,
            direction: .expense,
            merchant: merchant,
            category: "餐饮",
            source: .wechat,
            note: note,
            rawText: rawText
        )
    }

    func testHeaderAndLineEnding() {
        let csv = CSVExporter.makeCSV(from: [makeItem()])
        XCTAssertTrue(csv.hasPrefix("日期,时间,方向,金额,商户,分类,来源,备注,原始识别文本"))
        XCTAssertTrue(csv.contains("\r\n"))
        XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 2)
    }

    func testAmountAndDirectionColumns() {
        let csv = CSVExporter.makeCSV(from: [makeItem(amountCents: 2850)])
        let row = csv.components(separatedBy: "\r\n")[1]
        let columns = row.components(separatedBy: ",")
        XCTAssertEqual(columns.count, 9)
        XCTAssertEqual(columns[2], "支出")
        XCTAssertEqual(columns[3], "28.50")
        XCTAssertEqual(columns[4], "麦当劳")
        XCTAssertEqual(columns[6], "微信")
    }

    func testCommaAndQuoteAreEscaped() {
        let item = makeItem(merchant: "麦当劳, 国贸", note: "a\"b")
        let csv = CSVExporter.makeCSV(from: [item])
        XCTAssertTrue(csv.contains("\"麦当劳, 国贸\""))
        XCTAssertTrue(csv.contains("\"a\"\"b\""))
    }

    func testRawTextNewlinesCollapsed() {
        let item = makeItem(rawText: "第一行\n第二行")
        let csv = CSVExporter.makeCSV(from: [item])
        XCTAssertTrue(csv.contains("第一行 第二行"))
        // 一条记录只占一行
        XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 2)
    }

    func testEmptyListStillHasHeader() {
        let csv = CSVExporter.makeCSV(from: [])
        XCTAssertEqual(csv, "日期,时间,方向,金额,商户,分类,来源,备注,原始识别文本")
    }

    func testTemporaryFileHasBOM() {
        guard let url = CSVExporter.writeTemporaryFile(from: [makeItem()]) else {
            XCTFail("没有写出临时文件")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let data = try? Data(contentsOf: url), data.count > 3 else {
            XCTFail("临时文件为空")
            return
        }
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF], "缺少 UTF-8 BOM")

        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("日期,时间"))
    }
}

/// 去重指纹
final class FingerprintTests: XCTestCase {

    private func date(hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 18
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components) ?? Date()
    }

    func testSameMinuteSameFingerprint() {
        let first = Transaction.makeFingerprint(
            source: .wechat,
            amountCents: 2850,
            merchant: " 星巴克 咖啡 ",
            date: date(hour: 10, minute: 22, second: 5)
        )
        let second = Transaction.makeFingerprint(
            source: .wechat,
            amountCents: 2850,
            merchant: "星巴克咖啡",
            date: date(hour: 10, minute: 22, second: 40)
        )
        XCTAssertEqual(first, second)
    }

    func testDifferentAmountDiffers() {
        let base = Transaction.makeFingerprint(
            source: .wechat, amountCents: 2850, merchant: "星巴克", date: date(hour: 10, minute: 22, second: 0)
        )
        let other = Transaction.makeFingerprint(
            source: .wechat, amountCents: 2851, merchant: "星巴克", date: date(hour: 10, minute: 22, second: 0)
        )
        XCTAssertNotEqual(base, other)
    }

    func testDifferentSourceDiffers() {
        let base = Transaction.makeFingerprint(
            source: .wechat, amountCents: 2850, merchant: "星巴克", date: date(hour: 10, minute: 22, second: 0)
        )
        let other = Transaction.makeFingerprint(
            source: .bank, amountCents: 2850, merchant: "星巴克", date: date(hour: 10, minute: 22, second: 0)
        )
        XCTAssertNotEqual(base, other)
    }
}

/// 草稿的展示字段
final class ImportDraftTests: XCTestCase {

    func testValidityRequiresPositiveAmount() {
        var draft = ImportDraft()
        XCTAssertFalse(draft.isValid)

        draft.amountText = "28.50"
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.amountCents, 2850)

        draft.amountText = "0.00"
        XCTAssertFalse(draft.isValid)

        draft.amountText = ""
        XCTAssertFalse(draft.isValid)
    }

    func testConfidenceBuckets() {
        var draft = ImportDraft()
        draft.confidence = 0.9
        XCTAssertEqual(draft.confidenceText, "高")
        draft.confidence = 0.7
        XCTAssertEqual(draft.confidenceText, "中")
        draft.confidence = 0.3
        XCTAssertEqual(draft.confidenceText, "低")
    }

    func testSummaryLineFallsBack() {
        var draft = ImportDraft()
        XCTAssertEqual(draft.summaryLine, "未识别金额 · 未识别商户")

        draft.amountText = "12.00"
        draft.merchant = "星巴克"
        XCTAssertEqual(draft.summaryLine, "¥12.00 · 星巴克")
    }
}
