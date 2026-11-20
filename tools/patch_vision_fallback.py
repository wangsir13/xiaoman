import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

store = pathlib.Path("Xiaoman/Store/LedgerStore.swift")
text = store.read_text(encoding="utf-8")

old = '''            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                flash("AI 识图失败，改用本地识别（\\(reason)）")
            }
'''
new = '''            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let lower = reason.lowercased()
                let refused = lower.contains("image")
                    || lower.contains("vision")
                    || lower.contains("modal")
                    || reason.contains("图片")
                    || reason.contains("不支持")
                // 接口不收图片（比如只开了文本模型）和网络/额度问题分开提示，用户才知道该改哪儿
                flash(refused ? "该接口不接受图片，已改用 OCR 识别" : "识图失败，已改用本地识别")
            }
'''
if old not in text:
    print("miss: catch block")
    sys.exit(1)
text = text.replace(old, new, 1)
store.write_text(text, encoding="utf-8")

readme = pathlib.Path("README.md")
doc = readme.read_text(encoding="utf-8")
pairs = [
    (
        "| 大模型直接读图（可选） | 开了之后，截图**整张**发给所选的多模态模型（GPT / Claude / 豆包 / 自定义），由它直接看图取金额、商户、类别；DeepSeek 只有文本模型，走 OCR + 文字复核。不填 Key 就完全离线 |",
        "| 大模型直接读图（可选） | 开了之后，截图**整张**发给所选的多模态模型（DeepSeek / GPT / Claude / 豆包 / 自定义），由它直接看图取金额、商户、类别；接口不接受图片时自动退回 OCR + 文字复核。不填 Key 就完全离线 |",
    ),
    (
        "DeepSeek 官方接口只有文本模型，选它时会自动退回「本地 OCR → 文字复核」。入口在「设置 → AI 复核」。",
        "各家都会先尝试读图；若所选模型是纯文本的（接口会拒绝图片），自动退回「本地 OCR → 文字复核」，不会让识别失败。入口在「设置 → AI 复核」。",
    ),
]
for old_text, new_text in pairs:
    if old_text in doc:
        doc = doc.replace(old_text, new_text, 1)
    else:
        print("miss readme:", old_text[:20])
readme.write_text(doc, encoding="utf-8")
print("store + readme patched")
