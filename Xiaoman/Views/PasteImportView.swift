import SwiftUI
import UIKit

struct PasteImportView: View {

    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("把账单页面的文字粘进来。没有快捷指令时，也可以用它手动补一条。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 220)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.25))
                    )

                Button {
                    if let content = UIPasteboard.general.string {
                        text = content
                    }
                } label: {
                    Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                        .font(.footnote)
                }
            }
            .padding(16)
            .navigationTitle("粘贴识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("解析") {
                        let content = text
                        dismiss()
                        Task {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            await store.enqueueSmart(text: content)
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
