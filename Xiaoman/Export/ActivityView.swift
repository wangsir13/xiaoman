import SwiftUI
import UIKit

/// 用系统分享面板导出文件
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 给 .sheet(item:) 用的可识别包装
struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}
