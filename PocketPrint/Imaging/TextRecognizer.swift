import UIKit
import Vision

/// On-device text recognition (Apple Vision); nothing leaves the phone.
enum TextRecognizer {
    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = ImageStore.uprightCGImage(image, maxDimension: 3000) else { return "" }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}
