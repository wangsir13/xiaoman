"""把 Xiaoman/Parsing/BillParser.swift 逐条移植成 Python，用真实样例校验正则行为。

Windows 上没有 swiftc，无法编译运行 Swift，所以用这个脚本「离线跑一遍」解析逻辑，
确认金额 / 方向 / 商户 / 时间 / 置信度在各类账单文本上得到预期结果。
脚本里的规则必须与 Swift 版保持一致；改 Swift 时记得同步这里。

用法：python tools/parser_check.py
"""

import re
import sys
from datetime import datetime, timedelta

sys.stdout.reconfigure(encoding="utf-8")

# ---------------------------------------------------------------- 词法常量

AMOUNT_TOKEN = r"([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)"

LABELED_AMOUNT_PATTERNS = [
    r"(?:实付款|实付|实收款|实际支付|付款金额|支付金额|交易金额|订单金额|消费金额|合计|总计|应付|金额)[^0-9¥]{0,10}¥?\s*" + AMOUNT_TOKEN,
    r"¥\s*" + AMOUNT_TOKEN,
    AMOUNT_TOKEN + r"\s*元",
]

SOURCE_KEYWORDS = [
    ("wechat", ["微信支付", "微信", "零钱", "转账给", "扫二维码付款", "二维码收款"]),
    ("alipay", ["支付宝", "账单详情", "余额宝", "花呗", "借呗", "余额收支"]),
    ("unionpay", ["云闪付", "银联", "银联商务"]),
    ("meituan", ["美团", "美团外卖", "大众点评"]),
    ("jd", ["京东", "白条", "京东支付", "京东商城"]),
    ("bank", ["工商银行", "招商银行", "建设银行", "中国银行", "农业银行",
              "交通银行", "邮储银行", "中信银行", "浦发银行", "民生银行",
              "光大银行", "兴业银行", "平安银行", "广发银行", "华夏银行",
              "储蓄卡", "信用卡", "尾号"]),
]

NOISE_PATTERNS = [
    r"[0-9]{4}[-/年][0-9]{1,2}[-/月][0-9]{1,2}日?",
    r"[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?",
    r"[0-9]{6,}",
    r"(?:订单号|交易单号|流水号|凭证号|商户单号)[:：]?\s*[A-Za-z0-9]+",
    r"\*{2,}[0-9]{2,4}",
]

INCOME_KEYWORDS = ["收款成功", "已到账", "入账", "退款成功", "已退款", "收到转账", "收款到账"]

MERCHANT_PATTERNS = [
    r"(?:收款方|收款人|商户全称|商户名称|商家名称)[:：]?\s*([^\n]{2,30})",
    r"(?:付款给|转账给|支付给)[:：]?\s*([^\n]{2,26})",
    r"(?:来自|对方|付款方|转账方)[:：]?\s*([^\n]{2,20})",
    r"(?:向|在)\s*([\u4e00-\u9fa5A-Za-z0-9·-]{2,20})\s*(?:消费|支付|付款|刷卡|扣款)",
]

STOP_WORDS = [
    "支付成功", "付款成功", "交易成功", "收款成功", "转账成功", "已到账",
    "账单详情", "微信支付", "支付宝", "云闪付", "京东支付", "美团外卖",
    "交易单号", "订单号", "商户单号", "流水号", "创建时间", "付款时间",
    "转账时间", "付款方式", "支付方式", "当前状态", "全部账单", "查看更多",
    "银行卡", "零钱", "余额", "积分", "优惠", "实付", "合计", "收款方",
    "商户全称", "商户名称", "商品说明", "储蓄卡", "信用卡", "尾号",
    "支付金额", "交易金额", "订单金额", "消费金额", "付款金额", "实付款",
    "人民币", "总计", "应付", "商品名称",
    "运行", "轻点背面", "展开", "详情",
]

GENERIC_LABELS = {
    "交易", "支付", "付款", "消费", "订单", "收款", "转账", "实付",
    "合计", "总计", "应付", "余额", "金额", "商品", "说明", "时间",
    "方式", "状态", "详情", "全部账单",
}

CATEGORY_RULES = [
    ("餐饮", ["餐", "饭", "食", "咖啡", "茶", "奶茶", "烧烤", "火锅", "外卖",
              "麦当劳", "肯德基", "星巴克", "瑞幸", "蜜雪", "海底捞", "面馆",
              "便利店", "烘焙", "蛋糕", "小吃", "食堂"]),
    ("交通", ["地铁", "公交", "打车", "滴滴", "出租车", "高铁", "火车", "机票",
              "加油", "停车", "ETC", "高速", "单车", "充电桩", "航空"]),
    ("购物", ["超市", "商场", "淘宝", "天猫", "拼多多", "京东", "唯品会",
              "优衣库", "服饰", "数码", "苹果", "小米", "旗舰店"]),
    ("日用", ["日用", "百货", "洗衣", "理发", "快递", "五金", "家居"]),
    ("娱乐", ["电影", "游戏", "KTV", "健身", "演出", "门票", "视频会员",
              "音乐", "网吧", "剧本杀"]),
    ("医疗", ["药", "医院", "诊所", "体检", "口腔", "挂号", "卫生院"]),
    ("住房", ["房租", "物业", "水费", "电费", "燃气", "供暖", "家政"]),
    ("通讯", ["话费", "流量", "宽带", "中国移动", "中国联通", "中国电信"]),
    ("学习", ["书店", "图书", "课程", "培训", "学费", "考试", "文具"]),
    ("人情", ["红包", "转账", "礼金", "份子"]),
    ("工资", ["工资", "薪资", "薪", "奖金", "补贴", "报销"]),
    ("理财", ["基金", "理财", "股票", "利息", "收益", "余额宝"]),
]

# ---------------------------------------------------------------- 基础工具


def matches(pattern, text):
    """返回所有匹配的第 1 个分组（与 Swift 的 allMatches 一致）。"""
    out = []
    for m in re.finditer(pattern, text, re.IGNORECASE):
        if m.lastindex and m.groups():
            out.append(m.group(1))
    return out


def first_groups(pattern, text):
    m = re.search(pattern, text, re.IGNORECASE)
    if not m or not m.groups():
        return None
    return list(m.groups())


def replacing_all(pattern, text, replacement=" "):
    return re.sub(pattern, replacement, text, flags=re.IGNORECASE)


def normalize(text):
    out = []
    for ch in text:
        code = ord(ch)
        if 0xFF01 <= code <= 0xFF5E:
            out.append(chr(code - 0xFEE0))
        elif code == 0xFFE5:
            out.append("¥")
        elif code in (0x3000, 0x00A0):
            out.append(" ")
        else:
            out.append(ch)
    return "".join(out)


def cents_from(text):
    """Money.cents(from:) 的移植。"""
    from decimal import Decimal, ROUND_HALF_UP

    value = text.strip()
    for junk in ("¥", "￥", "元", " "):
        value = value.replace(junk, "")
    if not value:
        return None
    if "." in value:
        value = value.replace(",", "")
    else:
        value = value.replace(",", ".")
    try:
        amount = Decimal(value) * 100
    except Exception:
        return None
    return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def plain(cents):
    return "%d.%02d" % (cents // 100, cents % 100)


# ---------------------------------------------------------------- 解析步骤


def detect_source(text):
    for source, words in SOURCE_KEYWORDS:
        if any(w in text for w in words):
            return source
    return "other"


def mask_noise(text):
    result = text
    for pattern in NOISE_PATTERNS:
        result = replacing_all(pattern, result)
    return result


def is_plausible(cents):
    return cents is not None and 0 < cents <= 100_000_000


def extract_amount(joined, masked):
    for pattern in LABELED_AMOUNT_PATTERNS:
        for token in matches(pattern, joined):
            cents = cents_from(token)
            if is_plausible(cents):
                return cents
    for line in masked.split("\n"):
        line = line.strip()
        if re.fullmatch(r"[0-9]{1,7}(?:\.[0-9]{2})", line):
            cents = cents_from(line)
            if is_plausible(cents):
                return cents
    for token in matches(r"([0-9]+\.[0-9]{2})", masked):
        cents = cents_from(token)
        if is_plausible(cents):
            return cents
    return None


def detect_direction(text):
    if any(w in text for w in INCOME_KEYWORDS):
        return "income"
    if re.search(r"\+\s*¥?\s*[0-9]", text):
        return "income"
    return "expense"


def clean_merchant(raw):
    text = raw.strip()
    text = text.strip("：:，,。.·-—|/ 「」“”\"'")
    for word in STOP_WORDS:
        idx = text.find(word)
        if idx >= 0:
            text = text[:idx]
    text = text.strip("：:，,。.·-—|/ ")
    if len(text) < 2 or len(text) > 30:
        return ""
    if re.fullmatch(r"[0-9¥\s.,:/-]+", text):
        return ""
    if re.search(r"[0-9]{1,2}:[0-9]{2}", text):
        return ""
    if re.search(r"[0-9]+\.[0-9]{2}", text):
        return ""
    if text in GENERIC_LABELS:
        return ""
    if not re.search(r"[\u4e00-\u9fa5A-Za-z]", text):
        return ""
    return text[:24]


def extract_merchant(lines, joined):
    for pattern in MERCHANT_PATTERNS:
        for raw in matches(pattern, joined):
            cleaned = clean_merchant(raw)
            if cleaned:
                return cleaned
    for line in lines:
        cleaned = clean_merchant(line)
        if cleaned:
            return cleaned
    return ""


def build_date(year, month, day, hour, minute, second, now):
    try:
        year, month, day = int(year), int(month), int(day)
        hour, minute, second = int(hour), int(minute), int(second or 0)
    except (TypeError, ValueError):
        return None
    if not (1970 <= year <= 2100 and 1 <= month <= 12 and 1 <= day <= 31):
        return None
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        return None
    try:
        return datetime(year, month, day, hour, minute, second)
    except ValueError:
        return None


def extract_date(text, now):
    groups = first_groups(
        r"([0-9]{4})[-/年]([0-9]{1,2})[-/月]([0-9]{1,2})日?\s*([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?",
        text,
    )
    if groups:
        return build_date(groups[0], groups[1], groups[2], groups[3], groups[4], groups[5], now)

    groups = first_groups(r"([0-9]{4})[-/年]([0-9]{1,2})[-/月]([0-9]{1,2})", text)
    if groups:
        return build_date(groups[0], groups[1], groups[2], 12, 0, 0, now)

    groups = first_groups(r"([0-9]{1,2})月([0-9]{1,2})日\s*([0-9]{1,2}):([0-9]{2})", text)
    if groups:
        return build_date(now.year, groups[0], groups[1], groups[2], groups[3], 0, now)

    groups = first_groups(r"(今天|昨天|前天)\s*([0-9]{1,2}):([0-9]{2})", text)
    if groups:
        offset = {"昨天": -1, "前天": -2}.get(groups[0] or "", 0)
        base = now + timedelta(days=offset)
        return build_date(base.year, base.month, base.day, groups[1], groups[2], 0, now)

    groups = first_groups(r"(?:^|\s)([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?(?:\s|$)", text)
    if groups:
        return build_date(now.year, now.month, now.day, groups[0], groups[1], groups[2], now)

    return None


def suggest_category(merchant, source):
    if not merchant:
        return "其他"
    for category, keywords in CATEGORY_RULES:
        if any(k in merchant for k in keywords):
            return category
    return "其他"


def parse(text, source_hint=None, now=None):
    now = now or datetime(2026, 11, 18, 10, 22, 31)
    normalized = normalize(text)
    lines = [line.strip() for line in normalized.split("\n") if line.strip()]
    joined = "\n".join(lines)

    source = source_hint or detect_source(joined)
    masked = mask_noise(joined)
    cents = extract_amount(joined, masked)
    direction = detect_direction(joined)
    merchant = extract_merchant(lines, joined)
    occurred = extract_date(joined, now)

    confidence = 0.2
    if cents is not None:
        confidence += 0.45
    if source != "other":
        confidence += 0.15
    if merchant:
        confidence += 0.15
    if occurred is not None:
        confidence += 0.05

    return {
        "amount": plain(cents) if cents is not None else "",
        "cents": cents,
        "direction": direction,
        "merchant": merchant,
        "category": suggest_category(merchant, source),
        "source": source,
        "date": occurred.strftime("%Y-%m-%d %H:%M:%S") if occurred else "(未识别)",
        "confidence": round(min(confidence, 1.0), 2),
    }


# ---------------------------------------------------------------- 用例

WECHAT = """微信支付
支付成功
¥28.50
星巴克咖啡(国贸店)
收款方 星巴克咖啡(国贸店)
支付方式 零钱
支付时间 2026-11-18 10:22:31
账单详情
"""

ALIPAY = """账单详情
星巴克咖啡(北京国贸店)
-28.50
交易成功
付款方式 余额宝
创建时间 2026-11-18 10:22:31
订单号 2026111822001234567890
"""

BANK = "【招商银行】您尾号1234的储蓄卡于11月18日10:22向星巴克咖啡消费人民币28.50元，余额1,234.56元。"

CASES = [
    ("微信付款页", WECHAT, None, {"cents": 2850, "direction": "expense", "merchant": "星巴克咖啡(国贸店)", "source": "wechat", "category": "餐饮", "confidence": 1.0}),
    ("支付宝账单", ALIPAY, None, {"cents": 2850, "direction": "expense", "merchant": "星巴克咖啡(北京国贸店)", "source": "alipay", "category": "餐饮", "confidence": 1.0}),
    ("银行短信", BANK, None, {"cents": 2850, "direction": "expense", "merchant": "星巴克咖啡", "source": "bank", "category": "餐饮", "confidence": 1.0}),
    ("云闪付付款", "云闪付\n付款成功\n¥66.00\n收款方：全家便利店\n2026-11-18 12:01:09", "unionpay", {"cents": 6600, "direction": "expense", "merchant": "全家便利店", "source": "unionpay", "category": "餐饮"}),
    ("微信收款", "微信支付\n收款成功\n¥100.00\n来自 张三\n2026-11-18 09:00:00", "wechat", {"cents": 10000, "direction": "income", "merchant": "张三", "source": "wechat"}),
    ("美团订单", "美团\n订单金额 ¥45.80\n商家名称：肯德基(望京店)\n2026年11月17日 19:30", "meituan", {"cents": 4580, "direction": "expense", "merchant": "肯德基(望京店)", "source": "meituan", "category": "餐饮"}),
    ("京东白条", "京东\n白条支付\n实付款 ¥199.00\n收款方 京东商城\n2026-11-16 08:15", "jd", {"cents": 19900, "direction": "expense", "merchant": "京东商城", "source": "jd", "category": "购物"}),
    ("带标签无符号", "支付金额 128.00\n地铁出行\n2026-11-15 07:40", None, {"cents": 12800, "direction": "expense", "merchant": "地铁出行", "source": "other", "category": "交通"}),
    ("千分位金额", "招商银行\n消费金额：人民币 1,280.50 元\n商户名称 优衣库\n2026-11-14 20:11", None, {"cents": 128050, "direction": "expense", "merchant": "优衣库", "category": "购物"}),
    ("全角数字", "微信支付\n￥１２８．００\n收款方 瑞幸咖啡\n今天 08:30", None, {"cents": 12800, "direction": "expense", "merchant": "瑞幸咖啡", "source": "wechat"}),
    ("没有金额", "轻点背面\n已开启双击截屏\n无有效账单", None, {"cents": None}),
    ("纯噪声", "2026-11-18 10:22:31\n订单号 2026111822001234567890\n尾号1234", None, {"cents": None}),
]


def main():
    failures = 0
    for name, text, hint, expect in CASES:
        got = parse(text, hint)
        problems = []
        for key, want in expect.items():
            have = got[key]
            if key == "confidence":
                ok = abs(have - want) < 1e-9
            else:
                ok = have == want
            if not ok:
                problems.append("%s 期望 %r 实际 %r" % (key, want, have))
        flag = "PASS" if not problems else "FAIL"
        if problems:
            failures += 1
        print("[%s] %s" % (flag, name))
        print("       金额=%-8s 方向=%-7s 商户=%-18s 分类=%-4s 来源=%-8s 时间=%s 把握度=%s"
              % (got["amount"] or "-", got["direction"], got["merchant"] or "-",
                 got["category"], got["source"], got["date"], got["confidence"]))
        for problem in problems:
            print("       ! " + problem)

    print()
    if failures:
        print("有 %d 个用例不符合预期" % failures)
        return 1
    print("全部 %d 个用例通过" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
