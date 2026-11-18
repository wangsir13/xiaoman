import Foundation

/// 账单截图 OCR 文本的解析器。
///
/// 设计原则：
/// 1. 先按关键字判断来源（微信 / 支付宝 / 云闪付 / 美团 / 京东 / 银行）。
/// 2. 金额优先取「带标签的」和「带 ¥ 的」，实在没有才退化成「单独成行的两位小数」。
/// 3. 商户取「收款方 / 商户全称 / 付款给 / 向…消费」这类标签，取不到才扫第一行像名字的文本。
/// 4. 时间取不到就用当前时间，宁可错也不空着，用户确认时能改。
enum BillParser {

    /// 金额词法：支持 1,234.56 / 12.34 / 12
    private static let amountToken =
        #"([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)"#

    // MARK: - 入口

    static func parse(text: String, sourceHint: BillSource? = nil, now: Date = Date()) -> ImportDraft {
        let normalized = normalize(text)
        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")

        let source = sourceHint ?? detectSource(in: joined)
        let masked = maskNoise(joined)
        let cents = extractAmount(joined: joined, masked: masked)
        let direction = detectDirection(in: joined)
        let merchant = extractMerchant(lines: lines, joined: joined)
        let parsedDate = extractDate(in: joined, now: now)

        var confidence = 0.2
        if cents != nil { confidence += 0.45 }
        if source != .other { confidence += 0.15 }
        if !merchant.isEmpty { confidence += 0.15 }
        if parsedDate != nil { confidence += 0.05 }

        var draft = ImportDraft()
        draft.amountText = cents.map { Money.plain($0) } ?? ""
        draft.direction = direction
        draft.merchant = merchant
        draft.source = source
        draft.category = CategoryCatalog.suggest(merchant: merchant, source: source)
        draft.occurredAt = parsedDate ?? now
        draft.rawText = joined
        draft.confidence = min(confidence, 1.0)
        return draft
    }

    // MARK: - 归一化

    /// 全角转半角、￥ 统一成 ¥、全角空格换成半角
    static func normalize(_ text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF01...0xFF5E:
                if let converted = UnicodeScalar(scalar.value - 0xFEE0) {
                    output.append(Character(converted))
                }
            case 0xFFE5:
                output.append("¥")
            case 0x3000, 0x00A0:
                output.append(" ")
            default:
                output.append(Character(scalar))
            }
        }
        return output
    }

    // MARK: - 来源

    private static let sourceKeywords: [(BillSource, [String])] = [
        (.wechat, ["微信支付", "微信", "零钱", "转账给", "扫二维码付款", "二维码收款"]),
        (.alipay, ["支付宝", "账单详情", "余额宝", "花呗", "借呗", "余额收支"]),
        (.unionpay, ["云闪付", "银联", "银联商务"]),
        (.meituan, ["美团", "美团外卖", "大众点评"]),
        (.jd, ["京东", "白条", "京东支付", "京东商城"]),
        (.bank, ["工商银行", "招商银行", "建设银行", "中国银行", "农业银行",
                 "交通银行", "邮储银行", "中信银行", "浦发银行", "民生银行",
                 "光大银行", "兴业银行", "平安银行", "广发银行", "华夏银行",
                 "储蓄卡", "信用卡", "尾号"])
    ]

    private static func detectSource(in text: String) -> BillSource {
        for entry in sourceKeywords {
            if entry.1.contains(where: { text.contains($0) }) {
                return entry.0
            }
        }
        return .other
    }

    // MARK: - 金额

    private static var labeledAmountPatterns: [String] {
        [
            #"(?:实付款|实付|实收款|实际支付|付款金额|支付金额|交易金额|订单金额|消费金额|合计|总计|应付|金额)[^0-9¥]{0,10}¥?\s*"# + amountToken,
            #"¥\s*"# + amountToken,
            amountToken + #"\s*元"#
        ]
    }

    private static func extractAmount(joined: String, masked: String) -> Int? {
        for pattern in labeledAmountPatterns {
            for token in allMatches(pattern, in: joined) {
                if let cents = Money.cents(from: token), isPlausible(cents) {
                    return cents
                }
            }
        }

        // 支付成功页往往把金额单独一行、放大显示
        for line in masked.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: #"^[0-9]{1,7}(?:\.[0-9]{2})$"#, options: .regularExpression) != nil,
               let cents = Money.cents(from: trimmed),
               isPlausible(cents) {
                return cents
            }
        }

        // 最后一档：任意两位小数，取合理区间里靠前的
        for token in allMatches(#"([0-9]+\.[0-9]{2})"#, in: masked) {
            if let cents = Money.cents(from: token), isPlausible(cents) {
                return cents
            }
        }

        return nil
    }

    /// 排除 0 元和明显不合理的金额
    private static func isPlausible(_ cents: Int) -> Bool {
        cents > 0 && cents <= 100_000_000
    }

    /// 把日期、时间、订单号等干扰项替换掉，避免被误当成金额
    private static func maskNoise(_ text: String) -> String {
        var result = text
        let noisePatterns: [String] = [
            #"[0-9]{4}[-/年][0-9]{1,2}[-/月][0-9]{1,2}日?"#,
            #"[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?"#,
            #"[0-9]{6,}"#,
            #"(?:订单号|交易单号|流水号|凭证号|商户单号)[:：]?\s*[A-Za-z0-9]+"#,
            #"\*{2,}[0-9]{2,4}"#
        ]
        for pattern in noisePatterns {
            result = replacingAll(pattern, in: result, with: " ")
        }
        return result
    }

    // MARK: - 方向

    private static func detectDirection(in text: String) -> Direction {
        let incomeKeywords = ["收款成功", "已到账", "入账", "退款成功", "已退款", "收到转账", "收款到账"]
        if incomeKeywords.contains(where: { text.contains($0) }) {
            return .income
        }
        if text.range(of: #"\+\s*¥?\s*[0-9]"#, options: .regularExpression) != nil {
            return .income
        }
        return .expense
    }

    // MARK: - 商户

    private static let merchantLabelPatterns: [String] = [
        #"(?:收款方|收款人|商户全称|商户名称|商家名称)[:：]?\s*([^\n]{2,30})"#,
        #"(?:付款给|转账给|支付给)[:：]?\s*([^\n]{2,26})"#,
        #"(?:来自|对方|付款方|转账方)[:：]?\s*([^\n]{2,20})"#,
        #"(?:向|在)\s*([一-龥A-Za-z0-9·-]{2,20})\s*(?:消费|支付|付款|刷卡|扣款)"#
    ]

    private static let stopWords: [String] = [
        "支付成功", "付款成功", "交易成功", "收款成功", "转账成功", "已到账",
        "账单详情", "微信支付", "支付宝", "云闪付", "京东支付", "美团外卖",
        "交易单号", "订单号", "商户单号", "流水号", "创建时间", "付款时间",
        "转账时间", "付款方式", "支付方式", "当前状态", "全部账单", "查看更多",
        "银行卡", "零钱", "余额", "积分", "优惠", "实付", "合计", "收款方",
        "商户全称", "商户名称", "商品说明", "储蓄卡", "信用卡", "尾号",
        "支付金额", "交易金额", "订单金额", "消费金额", "付款金额", "实付款",
        "人民币", "总计", "应付", "商品名称",
        "运行", "轻点背面", "展开", "详情"
    ]

    /// 只由标签词构成的行（「支付金额」「合计」等）不是商户
    private static let genericLabels: Set<String> = [
        "交易", "支付", "付款", "消费", "订单", "收款", "转账", "实付",
        "合计", "总计", "应付", "余额", "金额", "商品", "说明", "时间",
        "方式", "状态", "详情", "全部账单"
    ]

    private static func extractMerchant(lines: [String], joined: String) -> String {
        for pattern in merchantLabelPatterns {
            for raw in allMatches(pattern, in: joined) {
                let cleaned = cleanMerchant(raw)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        for line in lines {
            let cleaned = cleanMerchant(line)
            if !cleaned.isEmpty { return cleaned }
        }
        return ""
    }

    private static func cleanMerchant(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "：:，,。.·-—|/ 　「」“”\"'"))

        // 砍掉后面跟着的状态词，例如「星巴克 支付成功」
        for word in stopWords {
            if let found = text.range(of: word) {
                text = String(text[text.startIndex..<found.lowerBound])
            }
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "：:，,。.·-—|/ 　"))

        if text.count < 2 || text.count > 30 { return "" }
        if text.range(of: #"^[0-9¥\s.,:/-]+$"#, options: .regularExpression) != nil { return "" }
        if text.range(of: #"[0-9]{1,2}:[0-9]{2}"#, options: .regularExpression) != nil { return "" }
        // 带价签的行（如「支付金额 128.00」）不是商户
        if text.range(of: #"[0-9]+\.[0-9]{2}"#, options: .regularExpression) != nil { return "" }
        if genericLabels.contains(text) { return "" }
        if text.range(of: #"[一-龥A-Za-z]"#, options: .regularExpression) == nil { return "" }
        return String(text.prefix(24))
    }

    // MARK: - 时间

    private static func extractDate(in text: String, now: Date) -> Date? {
        let calendar = Calendar.current

        if let groups = firstGroups(#"([0-9]{4})[-/年]([0-9]{1,2})[-/月]([0-9]{1,2})日?\s*([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?"#, in: text) {
            return buildDate(year: int(groups[0]), month: int(groups[1]), day: int(groups[2]),
                             hour: int(groups[3]), minute: int(groups[4]), second: int(groups[5]) ?? 0,
                             calendar: calendar)
        }
        if let groups = firstGroups(#"([0-9]{4})[-/年]([0-9]{1,2})[-/月]([0-9]{1,2})"#, in: text) {
            return buildDate(year: int(groups[0]), month: int(groups[1]), day: int(groups[2]),
                             hour: 12, minute: 0, second: 0, calendar: calendar)
        }
        if let groups = firstGroups(#"([0-9]{1,2})月([0-9]{1,2})日\s*([0-9]{1,2}):([0-9]{2})"#, in: text) {
            return buildDate(year: calendar.component(.year, from: now), month: int(groups[0]), day: int(groups[1]),
                             hour: int(groups[2]), minute: int(groups[3]), second: 0, calendar: calendar)
        }
        if let groups = firstGroups(#"(今天|昨天|前天)\s*([0-9]{1,2}):([0-9]{2})"#, in: text) {
            let offset: Int
            switch groups[0] ?? "" {
            case "昨天": offset = -1
            case "前天": offset = -2
            default: offset = 0
            }
            let base = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let parts = calendar.dateComponents([.year, .month, .day], from: base)
            return buildDate(year: parts.year, month: parts.month, day: parts.day,
                             hour: int(groups[1]), minute: int(groups[2]), second: 0, calendar: calendar)
        }
        if let groups = firstGroups(#"(?:^|\s)([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?(?:\s|$)"#, in: text) {
            let parts = calendar.dateComponents([.year, .month, .day], from: now)
            return buildDate(year: parts.year, month: parts.month, day: parts.day,
                             hour: int(groups[0]), minute: int(groups[1]), second: int(groups[2]) ?? 0,
                             calendar: calendar)
        }
        return nil
    }

    private static func buildDate(
        year: Int?,
        month: Int?,
        day: Int?,
        hour: Int?,
        minute: Int?,
        second: Int,
        calendar: Calendar
    ) -> Date? {
        guard let year = year, let month = month, let day = day,
              let hour = hour, let minute = minute else { return nil }
        guard (1970...2100).contains(year),
              (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)
    }

    // MARK: - 正则小工具

    private static func int(_ value: String?) -> Int? {
        guard let value = value else { return nil }
        return Int(value)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// 返回所有匹配的第 1 个分组
    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let expression = regex(pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return expression.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let groupRange = match.range(at: 1)
            guard groupRange.location != NSNotFound else { return nil }
            return nsText.substring(with: groupRange)
        }
    }

    private static func firstGroups(_ pattern: String, in text: String) -> [String?]? {
        guard let expression = regex(pattern) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = expression.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).map { index in
            let groupRange = match.range(at: index)
            guard groupRange.location != NSNotFound else { return nil }
            return nsText.substring(with: groupRange)
        }
    }

    private static func replacingAll(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let expression = regex(pattern) else { return text }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}
