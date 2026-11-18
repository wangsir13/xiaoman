import Foundation

/// 一个分类。用户可以在设置里加自己的分类（存本地，不落进 Transaction 之外的地方）
struct CategoryItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var colorHex: String
    var kind: Direction
    var isBuiltin: Bool = false

    static func == (lhs: CategoryItem, rhs: CategoryItem) -> Bool { lhs.id == rhs.id }
}

/// 分类目录 + 基于商户名的自动归类
enum CategoryCatalog {

    static let defaultName = "其他"

    /// 系统预置分类：支出在前、收入在后
    static let builtin: [CategoryItem] = [
        CategoryItem(name: "餐饮", symbol: "fork.knife", colorHex: "FF7043", kind: .expense, isBuiltin: true),
        CategoryItem(name: "交通", symbol: "car.fill", colorHex: "42A5F5", kind: .expense, isBuiltin: true),
        CategoryItem(name: "购物", symbol: "bag.fill", colorHex: "AB47BC", kind: .expense, isBuiltin: true),
        CategoryItem(name: "日用", symbol: "house.fill", colorHex: "26A69A", kind: .expense, isBuiltin: true),
        CategoryItem(name: "娱乐", symbol: "gamecontroller.fill", colorHex: "EC407A", kind: .expense, isBuiltin: true),
        CategoryItem(name: "医疗", symbol: "cross.case.fill", colorHex: "EF5350", kind: .expense, isBuiltin: true),
        CategoryItem(name: "住房", symbol: "building.2.fill", colorHex: "8D6E63", kind: .expense, isBuiltin: true),
        CategoryItem(name: "通讯", symbol: "antenna.radiowaves.left.and.right", colorHex: "5C6BC0", kind: .expense, isBuiltin: true),
        CategoryItem(name: "学习", symbol: "book.fill", colorHex: "7E57C2", kind: .expense, isBuiltin: true),
        CategoryItem(name: "人情", symbol: "gift.fill", colorHex: "F06292", kind: .expense, isBuiltin: true),
        CategoryItem(name: "工资", symbol: "yensign.circle.fill", colorHex: "66BB6A", kind: .income, isBuiltin: true),
        CategoryItem(name: "理财", symbol: "chart.line.uptrend.xyaxis", colorHex: "9CCC65", kind: .income, isBuiltin: true),
        CategoryItem(name: defaultName, symbol: "ellipsis.circle.fill", colorHex: "90A4AE", kind: .expense, isBuiltin: true)
    ]

    static var all: [String] { builtin.map(\.name) }

    private static let rules: [(category: String, keywords: [String])] = [
        ("餐饮", ["餐", "饭", "食", "咖啡", "茶", "奶茶", "烧烤", "火锅", "外卖",
                 "麦当劳", "肯德基", "星巴克", "瑞幸", "蜜雪", "海底捞", "面馆",
                 "便利店", "烘焙", "蛋糕", "小吃", "食堂", "餐厅", "料理"]),
        ("交通", ["地铁", "公交", "打车", "滴滴", "出租车", "高铁", "火车", "机票",
                 "加油", "停车", "ETC", "高速", "单车", "充电桩", "航空", "代驾"]),
        ("购物", ["超市", "商场", "淘宝", "天猫", "拼多多", "京东", "唯品会",
                 "优衣库", "服饰", "数码", "苹果", "小米", "旗舰店", "商城", "网购"]),
        ("日用", ["日用", "百货", "洗衣", "理发", "快递", "五金", "家居", "清洁"]),
        ("娱乐", ["电影", "游戏", "KTV", "健身", "演出", "门票", "视频会员",
                 "音乐", "网吧", "剧本杀", "影院"]),
        ("医疗", ["药", "医院", "诊所", "体检", "口腔", "挂号", "卫生院"]),
        ("住房", ["房租", "物业", "水费", "电费", "燃气", "供暖", "家政"]),
        ("通讯", ["话费", "流量", "宽带", "中国移动", "中国联通", "中国电信"]),
        ("学习", ["书店", "图书", "课程", "培训", "学费", "考试", "文具"]),
        ("人情", ["红包", "转账", "礼金", "份子"]),
        ("工资", ["工资", "薪资", "薪", "奖金", "补贴", "报销"]),
        ("理财", ["基金", "理财", "股票", "利息", "收益", "余额宝"])
    ]

    static func suggest(merchant: String, source: BillSource) -> String {
        guard !merchant.isEmpty else { return defaultName }
        for rule in rules where rule.keywords.contains(where: { merchant.contains($0) }) {
            return rule.category
        }
        return defaultName
    }

    /// 所有预置分类 + 用户自定义分类
    static func merged(custom: [CategoryItem]) -> [CategoryItem] {
        builtin + custom
    }
}
