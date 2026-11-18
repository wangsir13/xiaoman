import Foundation
import UIKit

/// 一条「某分类花了多少」
struct CategoryTotal: Identifiable, Hashable {
    var id: String { category.name }
    let category: CategoryItem
    let cents: Int
    let share: Double
}

/// 记账数据仓库：全部 JSON 落盘（不依赖 Core Data / iCloud，自签环境最稳）
@MainActor
final class LedgerStore: ObservableObject {

    // MARK: - 对外状态

    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var assets: [Asset] = []
    @Published private(set) var budgetPlan: BudgetPlan = BudgetPlan()
    @Published private(set) var customCategories: [CategoryItem] = []
    /// 等待用户确认的识别结果
    @Published var pendingDrafts: [ImportDraft] = []
    /// 顶部小提示
    @Published var banner: String?

    // MARK: - 路径

    private let fileManager = FileManager.default
    private let folderURL: URL
    private let transactionsURL: URL
    private let assetsURL: URL
    private let budgetURL: URL
    private let categoriesURL: URL
    private var lastLoadedStamp: Date?

    // MARK: - 生命周期

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folderURL = base.appendingPathComponent("Xiaoman", isDirectory: true)
        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        transactionsURL = folderURL.appendingPathComponent("transactions.json")
        assetsURL = folderURL.appendingPathComponent("assets.json")
        budgetURL = folderURL.appendingPathComponent("budget.json")
        categoriesURL = folderURL.appendingPathComponent("categories.json")
        loadAll()
    }

    // MARK: - 读写

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func loadAll() {
        if let data = try? Data(contentsOf: transactionsURL),
           let items = try? decoder.decode([Transaction].self, from: data) {
            transactions = items
            sortTransactions()
        }
        if let data = try? Data(contentsOf: assetsURL),
           let items = try? decoder.decode([Asset].self, from: data) {
            assets = items
        }
        if let data = try? Data(contentsOf: budgetURL),
           let plan = try? decoder.decode(BudgetPlan.self, from: data) {
            budgetPlan = plan
        }
        if let data = try? Data(contentsOf: categoriesURL),
           let items = try? decoder.decode([CategoryItem].self, from: data) {
            customCategories = items
        }
        if assets.isEmpty { assets = LedgerStore.defaultAssets() }
        lastLoadedStamp = currentStamp()
    }

    /// 别的地方（App Intent）改了磁盘的话，前台定时调这个同步过来
    @discardableResult
    func reloadIfChanged() -> Bool {
        let stamp = currentStamp()
        guard stamp != lastLoadedStamp else { return false }
        loadAll()
        return true
    }

    func reload() {
        loadAll()
    }

    private func currentStamp() -> Date {
        let urls = [transactionsURL, assetsURL, budgetURL, categoriesURL]
        var newest = Date.distantPast
        for url in urls {
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = values.contentModificationDate, date > newest {
                newest = date
            }
        }
        return newest
    }

    private func saveTransactions() {
        if let data = try? encoder.encode(transactions) {
            try? data.write(to: transactionsURL, options: .atomic)
        }
        lastLoadedStamp = currentStamp()
    }

    private func saveAssets() {
        if let data = try? encoder.encode(assets) {
            try? data.write(to: assetsURL, options: .atomic)
        }
        lastLoadedStamp = currentStamp()
    }

    private func saveBudget() {
        if let data = try? encoder.encode(budgetPlan) {
            try? data.write(to: budgetURL, options: .atomic)
        }
        lastLoadedStamp = currentStamp()
    }

    private func saveCategories() {
        if let data = try? encoder.encode(customCategories) {
            try? data.write(to: categoriesURL, options: .atomic)
        }
        lastLoadedStamp = currentStamp()
    }

    private func sortTransactions() {
        transactions.sort { $0.occurredAt > $1.occurredAt }
    }

    // MARK: - 备份 / 恢复

    /// 把整份账本写成一个 JSON 临时文件，交给分享面板保存到「文件」
    func makeBackupFile() -> URL? {
        let envelope = BackupEnvelope(
            transactions: transactions,
            assets: assets,
            plan: budgetPlan,
            customCategories: customCategories
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return nil }

        let name = "xiaoman-backup-\(BackupEnvelope.stamp()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// 用备份文件覆盖当前账本，成功返回恢复的笔数；失败抛出可读的原因
    @discardableResult
    func restoreBackup(from data: Data) throws -> Int {
        guard !data.isEmpty else {
            throw BackupError.emptyFile
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let envelope: BackupEnvelope
        do {
            envelope = try decoder.decode(BackupEnvelope.self, from: data)
        } catch let error as DecodingError {
            throw BackupError.badEnvelope(Self.describe(error))
        } catch {
            throw BackupError.badEnvelope(error.localizedDescription)
        }

        transactions = envelope.transactions
        assets = envelope.assets.isEmpty ? Self.defaultAssets() : envelope.assets
        budgetPlan = envelope.plan
        customCategories = envelope.customCategories

        sortTransactions()
        saveTransactions()
        saveAssets()
        saveBudget()
        saveCategories()
        flash("已从备份恢复 \(transactions.count) 笔账")
        return transactions.count
    }

    /// 把 DecodingError 翻译成「哪个字段没对上」，方便用户在短提示里看到重点
    static func describe(_ error: DecodingError) -> String {
        func path(_ keys: [CodingKey]) -> String {
            keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().dropFirst().description
        }

        switch error {
        case let .keyNotFound(key, context):
            return "缺少字段 \(key.stringValue)（位置：\(path(context.codingPath))）"
        case let .typeMismatch(type, context):
            return "字段类型不符，期望 \(type)，位置：\(path(context.codingPath))"
        case let .valueNotFound(type, context):
            return "字段没有值，期望 \(type)，位置：\(path(context.codingPath))"
        case let .dataCorrupted(context):
            return "JSON 内容损坏：\(context.debugDescription)（位置：\(path(context.codingPath))）"
        @unknown default:
            return "解析失败"
        }
    }

    // MARK: - 默认资产（第一次打开时给几个空的，用户改名字即可）

    static func defaultAssets() -> [Asset] {
        [
            Asset(name: "微信钱包", kind: .wallet, openingBalanceCents: 0,
                  keywords: ["微信", "零钱"], colorHex: "07C160"),
            Asset(name: "支付宝", kind: .wallet, openingBalanceCents: 0,
                  keywords: ["支付宝", "余额宝", "花呗"], colorHex: "1677FF"),
            Asset(name: "银行卡", kind: .bankCard, openingBalanceCents: 0,
                  keywords: ["银行", "储蓄卡"], colorHex: "E4572E")
        ]
    }

    // MARK: - 账目增删改

    func upsert(_ transaction: Transaction) {
        var item = transaction
        if item.fingerprint.isEmpty {
            item.fingerprint = Transaction.makeFingerprint(
                source: item.source,
                amountCents: item.amountCents,
                merchant: item.merchant,
                date: item.occurredAt
            )
        }
        if let index = transactions.firstIndex(where: { $0.id == item.id }) {
            transactions[index] = item
        } else {
            transactions.append(item)
        }
        sortTransactions()
        saveTransactions()
    }

    func delete(_ transaction: Transaction) {
        transactions.removeAll { $0.id == transaction.id }
        saveTransactions()
    }

    func clearAll() {
        transactions.removeAll()
        saveTransactions()
    }

    /// 批量导入（微信/支付宝 CSV）：按指纹去重，返回新增和跳过的条数
    @discardableResult
    func importTransactions(_ incoming: [Transaction]) -> (added: Int, skipped: Int) {
        var fingerprints = Set(transactions.map { $0.fingerprint })
        var added = 0
        var skipped = 0

        for var item in incoming {
            if item.fingerprint.isEmpty {
                item.fingerprint = Transaction.makeFingerprint(
                    source: item.source,
                    amountCents: item.amountCents,
                    merchant: item.merchant,
                    date: item.occurredAt
                )
            }
            if fingerprints.contains(item.fingerprint) {
                skipped += 1
                continue
            }
            fingerprints.insert(item.fingerprint)
            transactions.append(item)
            added += 1
        }

        if added > 0 {
            sortTransactions()
            saveTransactions()
        }
        flash("导入 \(added) 笔" + (skipped > 0 ? "，跳过重复 \(skipped) 笔" : ""))
        return (added, skipped)
    }

    // MARK: - 资产

    func asset(for id: UUID?) -> Asset? {
        guard let id = id else { return nil }
        return assets.first { $0.id == id }
    }

    /// 资产当前余额 = 期初 + 绑到它的所有收支
    func balanceCents(of asset: Asset) -> Int {
        var value = asset.openingBalanceCents
        for item in transactions where item.assetID == asset.id {
            // 期初余额是「从某一刻起」的数：那之前的历史账单不再重复扣减
            if let openingAt = asset.openingAt, item.occurredAt < openingAt { continue }
            value += item.signedCents
        }
        return value
    }

    func balanceText(of asset: Asset) -> String {
        Money.display(balanceCents(of: asset))
    }

    /// 所有资产余额之和（把负债也算进去，所以是净额）
    var totalBalanceCents: Int {
        assets.reduce(0) { $0 + balanceCents(of: $1) }
    }

    func addAsset(_ asset: Asset) {
        assets.append(asset)
        saveAssets()
    }

    func updateAsset(_ asset: Asset) {
        if let index = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[index] = asset
        } else {
            assets.append(asset)
        }
        saveAssets()
    }

    func deleteAsset(_ asset: Asset) {
        assets.removeAll { $0.id == asset.id }
        for index in transactions.indices where transactions[index].assetID == asset.id {
            transactions[index].assetID = nil
        }
        saveAssets()
        saveTransactions()
    }

    /// 从 OCR 文本里猜这笔账该记到哪个资产
    func guessAsset(in text: String) -> UUID? {
        guard !text.isEmpty else { return nil }
        let haystack = text.lowercased()
        var best: (Asset, Int)?
        for asset in assets where !asset.isArchived {
            var score = 0
            for keyword in asset.keywords where !keyword.isEmpty {
                if haystack.contains(keyword.lowercased()) { score += keyword.count + 2 }
            }
            if !asset.name.isEmpty, haystack.contains(asset.name.lowercased()) {
                score += asset.name.count
            }
            if score > 0, score > (best?.1 ?? 0) {
                best = (asset, score)
            }
        }
        return best?.0.id
    }

    // MARK: - 分类

    var categories: [CategoryItem] {
        CategoryCatalog.builtin + customCategories
    }

    func category(named name: String) -> CategoryItem {
        categories.first { $0.name == name }
            ?? CategoryCatalog.builtin[CategoryCatalog.builtin.count - 1]
    }

    func addCategory(_ item: CategoryItem) {
        guard !item.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !categories.contains(where: { $0.name == item.name }) else { return }
        customCategories.append(item)
        saveCategories()
    }

    func deleteCategory(_ item: CategoryItem) {
        customCategories.removeAll { $0.id == item.id }
        saveCategories()
    }

    /// 某个月的支出按分类汇总，从多到少
    func expenseByCategory(in month: Date = Date()) -> [CategoryTotal] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        var sums: [String: Int] = [:]
        var total = 0
        for item in transactions where item.direction == .expense && interval.contains(item.occurredAt) {
            sums[item.category, default: 0] += item.amountCents
            total += item.amountCents
        }
        return sums
            .map { name, cents in
                CategoryTotal(
                    category: category(named: name),
                    cents: cents,
                    share: total > 0 ? Double(cents) / Double(total) : 0
                )
            }
            .sorted { $0.cents > $1.cents }
    }

    // MARK: - 预算

    func updateBudget(_ plan: BudgetPlan) {
        budgetPlan = plan
        saveBudget()
    }

    func dailyBudgets(in month: Date = Date()) -> [DailyBudget] {
        BudgetEngine.dailyBudgets(month: month, plan: budgetPlan, transactions: transactions)
    }

    var todayBudget: DailyBudget? {
        BudgetEngine.todayBudget(plan: budgetPlan, transactions: transactions)
    }

    var monthRemainingCents: Int {
        BudgetEngine.monthRemainingCents(plan: budgetPlan, transactions: transactions)
    }

    /// 今天花了多少（固定支出也计入，首页「今日支出」看的是真实花费）
    func spentToday() -> Int {
        let calendar = Calendar.current
        return transactions
            .filter { $0.direction == .expense && calendar.isDateInToday($0.occurredAt) }
            .reduce(0) { $0 + $1.amountCents }
    }

    /// 本月「占预算」的支出：不含标记为固定支出的那几笔（房租、话费）
    var budgetSpentThisMonth: Int {
        let calendar = Calendar.current
        let clearedStart = budgetPlan.clearedBefore
        return transactions
            .filter { item in
                guard item.direction == .expense, !item.isFixedFlag else { return false }
                guard calendar.isDate(item.occurredAt, equalTo: Date(), toGranularity: .month) else { return false }
                if let clearedStart, item.occurredAt < clearedStart { return false }
                return true
            }
            .reduce(0) { $0 + $1.amountCents }
    }

    // MARK: - 统计

    /// 某个月的（支出, 收入），单位分
    func monthSummary(for date: Date = Date()) -> (expense: Int, income: Int) {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return (0, 0) }
        var expense = 0
        var income = 0
        for item in transactions where interval.contains(item.occurredAt) {
            if item.direction == .expense {
                expense += item.amountCents
            } else {
                income += item.amountCents
            }
        }
        return (expense, income)
    }

    func summary(for date: Date = Date()) -> (expense: Int, income: Int) {
        monthSummary(for: date)
    }

    func transactions(in month: Date = Date()) -> [Transaction] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return transactions }
        return transactions.filter { interval.contains($0.occurredAt) }
    }

    func recentTransactions(limit: Int = 5) -> [Transaction] {
        Array(transactions.prefix(limit))
    }

    // MARK: - 导入：解析结果入队

    @discardableResult
    func enqueue(text: String, sourceHint: BillSource? = nil, imageFileName: String? = nil) -> ImportDraft {
        var draft = BillParser.parse(text: text, sourceHint: sourceHint)
        draft.imageFileName = imageFileName
        draft.rawText = text
        if let assetID = guessAsset(in: text) {
            draft.assetID = assetID
            draft.assetName = asset(for: assetID)?.name ?? ""
        }
        return enqueue(draft: draft)
    }

    /// 先跑本地规则，再在用户开了 AI 时把整段文字交给大模型补字段。
    /// 联网只在设置里填了 Key 并打开开关时发生，否则和 `enqueue(text:)` 完全一样。
    @discardableResult
    func enqueueSmart(text: String, sourceHint: BillSource? = nil, imageFileName: String? = nil) async -> ImportDraft {
        var draft = BillParser.parse(text: text, sourceHint: sourceHint)
        draft.imageFileName = imageFileName
        draft.rawText = text

        let config = AIParser.Config.load()
        if config.isUsable {
            do {
                // 把内置 + 自定义分类一起交给模型，这样「分类」也是 AI 判的
                let ai = try await AIParser.parse(
                    text: text,
                    config: config,
                    categories: categories.map(\.name)
                )
                draft = merge(draft, with: ai)
            } catch {
                flash("AI 解析失败，已用本地规则")
            }
        }

        if let assetID = guessAsset(in: text) {
            draft.assetID = assetID
            draft.assetName = asset(for: assetID)?.name ?? ""
        }
        return enqueue(draft: draft)
    }

    /// 把模型的字段合并进本地解析结果：模型给了就用模型的，没给就留本地的。
    private func merge(_ draft: ImportDraft, with ai: AIParser.Result) -> ImportDraft {
        var result = draft
        if let cents = ai.amountCents {
            result.amountText = Money.plain(cents)
        }
        if !ai.merchant.isEmpty {
            result.merchant = ai.merchant
        }
        result.direction = ai.direction
        if !ai.category.isEmpty, let matched = resolvedCategory(ai.category) {
            result.category = matched
        }
        if let date = ai.occurredAt {
            result.occurredAt = date
        }
        if !ai.note.isEmpty {
            result.note = ai.note
        }
        if !ai.assetName.isEmpty {
            let matched = assets.first { asset in
                if asset.name == ai.assetName { return true }
                return asset.keywords.contains { keyword in
                    !keyword.isEmpty && ai.assetName.localizedCaseInsensitiveContains(keyword)
                }
            }
            if let matched {
                result.assetID = matched.id
                result.assetName = matched.name
            } else {
                result.assetName = ai.assetName
            }
        }
        result.confidence = max(draft.confidence, ai.confidence)
        return result
    }

    /// 模型给的分类名可能是「餐饮美食」「交通出行」这种带后缀的，做一次宽松匹配
    private func resolvedCategory(_ raw: String) -> String? {
        let name = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "类", with: "")
        guard !name.isEmpty else { return nil }
        if let exact = categories.first(where: { $0.name == name }) { return exact.name }
        if let partial = categories.first(where: {
            name.contains($0.name) || $0.name.contains(name)
        }) {
            return partial.name
        }
        return nil
    }

    /// 把已经解析好的草稿入队（App Intent / 深链接会先覆盖字段再调用这里）
    @discardableResult
    func enqueue(draft: ImportDraft) -> ImportDraft {
        var draft = draft
        if draft.assetID == nil {
            let haystack = draft.rawText + " " + draft.merchant
            if let guessed = guessAsset(in: haystack) {
                draft.assetID = guessed
            }
        }
        if draft.assetName.isEmpty, let asset = asset(for: draft.assetID) {
            draft.assetName = asset.name
        }
        draft.isDuplicate = isDuplicate(draft)

        let auto = shouldAutoCommit(draft)
        if auto {
            _ = commit(draft)
            flash("已自动记账 \(Money.display(draft.amountCents ?? 0))")
        } else {
            pendingDrafts.append(draft)
        }
        return draft
    }

    private func shouldAutoCommit(_ draft: ImportDraft) -> Bool {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "autoCommit") as? Bool ?? true
        guard enabled, draft.isValid, draft.confidence >= 0.8 else { return false }
        if draft.isDuplicate { return false }
        return true
    }

    func isDuplicate(_ draft: ImportDraft) -> Bool {
        guard let cents = draft.amountCents, cents > 0 else { return false }
        let fingerprint = Transaction.makeFingerprint(
            source: draft.source,
            amountCents: cents,
            merchant: draft.merchant,
            date: draft.occurredAt
        )
        return transactions.contains { $0.fingerprint == fingerprint }
    }

    /// 把草稿写成正式账目；金额非法返回 false
    @discardableResult
    func commit(_ draft: ImportDraft) -> Bool {
        guard let cents = draft.amountCents, cents > 0 else { return false }
        let merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = Transaction(
            amountCents: cents,
            direction: draft.direction,
            merchant: merchant,
            category: draft.category,
            source: draft.source,
            occurredAt: draft.occurredAt,
            note: draft.note,
            rawText: draft.rawText,
            assetID: draft.assetID
        )
        item.fingerprint = Transaction.makeFingerprint(
            source: draft.source,
            amountCents: cents,
            merchant: merchant,
            date: draft.occurredAt
        )
        upsert(item)
        return true
    }

    @discardableResult
    func commitAllDrafts() -> Int {
        var saved = 0
        for draft in pendingDrafts where draft.isValid {
            if commit(draft) { saved += 1 }
        }
        let skipped = pendingDrafts.count - saved
        pendingDrafts.removeAll()
        if saved > 0 {
            flash(skipped > 0 ? "已保存 \(saved) 条，\(skipped) 条缺金额未保存" : "已保存 \(saved) 条")
        } else {
            flash("没有可保存的记录：金额为空")
        }
        return saved
    }

    func discardAllDrafts() {
        pendingDrafts.removeAll()
    }

    func commitAndRemove(_ draft: ImportDraft) {
        guard commit(draft) else {
            flash("金额无效，未保存")
            return
        }
        removeDraft(draft.id)
    }

    func removeDraft(_ id: UUID) {
        pendingDrafts.removeAll { $0.id == id }
    }

    // MARK: - 提示

    func flash(_ message: String) {
        banner = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let self = self else { return }
            if self.banner == message {
                self.banner = nil
            }
        }
    }
}
