import Foundation
import UIKit

/// 可选的大模型解析：把 OCR 出来的整段文字交给一家大模型，让它直接给出结构化字段。
///
/// 支持 DeepSeek / OpenAI / Anthropic(Claude) / 豆包(火山方舟) 和任何 OpenAI 兼容接口。
/// 只在用户自己填了 API Key 并打开开关时才会联网；默认完全离线。
enum AIParser {

    // MARK: - 服务商

    enum Provider: String, CaseIterable, Identifiable, Sendable {
        case deepseek
        case openai
        case anthropic
        case doubao
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .deepseek: return "DeepSeek"
            case .openai: return "OpenAI（GPT）"
            case .anthropic: return "Anthropic（Claude）"
            case .doubao: return "豆包（火山方舟）"
            case .custom: return "自定义（OpenAI 兼容）"
            }
        }

        var defaultEndpoint: String {
            switch self {
            case .deepseek: return "https://api.deepseek.com/chat/completions"
            case .openai: return "https://api.openai.com/v1/chat/completions"
            case .anthropic: return "https://api.anthropic.com/v1/messages"
            case .doubao: return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
            case .custom: return ""
            }
        }

        var defaultModel: String {
            switch self {
            case .deepseek: return "deepseek-chat"
            case .openai: return "gpt-4o-mini"
            case .anthropic: return "claude-sonnet-4-5"
            case .doubao: return ""
            case .custom: return ""
            }
        }

        /// Claude 用 Anthropic 自己的 /v1/messages 协议，其余都是 OpenAI 兼容的 chat/completions
        var usesAnthropicAPI: Bool { self == .anthropic }

        var modelHint: String {
            switch self {
            case .deepseek: return "deepseek-chat / deepseek-reasoner"
            case .openai: return "gpt-4o-mini / gpt-4o"
            case .anthropic: return "claude-sonnet-4-5 / claude-3-5-sonnet-latest"
            case .doubao: return "方舟的接入点 ID，形如 ep-2024xxxx"
            case .custom: return "服务商要求的模型名"
            }
        }

        var keyHint: String {
            switch self {
            case .deepseek: return "API Key（sk-…）"
            case .openai: return "API Key（sk-…）"
            case .anthropic: return "API Key（sk-ant-…）"
            case .doubao: return "方舟 API Key"
            case .custom: return "API Key（没有就留空）"
            }
        }

        var keyURL: String {
            switch self {
            case .deepseek: return "platform.deepseek.com"
            case .openai: return "platform.openai.com"
            case .anthropic: return "console.anthropic.com"
            case .doubao: return "console.volcengine.com/ark"
            case .custom: return ""
            }
        }

        /// 豆包/自定义必须自己填模型，没有默认值
        var requiresModel: Bool { defaultModel.isEmpty }

        /// 是否尝试把截图直接交给它读（多模态）。
        /// 现在各家都陆续支持视觉，所以一律先试读图；接口明确拒绝图片时会自动退回 OCR。
        var supportsVision: Bool { true }

        var visionHint: String {
            switch self {
            case .deepseek: return "deepseek-chat / deepseek-vl 系列可直接读图；若你的 Key 只能调文本模型，接口会拒绝图片并自动改用 OCR"
            case .openai: return "gpt-4o-mini / gpt-4o 都能直接读图"
            case .anthropic: return "claude-sonnet-4-5 / claude-3-5-sonnet 都支持读图"
            case .doubao: return "需要填方舟里的视觉接入点（如 doubao-vision 系列的 ep-xxxx）"
            case .custom: return "接口需要兼容 OpenAI 的 image_url 格式，模型本身也要支持读图"
            }
        }
    }

    // MARK: - 配置

    struct Config: Sendable {
        var enabled: Bool
        var provider: Provider
        var apiKey: String
        var endpoint: String
        var model: String

        static func load(from defaults: UserDefaults = .standard) -> Config {
            let provider = Provider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .deepseek
            let endpoint = (defaults.string(forKey: "aiEndpoint") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (defaults.string(forKey: "aiModel") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Config(
                enabled: defaults.object(forKey: "aiEnabled") as? Bool ?? false,
                provider: provider,
                apiKey: (defaults.string(forKey: "aiKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                endpoint: endpoint.isEmpty ? provider.defaultEndpoint : endpoint,
                model: model.isEmpty ? provider.defaultModel : model
            )
        }

        var isUsable: Bool { enabled && !apiKey.isEmpty && !model.isEmpty && !endpoint.isEmpty }
    }

    // MARK: - 结果

    struct Result: Sendable {
        var amountCents: Int?
        var merchant: String
        var direction: Direction
        var category: String
        var occurredAt: Date?
        var assetName: String
        var note: String
        var confidence: Double
    }

    enum AIError: LocalizedError {
        case missingKey
        case missingModel
        case visionUnsupported
        case badStatus(Int, String)
        case badPayload(String)
        case emptyAnswer

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "还没填 API Key。"
            case .missingModel:
                return "还没填模型名。"
            case .visionUnsupported:
                return "这家服务商不支持直接读图，请在设置里换成 OpenAI / Claude / 豆包。"
            case .badStatus(let code, let body):
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                let short = trimmed.count > 160 ? String(trimmed.prefix(160)) + "…" : trimmed
                return "接口返回 \(code)：\(short)"
            case .badPayload(let detail):
                return "返回内容看不懂：\(detail)"
            case .emptyAnswer:
                return "模型未返回内容。"
            }
        }
    }

    // MARK: - 请求

    static func parse(
        text: String,
        config: Config,
        categories: [String] = CategoryCatalog.builtin.map(\.name)
    ) async throws -> Result {
        guard !config.apiKey.isEmpty else { throw AIError.missingKey }
        guard !config.model.isEmpty else { throw AIError.missingModel }
        guard let url = URL(string: config.endpoint) else {
            throw AIError.badPayload("接口地址不合法：\(config.endpoint)")
        }

        let prompt = systemPrompt(categories: categories)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if config.provider.usesAnthropicAPI {
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": config.model,
                "max_tokens": 500,
                "temperature": 0,
                "system": prompt,
                "messages": [["role": "user", "content": text]]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            var body: [String: Any] = [
                "model": config.model,
                "messages": [
                    ["role": "system", "content": prompt],
                    ["role": "user", "content": text]
                ],
                "temperature": 0,
                "max_tokens": 500
            ]
            // 只有明确支持的才加 JSON 约束，避免第三方兼容接口直接报 400
            if config.provider == .deepseek || config.provider == .openai {
                body["response_format"] = ["type": "json_object"]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let content = try answer(from: data, provider: config.provider)
        return try result(from: content)
    }

    /// 连通性测试：拿一条示例账单跑一遍，成功就返回解析摘要。
    static func test(config: Config, sample: String) async throws -> String {
        let parsed = try await parse(text: sample, config: config)
        let amount = Money.plain(parsed.amountCents ?? 0)
        let merchant = parsed.merchant.isEmpty ? "未识别商户" : parsed.merchant
        return "¥\(amount) · \(merchant) · \(parsed.category)"
    }

    /// 连通性测试（读图版）：传一张示例图，看看这一家能不能直接读图。
    static func testVision(config: Config, image: Data) async throws -> String {
        let parsed = try await parse(imageJPEG: image, config: config)
        let amount = Money.plain(parsed.amountCents ?? 0)
        let merchant = parsed.merchant.isEmpty ? "未识别商户" : parsed.merchant
        return "¥\(amount) · \(merchant) · \(parsed.category)"
    }

    // MARK: - 直接读图（多模态）

    /// 把截图压到合适大小再上传：1280 宽、JPEG 0.7。
    /// 一张 iPhone 截图原图 3~8 MB，base64 之后会更大；压完通常在 200~400 KB，识别率没有肉眼可见的下降。
    static func prepare(_ image: UIImage, maxWidth: CGFloat = 1280, quality: CGFloat = 0.7) -> Data? {
        let width = image.size.width * image.scale
        let ratio = min(1, maxWidth / max(1, width))
        let target = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: quality)
    }

    /// 直接把截图交给多模态模型，不经过 OCR。
    static func parse(
        imageJPEG data: Data,
        config: Config,
        categories: [String] = CategoryCatalog.builtin.map(\.name)
    ) async throws -> Result {
        guard !config.apiKey.isEmpty else { throw AIError.missingKey }
        guard !config.model.isEmpty else { throw AIError.missingModel }
        guard let url = URL(string: config.endpoint) else {
            throw AIError.badPayload("接口地址不合法：\(config.endpoint)")
        }

        let base64 = data.base64EncodedString()
        let prompt = imagePrompt(categories: categories)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if config.provider.usesAnthropicAPI {
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": config.model,
                "max_tokens": 600,
                "temperature": 0,
                "system": systemPrompt(categories: categories),
                "messages": [[
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]
                        ],
                        ["type": "text", "text": prompt]
                    ]
                ]]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            var body: [String: Any] = [
                "model": config.model,
                "messages": [
                    ["role": "system", "content": systemPrompt(categories: categories)],
                    [
                        "role": "user",
                        "content": [
                            ["type": "text", "text": prompt],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                        ]
                    ]
                ],
                "temperature": 0,
                "max_tokens": 600
            ]
            if config.provider == .openai {
                body["response_format"] = ["type": "json_object"]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let content = try answer(from: data, provider: config.provider)
        return try result(from: content)
    }

    private static func imagePrompt(categories: [String]) -> String {
        """
        这是一张手机支付成功 / 账单详情 / 银行短信的截图。请直接看图，不要做 OCR 转写，把里面的这一笔账读出来。
        只输出一个 JSON 对象，不要解释、不要 Markdown。

        读数要点：
        - amount：这一笔实际支付或收到的金额（数字，单位元，正数）。有「实付」「付款金额」「金额」就取那个；别取余额、别取优惠券、别取合计里的小计。
        - merchant：付款给谁 / 收款方 / 商户全称，照图上的字写，不要自己改写、不要补全简称。取不到就填空字符串。
        - direction：expense（付款/消费/转账出去）或 income（收款/退款/入账）。
        - category：只能从这些里选一个：\(categories.joined(separator: "、"))。
        - datetime：yyyy-MM-dd HH:mm:ss，图上没有就用当前时间。
        - asset：图上显示的付款方式或账户，比如「微信」「支付宝」「招商银行储蓄卡(1234)」「信用卡」；没有就填空。
        - note：一两句补充，比如商品名、订单号尾号，可空。
        - confidence：0 到 1，表示你对这一笔的把握；字太小、被遮挡、信息不全时给 0.5 以下。
        """
    }

    // MARK: - 提示词

    private static func systemPrompt(categories: [String]) -> String {
        let categoryList = categories.joined(separator: "、")
        return """
        你是记账 App 的账单解析器。用户会给你一段从支付截图里 OCR 出来的文字，你只输出一个 JSON 对象，不要任何解释或 Markdown 代码块。
        JSON 字段：
        - amount：数字，单位元，永远为正数，例如 28.5
        - merchant：收款方或商家名称，尽量短；没有就填空字符串
        - direction：expense（支出）或 income（收入）
        - category：只能从这些里选一个：\(categoryList)（按商户、商品名判断，例如星巴克→餐饮、滴滴→交通、京东→购物、话费→通讯、房租→住房）
        - datetime：yyyy-MM-dd HH:mm:ss；文字里没有就用当前时间
        - asset：付款方式/账户，例如 微信、支付宝、招商银行储蓄卡、信用卡；没有就填空字符串
        - note：补充说明，可空
        - confidence：0 到 1 之间的小数，表示你对自己结果的把握
        """
    }

    // MARK: - 解析返回

    /// OpenAI 兼容：{"choices":[{"message":{"content":"…"}}]}
    /// Anthropic：{"content":[{"type":"text","text":"…"}]}
    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct AnthropicResponse: Decodable {
        struct Block: Decodable {
            let type: String?
            let text: String?
        }
        let content: [Block]
    }

    private static func answer(from data: Data, provider: Provider) throws -> String {
        let decoder = JSONDecoder()

        if provider.usesAnthropicAPI {
            guard let decoded = try? decoder.decode(AnthropicResponse.self, from: data) else {
                throw AIError.badPayload(String(data: data, encoding: .utf8) ?? "空的响应")
            }
            let text = decoded.content.compactMap { $0.text }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AIError.emptyAnswer }
            return text
        }

        guard let decoded = try? decoder.decode(ChatResponse.self, from: data) else {
            throw AIError.badPayload(String(data: data, encoding: .utf8) ?? "空的响应")
        }
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AIError.emptyAnswer
        }
        return content
    }

    private static func result(from content: String) throws -> Result {
        let cleaned = stripCodeFence(content)
        guard let raw = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: raw),
              let object = json as? [String: Any] else {
            throw AIError.badPayload(cleaned)
        }

        let cents = parseAmount(object["amount"])
        let merchant = stringValue(object["merchant"])
        let direction: Direction = {
            let raw = stringValue(object["direction"]).lowercased()
            if raw.contains("income") || raw.contains("收入") || raw.contains("入账") {
                return .income
            }
            return .expense
        }()
        let category = stringValue(object["category"])
        let assetName = stringValue(object["asset"])
        let note = stringValue(object["note"])

        let occurredAt: Date? = {
            let raw = stringValue(object["datetime"])
            guard !raw.isEmpty else { return nil }
            for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .current
                formatter.dateFormat = format
                if let date = formatter.date(from: raw) { return date }
            }
            return ISO8601DateFormatter().date(from: raw)
        }()

        var confidence: Double = 0.85
        if let number = object["confidence"] as? NSNumber {
            confidence = min(1, max(0, number.doubleValue))
        } else if let number = Double(stringValue(object["confidence"])) {
            confidence = min(1, max(0, number))
        }

        return Result(
            amountCents: cents,
            merchant: merchant,
            direction: direction,
            category: category,
            occurredAt: occurredAt,
            assetName: assetName,
            note: note,
            confidence: confidence
        )
    }

    private static func stripCodeFence(_ text: String) -> String {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            if let newline = body.firstIndex(of: "\n") {
                body = String(body[body.index(after: newline)...])
            }
            if let fence = body.range(of: "```", options: .backwards) {
                body = String(body[..<fence.lowerBound])
            }
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // 有些模型会在 JSON 前后加一句话，兜底截取第一个 { 到最后一个 }
        if let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}"), start < end {
            return String(body[start...end])
        }
        return body
    }

    private static func stringValue(_ any: Any?) -> String {
        switch any {
        case let text as String:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }

    private static func parseAmount(_ any: Any?) -> Int? {
        let text = stringValue(any)
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let value = Money.cents(from: text), value > 0 { return value }
        if let number = Double(text) {
            let cents = Int((number * 100).rounded())
            return cents > 0 ? cents : nil
        }
        return nil
    }
}
