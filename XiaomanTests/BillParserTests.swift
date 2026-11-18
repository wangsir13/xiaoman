import XCTest
@testable import Xiaoman

/// 金额换算（分）与展示格式
final class MoneyTests: XCTestCase {

    func testPlainAlwaysTwoDecimals() {
        XCTAssertEqual(Money.plain(2850), "28.50")
        XCTAssertEqual(Money.plain(5), "0.05")
        XCTAssertEqual(Money.plain(0), "0.00")
        XCTAssertEqual(Money.plain(100000), "1000.00")
        XCTAssertEqual(Money.plain(-100), "-1.00")
    }

    func testDisplayHasYenSign() {
        XCTAssertEqual(Money.display(2850), "¥28.50")
        XCTAssertEqual(Money.display(-1), "-¥0.01")
    }

    func testCentsParsing() {
        XCTAssertEqual(Money.cents(from: "28.50"), 2850)
        XCTAssertEqual(Money.cents(from: "¥28.50"), 2850)
        XCTAssertEqual(Money.cents(from: "66.00元"), 6600)
        XCTAssertEqual(Money.cents(from: "¥1,234.56"), 123456)
        // 没有小数点时，逗号按小数点处理（欧洲写法）
        XCTAssertEqual(Money.cents(from: "12,34"), 1234)
        XCTAssertEqual(Money.cents(from: "100"), 10000)
        // 负数：欠款、信用卡欠额、支付宝账单里带减号的金额
        XCTAssertEqual(Money.cents(from: "-1500"), -150000)
        XCTAssertEqual(Money.cents(from: "−12.50"), -1250)
        XCTAssertEqual(Money.cents(from: "-¥1,234.56"), -123456)
        XCTAssertEqual(Money.cents(from: "1500"), 150000)
        XCTAssertNil(Money.cents(from: ""))
        XCTAssertNil(Money.cents(from: "abc"))
        XCTAssertNil(Money.cents(from: "."))
    }

    func testCentsRoundTrip() {
        for cents in [1, 9, 99, 100, 2850, 123456, 100000000] {
            XCTAssertEqual(Money.cents(from: Money.plain(cents)), cents, "\(cents) 往返失败")
        }
    }
}

/// 归一化
final class NormalizeTests: XCTestCase {

    func testFullWidthToHalfWidth() {
        XCTAssertEqual(BillParser.normalize("￥１２８．００"), "¥128.00")
        XCTAssertEqual(BillParser.normalize("ＡＢＣ１２３"), "ABC123")
        XCTAssertEqual(BillParser.normalize("金　额"), "金 额")
    }
}

/// 各类账单文本的解析结果
final class BillParserTests: XCTestCase {

    private static var referenceDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 18
        components.hour = 10
        components.minute = 22
        components.second = 31
        return Calendar.current.date(from: components) ?? Date()
    }

    private func makeDraft(_ text: String, hint: BillSource? = nil) -> ImportDraft {
        BillParser.parse(text: text, sourceHint: hint, now: Self.referenceDate)
    }

    private func dateParts(_ date: Date) -> (year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return (
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    // MARK: - 微信

    func testWechatPayment() {
        let draft = makeDraft(SampleData.wechat)
        XCTAssertEqual(draft.amountCents, 2850)
        XCTAssertEqual(draft.direction, .expense)
        XCTAssertEqual(draft.merchant, "星巴克咖啡(国贸店)")
        XCTAssertEqual(draft.category, "餐饮")
        XCTAssertEqual(draft.source, .wechat)
        XCTAssertEqual(draft.confidence, 1.0, accuracy: 0.001)
        XCTAssertTrue(draft.isValid)

        let parts = dateParts(draft.occurredAt)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 11)
        XCTAssertEqual(parts.day, 18)
        XCTAssertEqual(parts.hour, 10)
        XCTAssertEqual(parts.minute, 22)
        XCTAssertEqual(parts.second, 31)
    }

    // MARK: - 支付宝（金额前面带负号，是最容易漏的一类）

    func testAlipayBill() {
        let draft = makeDraft(SampleData.alipay)
        XCTAssertEqual(draft.amountCents, 2850)
        XCTAssertEqual(draft.direction, .expense)
        XCTAssertEqual(draft.merchant, "星巴克咖啡(北京国贸店)")
        XCTAssertEqual(draft.category, "餐饮")
        XCTAssertEqual(draft.source, .alipay)
        XCTAssertEqual(draft.confidence, 1.0, accuracy: 0.001)
    }

    // MARK: - 银行短信

    func testBankSMS() {
        let draft = makeDraft(SampleData.bank)
        XCTAssertEqual(draft.amountCents, 2850)
        XCTAssertEqual(draft.direction, .expense)
        XCTAssertEqual(draft.merchant, "星巴克咖啡")
        XCTAssertEqual(draft.category, "餐饮")
        XCTAssertEqual(draft.source, .bank)

        // 「11月18日10:22」没有年份，取当前年
        let parts = dateParts(draft.occurredAt)
        XCTAssertEqual(parts.month, 11)
        XCTAssertEqual(parts.day, 18)
        XCTAssertEqual(parts.hour, 10)
        XCTAssertEqual(parts.minute, 22)
    }

    // MARK: - 云闪付

    func testUnionPay() {
        let text = """
        云闪付
        付款成功
        ¥66.00
        收款方：全家便利店
        2026-11-18 12:01:09
        """
        let draft = makeDraft(text, hint: .unionpay)
        XCTAssertEqual(draft.amountCents, 6600)
        XCTAssertEqual(draft.merchant, "全家便利店")
        XCTAssertEqual(draft.category, "餐饮")
        XCTAssertEqual(draft.source, .unionpay)
    }

    // MARK: - 收款（收入方向）

    func testWechatIncome() {
        let text = """
        微信支付
        收款成功
        ¥100.00
        来自 张三
        2026-11-18 09:00:00
        """
        let draft = makeDraft(text)
        XCTAssertEqual(draft.amountCents, 10000)
        XCTAssertEqual(draft.direction, .income)
        XCTAssertEqual(draft.merchant, "张三")
        XCTAssertEqual(draft.source, .wechat)
    }

    func testPlusSignMeansIncome() {
        let draft = makeDraft("支付宝\n+¥12.00\n余额宝收益\n2026-11-18 06:00")
        XCTAssertEqual(draft.direction, .income)
        XCTAssertEqual(draft.amountCents, 1200)
    }

    // MARK: - 美团 / 京东

    func testMeituanOrder() {
        let text = """
        美团
        订单金额 ¥45.80
        商家名称：肯德基(望京店)
        2026年11月17日 19:30
        """
        let draft = makeDraft(text)
        XCTAssertEqual(draft.amountCents, 4580)
        XCTAssertEqual(draft.merchant, "肯德基(望京店)")
        XCTAssertEqual(draft.category, "餐饮")
        XCTAssertEqual(draft.source, .meituan)

        let parts = dateParts(draft.occurredAt)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 11)
        XCTAssertEqual(parts.day, 17)
        XCTAssertEqual(parts.hour, 19)
        XCTAssertEqual(parts.minute, 30)
    }

    func testJingdongOrder() {
        let text = """
        京东
        白条支付
        实付款 ¥199.00
        收款方 京东商城
        2026-11-16 08:15
        """
        let draft = makeDraft(text)
        XCTAssertEqual(draft.amountCents, 19900)
        XCTAssertEqual(draft.merchant, "京东商城")
        XCTAssertEqual(draft.category, "购物")
        XCTAssertEqual(draft.source, .jd)
    }

    // MARK: - 没有货币符号，只能靠「标签」或「独立成行」

    func testLabeledAmountWithoutSymbol() {
        let text = """
        支付金额 128.00
        地铁出行
        2026-11-15 07:40
        """
        let draft = makeDraft(text)
        XCTAssertEqual(draft.amountCents, 12800)
        XCTAssertEqual(draft.merchant, "地铁出行")
        XCTAssertEqual(draft.category, "交通")
        XCTAssertEqual(draft.source, .other)
        // 来源未知，把握度低一档
        XCTAssertEqual(draft.confidence, 0.85, accuracy: 0.001)
    }

    func testThousandsSeparator() {
        let text = """
        招商银行
        消费金额：人民币 1,280.50 元
        商户名称 优衣库
        2026-11-14 20:11
        """
        let draft = makeDraft(text)
        XCTAssertEqual(draft.amountCents, 128050)
        XCTAssertEqual(draft.merchant, "优衣库")
        XCTAssertEqual(draft.category, "购物")
        XCTAssertEqual(draft.source, .bank)
    }

    // MARK: - 全角 / 今天

    func testFullWidthAndRelativeDay() {
        let text = """
        微信支付
        ￥１２８．００
        收款方 瑞幸咖啡
        今天 08:30
        """
        let draft = makeDraft(text)
        XCTAssertEqual(draft.amountCents, 12800)
        XCTAssertEqual(draft.merchant, "瑞幸咖啡")
        XCTAssertEqual(draft.category, "餐饮")
        XCTAssertEqual(draft.source, .wechat)

        let parts = dateParts(draft.occurredAt)
        XCTAssertEqual(parts.hour, 8)
        XCTAssertEqual(parts.minute, 30)
    }

    // MARK: - 负例

    func testNoAmountMeansInvalid() {
        let draft = makeDraft("轻点背面\n已开启双击截屏\n无有效账单")
        XCTAssertNil(draft.amountCents)
        XCTAssertFalse(draft.isValid)
        XCTAssertEqual(draft.confidence, 0.35, accuracy: 0.001)
    }

    func testNoiseIsMasked() {
        let draft = makeDraft("2026-11-18 10:22:31\n订单号 2026111822001234567890\n尾号1234")
        XCTAssertNil(draft.amountCents)
        XCTAssertEqual(draft.source, .bank)
    }

    func testEmptyTextDoesNotCrash() {
        let draft = makeDraft("")
        XCTAssertNil(draft.amountCents)
        XCTAssertEqual(draft.merchant, "")
        XCTAssertEqual(draft.category, "其他")
    }

    // MARK: - 自动归类

    func testCategorySuggestions() {
        XCTAssertEqual(CategoryCatalog.suggest(merchant: "星巴克咖啡(国贸店)", source: .wechat), "餐饮")
        XCTAssertEqual(CategoryCatalog.suggest(merchant: "滴滴出行", source: .alipay), "交通")
        XCTAssertEqual(CategoryCatalog.suggest(merchant: "优衣库", source: .alipay), "购物")
        XCTAssertEqual(CategoryCatalog.suggest(merchant: "屈臣氏", source: .wechat), "其他")
        XCTAssertEqual(CategoryCatalog.suggest(merchant: "", source: .wechat), "其他")
    }
}
