import CoreGraphics
import ImageIO
import UIKit

/// Pages from PDFs and images, rasterised to the print width on demand (and cached).
final class DocumentSource: @unchecked Sendable {
    enum Page {
        case pdf(CGPDFPage)
        case image(CGImage)
    }

    static let maxPages = 60

    let pages: [Page]
    private let documents: [CGPDFDocument]
    private var cache: [String: GrayImage] = [:]
    private let lock = NSLock()

    init(urls: [URL]) {
        var pages: [Page] = []
        var documents: [CGPDFDocument] = []
        for url in urls {
            if url.pathExtension.lowercased() == "pdf", let document = CGPDFDocument(url as CFURL) {
                documents.append(document)
                for index in 0..<document.numberOfPages {
                    if let page = document.page(at: index + 1) { pages.append(.pdf(page)) }
                }
            } else if let image = UIImage(contentsOfFile: url.path),
                      let upright = ImageStore.uprightCGImage(image, maxDimension: 3000) {
                pages.append(.image(upright))
            }
        }
        self.pages = Array(pages.prefix(Self.maxPages))
        self.documents = documents
    }

    init(pdfData: Data) {
        var pages: [Page] = []
        var documents: [CGPDFDocument] = []
        if let provider = CGDataProvider(data: pdfData as CFData), let document = CGPDFDocument(provider) {
            documents.append(document)
            for index in 0..<document.numberOfPages {
                if let page = document.page(at: index + 1) { pages.append(.pdf(page)) }
            }
        }
        self.pages = Array(pages.prefix(Self.maxPages))
        self.documents = documents
    }

    var truncated: Bool { pages.count >= Self.maxPages }

    /// Page `index` as grayscale at the print width.
    func gray(page index: Int, rotateLandscape: Bool, trimMargins: Bool, width: Int = PrinterCatalog.printWidth) -> GrayImage? {
        let key = "\(index)-\(rotateLandscape)-\(trimMargins)-\(width)"
        lock.lock()
        if let cached = cache[key] { lock.unlock(); return cached }
        lock.unlock()
        guard pages.indices.contains(index) else { return nil }
        let result: GrayImage?
        switch pages[index] {
        case .pdf(let page): result = Self.render(pdf: page, width: width, rotateLandscape: rotateLandscape, trim: trimMargins)
        case .image(let image): result = Self.render(image: image, width: width, rotateLandscape: rotateLandscape, trim: trimMargins)
        }
        if let result {
            lock.lock()
            cache[key] = result
            lock.unlock()
        }
        return result
    }

    // MARK: PDF

    private static func displaySize(_ page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        let rotation = ((page.rotationAngle % 360) + 360) % 360
        return rotation == 90 || rotation == 270 ? CGSize(width: box.height, height: box.width) : box.size
    }

    private static func render(pdf page: CGPDFPage, width: Int, rotateLandscape: Bool, trim: Bool) -> GrayImage? {
        let size = displaySize(page)
        guard size.width > 0, size.height > 0 else { return nil }
        var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        if trim {
            let probeScale = 300 / size.width
            if let probe = draw(page, size: size, scale: probeScale, crop: crop),
               let bounds = probe.contentBounds(threshold: 0.92) {
                crop = normalized(bounds, in: CGSize(width: probe.width, height: probe.height), padding: 6)
            }
        }
        let cropSize = CGSize(width: size.width * crop.width, height: size.height * crop.height)
        // Orientation follows the page itself, so trimmed content from portrait pages stays upright.
        let rotate = rotateLandscape && size.width > size.height * 1.1
        let scale = CGFloat(width) / (rotate ? cropSize.height : cropSize.width)
        guard let gray = draw(page, size: size, scale: scale, crop: crop) else { return nil }
        return rotate ? gray.rotated(quarterTurns: 1) : gray
    }

    /// Draws the normalised `crop` region of the page at `scale` into a grayscale buffer.
    private static func draw(_ page: CGPDFPage, size: CGSize, scale: CGFloat, crop: CGRect) -> GrayImage? {
        let full = CGSize(width: size.width * scale, height: size.height * scale)
        let region = CGRect(x: crop.minX * full.width, y: crop.minY * full.height,
                            width: crop.width * full.width, height: crop.height * full.height)
        let w = max(1, Int(region.width.rounded())), h = max(1, min(40_000, Int(region.height.rounded())))
        var bytes = [UInt8](repeating: 255, count: w * h)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.interpolationQuality = .high
            // Region origin is top-left; Core Graphics is bottom-left.
            context.translateBy(x: -region.minX, y: -(full.height - region.maxY))
            context.scaleBy(x: scale, y: scale)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            return true
        }
        guard drawn else { return nil }
        return GrayImage(width: w, height: h, data: bytes.map { Float($0) / 255 })
    }

    // MARK: Images

    private static func render(image: CGImage, width: Int, rotateLandscape: Bool, trim: Bool) -> GrayImage? {
        var source = image
        let isLandscape = image.width > Int(Double(image.height) * 1.1)
        if trim {
            let probe = GrayImage(cgImage: image, fittingWidth: 300)
            if let bounds = probe.contentBounds(threshold: 0.92) {
                let crop = normalized(bounds, in: CGSize(width: probe.width, height: probe.height), padding: 6)
                source = image.cropped(normalized: crop) ?? image
            }
        }
        if rotateLandscape, isLandscape {
            source = source.oriented(quarterTurns: 1, mirrored: false) ?? source
        }
        return GrayImage(cgImage: source, fittingWidth: width, maxHeight: 40_000)
    }

    private static func normalized(_ bounds: CGRect, in size: CGSize, padding: CGFloat) -> CGRect {
        let padded = bounds.insetBy(dx: -padding, dy: -padding)
            .intersection(CGRect(origin: .zero, size: size))
        return CGRect(x: padded.minX / size.width, y: padded.minY / size.height,
                      width: padded.width / size.width, height: padded.height / size.height)
    }
}

struct DocumentOptions: Hashable {
    var pages: [Int]
    var adjustments = ImageAdjustments(style: .threshold, sharpness: 0, threshold: 0.6, autoLevels: false)
    var rotateLandscape = true
    var trimMargins = true
    var separatePages = true
    /// Maximum printed length in dots (0 = no limit).
    var maxLength = 0
}

enum DocumentComposer {
    static func compose(_ source: DocumentSource, options: DocumentOptions) -> MonoBitmap {
        let width = PrinterCatalog.printWidth
        var parts: [MonoBitmap] = []
        for (position, index) in options.pages.sorted().enumerated() {
            guard let gray = source.gray(page: index, rotateLandscape: options.rotateLandscape, trimMargins: options.trimMargins) else { continue }
            if position > 0, options.separatePages {
                parts.append(BlockRenderer.divider(DividerBlock(style: .scissors, thickness: 2), width: width))
            }
            parts.append(ImagePipeline.mono(from: gray, adjustments: options.adjustments))
        }
        var result = MonoBitmap.stacked(parts, width: width, spacing: options.separatePages ? 16 : 4)
        if options.maxLength > 0, result.height > options.maxLength {
            result = result.cropped(x: 0, y: 0, width: width, height: options.maxLength)
        }
        return result
    }
}
