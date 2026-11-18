import Foundation
import UIKit
import Vision

enum OCRError: Error {
    case invalidImage
    case recognizeFailed

    var message: String {
        switch self {
        case .invalidImage: return "图片无法解析"
        case .recognizeFailed: return "文字识别失败"
        }
    }
}

/// 本地 Vision OCR（中文优先）。不联网、不上传。
enum ImageOCR {

    private final class ResumeOnce {
        private let lock = NSLock()
        private var finished = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }
    }

    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }

        return try await withCheckedThrowingContinuation { continuation in
            let guarder = ResumeOnce()

            let request = VNRecognizeTextRequest { request, error in
                guard guarder.claim() else { return }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    guard guarder.claim() else { return }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
