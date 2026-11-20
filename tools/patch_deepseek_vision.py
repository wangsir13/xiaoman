import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

parser = pathlib.Path("Xiaoman/Import/AIParser.swift")
text = parser.read_text(encoding="utf-8")

# 1) DeepSeek 也走读图；不再按服务商写死「不支持」
old_support = '''        /// 能不能直接把截图丢给它读（多模态）。
        /// DeepSeek 官方接口目前只有文本模型，所以走 OCR + 文本复核那条路。
        var supportsVision: Bool {
            switch self {
            case .deepseek: return false
            case .openai, .anthropic, .doubao, .custom: return true
            }
        }
'''
new_support = '''        /// 是否尝试把截图直接交给它读（多模态）。
        /// 现在各家都陆续支持视觉，所以一律先试读图；接口明确拒绝图片时会自动退回 OCR。
        var supportsVision: Bool { true }
'''
if old_support not in text:
    print("miss: supportsVision")
    sys.exit(1)
text = text.replace(old_support, new_support, 1)

# 2) 各家的说明文案
old_hint = '''        var visionHint: String {
            switch self {
            case .deepseek: return "DeepSeek 仅提供文本模型，将先执行 OCR 再进行文字复核；如需直接识图，请改用 OpenAI / Claude / 豆包。"
            case .openai: return "gpt-4o-mini / gpt-4o 都能直接读图"
            case .anthropic: return "claude-sonnet-4-5 / claude-3-5-sonnet 都支持读图"
            case .doubao: return "需要填方舟里的视觉接入点（如 doubao-vision 系列的 ep-xxxx）"
            case .custom: return "接口需要兼容 OpenAI 的 image_url 格式，模型本身也要支持读图"
            }
        }
'''
new_hint = '''        var visionHint: String {
            switch self {
            case .deepseek: return "deepseek-chat / deepseek-vl 系列可直接读图；若你的 Key 只能调文本模型，接口会拒绝图片并自动改用 OCR"
            case .openai: return "gpt-4o-mini / gpt-4o 都能直接读图"
            case .anthropic: return "claude-sonnet-4-5 / claude-3-5-sonnet 都支持读图"
            case .doubao: return "需要填方舟里的视觉接入点（如 doubao-vision 系列的 ep-xxxx）"
            case .custom: return "接口需要兼容 OpenAI 的 image_url 格式，模型本身也要支持读图"
            }
        }
'''
if old_hint in text:
    text = text.replace(old_hint, new_hint, 1)
else:
    # 上一版文案可能已被改写，按单行替换兜底
    text = text.replace(
        'case .deepseek: return "DeepSeek 仅提供文本模型，将先执行 OCR 再进行文字复核；如需直接识图，请改用 OpenAI / Claude / 豆包。"',
        'case .deepseek: return "deepseek-chat / deepseek-vl 系列可直接读图；若你的 Key 只能调文本模型，接口会拒绝图片并自动改用 OCR"',
        1,
    )

# 3) 去掉「服务商不支持读图」的前置拦截，改成失败后自动回退
old_guard = "        guard config.provider.supportsVision else { throw AIError.visionUnsupported }\n"
if old_guard not in text:
    print("miss: guard")
    sys.exit(1)
text = text.replace(old_guard, "", 1)

parser.write_text(text, encoding="utf-8")
print("AIParser patched")
