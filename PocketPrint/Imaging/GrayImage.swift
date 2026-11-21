import CoreGraphics
import Foundation

/// A grayscale image with luminance values in 0...1 (0 = black, 1 = white).
struct GrayImage: Sendable {
    let width: Int
    let height: Int
    var data: [Float]

    init(width: Int, height: Int, fill: Float = 1) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.data = [Float](repeating: fill, count: self.width * self.height)
    }

    init(width: Int, height: Int, data: [Float]) {
        precondition(data.count == width * height, "pixel count mismatch")
        self.width = width
        self.height = height
        self.data = data
    }

    /// Resamples `cgImage` into a grayscale buffer of the given size, compositing over white.
    init(cgImage: CGImage, width: Int, height: Int, interpolation: CGInterpolationQuality = .high) {
        let w = max(1, width), h = max(1, height)
        var source = cgImage
        // Large reductions alias with a single pass; step down by halves first.
        if interpolation != .none {
            while source.width > w * 3 || source.height > h * 3 {
                let stepW = max(w, source.width / 2), stepH = max(h, source.height / 2)
                guard let reduced = GrayImage.resampledRGB(source, width: stepW, height: stepH) else { break }
                source = reduced
            }
        }
        var bytes = [UInt8](repeating: 255, count: w * h)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = interpolation
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        self.width = w
        self.height = h
        self.data = bytes.map { Float($0) * (1 / 255) }
    }

    /// Resamples to `width`, keeping the aspect ratio.
    init(cgImage: CGImage, fittingWidth width: Int, maxHeight: Int = 20_000) {
        let aspect = Double(cgImage.height) / Double(max(1, cgImage.width))
        let height = min(maxHeight, max(1, Int((Double(width) * aspect).rounded())))
        self.init(cgImage: cgImage, width: width, height: height)
    }

    private static func resampledRGB(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: Adjustments

    /// brightness and contrast in -1...1, gamma > 0 (values above 1 lighten mid-tones).
    func adjusted(brightness: Double, contrast: Double, gamma: Double = 1) -> GrayImage {
        if brightness == 0, contrast == 0, gamma == 1 { return self }
        let b = Float(brightness) * 0.5
        let c = Float(contrast >= 0 ? 1 + contrast * 2 : 1 + contrast)
        let g = Float(1 / max(0.05, gamma))
        var out = self
        for i in 0..<out.data.count {
            var v = (out.data[i] - 0.5) * c + 0.5 + b
            v = min(1, max(0, v))
            if g != 1 { v = powf(v, g) }
            out.data[i] = v
        }
        return out
    }

    /// Stretches the histogram so that the darkest/lightest `clip` fraction maps to black/white.
    func autoLevels(clip: Double = 0.005) -> GrayImage {
        guard !data.isEmpty else { return self }
        var histogram = [Int](repeating: 0, count: 256)
        for v in data { histogram[Int(min(255, max(0, v * 255)))] += 1 }
        let limit = Int(Double(data.count) * clip)
        var low = 0, high = 255, accumulated = 0
        for (index, count) in histogram.enumerated() {
            accumulated += count
            if accumulated > limit { low = index; break }
        }
        accumulated = 0
        for index in stride(from: 255, through: 0, by: -1) {
            accumulated += histogram[index]
            if accumulated > limit { high = index; break }
        }
        guard high - low > 8 else { return self }
        let lo = Float(low) / 255, range = Float(high - low) / 255
        var out = self
        for i in 0..<out.data.count {
            out.data[i] = min(1, max(0, (out.data[i] - lo) / range))
        }
        return out
    }

    /// Unsharp mask using a 3x3 box blur; `amount` 0...2.
    func sharpened(amount: Double) -> GrayImage {
        guard amount > 0, width > 2, height > 2 else { return self }
        let blurred = boxBlurred()
        let a = Float(amount)
        var out = self
        for i in 0..<out.data.count {
            out.data[i] = min(1, max(0, data[i] + a * (data[i] - blurred.data[i])))
        }
        return out
    }

    func boxBlurred(radius: Int = 1) -> GrayImage {
        guard radius > 0 else { return self }
        var horizontal = self
        for y in 0..<height {
            let base = y * width
            for x in 0..<width {
                var sum: Float = 0
                var count: Float = 0
                for dx in -radius...radius {
                    let sx = x + dx
                    if sx >= 0, sx < width { sum += data[base + sx]; count += 1 }
                }
                horizontal.data[base + x] = sum / count
            }
        }
        var out = horizontal
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                var count: Float = 0
                for dy in -radius...radius {
                    let sy = y + dy
                    if sy >= 0, sy < height { sum += horizontal.data[sy * width + x]; count += 1 }
                }
                out.data[y * width + x] = sum / count
            }
        }
        return out
    }

    func inverted() -> GrayImage {
        var out = self
        for i in 0..<out.data.count { out.data[i] = 1 - out.data[i] }
        return out
    }

    func rotated(quarterTurns: Int) -> GrayImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return self }
        if turns == 2 { return GrayImage(width: width, height: height, data: data.reversed()) }
        var out = GrayImage(width: height, height: width)
        for y in 0..<height {
            for x in 0..<width {
                let value = data[y * width + x]
                if turns == 1 {
                    out.data[x * out.width + (height - 1 - y)] = value
                } else {
                    out.data[(width - 1 - x) * out.width + y] = value
                }
            }
        }
        return out
    }

    /// Bounding box of pixels darker than `threshold`, used to trim page margins.
    func contentBounds(threshold: Float = 0.85) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let base = y * width
            for x in 0..<width where data[base + x] < threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
