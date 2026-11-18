import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 原生文件选择器。
///
/// 用 `UIDocumentPickerViewController(asCopy: true)` 而不是 SwiftUI 的 `.fileImporter`：
/// - `asCopy: true` 会把选中的文件直接拷进 App 沙盒，不再需要 security-scoped 授权，也不会出现
///   「选了文件但读不到」的情况；
/// - 单选模式由我们自己设，避免系统把选择器带进「多选编辑」状态（全选 / 取消全选、点文件没反应）。
struct DocumentPicker: UIViewControllerRepresentable {

    var contentTypes: [UTType] = [.item]
    var allowsMultipleSelection: Bool = false
    /// 取消时回调空数组。
    var onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick([])
        }
    }
}
