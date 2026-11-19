import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

path = pathlib.Path("README.md")
text = path.read_text(encoding="utf-8")

pairs = [
    (
        "| AI 复核（可选） | 本地规则先解析，再把文字发给所选的大模型（DeepSeek / GPT / Claude / 豆包 / 自定义接口）补字段；不填 Key 就完全离线 |",
        "| 大模型直接读图（可选） | 开了之后，截图**整张**发给所选的多模态模型（GPT / Claude / 豆包 / 自定义），由它直接看图取金额、商户、类别；DeepSeek 只有文本模型，走 OCR + 文字复核。不填 Key 就完全离线 |",
    ),
    (
        "- **AI 复核（可选）**：本地规则先跑，再用所选的大模型（DeepSeek / GPT / Claude / 豆包）把原文整段看一遍，补金额/商户/分类/资产/时间。模型给的字段优先，没给的就保留本地结果。入口在「设置 → AI 复核」。",
        "- **大模型直接读图（可选）**：开了之后，截图不再先做 OCR，而是压到 1280 宽（JPEG 0.7）直接发给多模态模型，由它从像素里读出金额、商户全称、付款方式、类别。商户名这类 OCR 常错的地方，读图明显更准。DeepSeek 官方接口只有文本模型，选它时会自动退回「本地 OCR → 文字复核」。入口在「设置 → AI 复核」。",
    ),
    (
        "- 可选 AI 复核：设置里填了自己某个大模型的 Key 后，才会把**识别出来的文字**（不是图片）发到那家服务商的接口补字段；Key 存在本机，随 App 卸载一起消失。",
        "- 可选大模型读图：设置里填了自己某个多模态模型的 Key 后，才会把**截图本身**（压缩后的 JPEG）发到那家服务商的接口；选 DeepSeek 时只发 OCR 出来的文字。Key 存在本机，随 App 卸载一起消失。",
    ),
]

for old, new in pairs:
    if old not in text:
        print("missing:", old[:24])
        sys.exit(1)
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
print("readme updated")
