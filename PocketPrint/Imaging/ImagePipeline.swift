import Foundation

enum ImagePipeline {
    /// Tone adjustments followed by dithering. Dithered styles get a slight mid-tone lift
    /// because thermal dots spread a little and prints come out darker than the screen preview.
    static func mono(from gray: GrayImage, adjustments a: ImageAdjustments) -> MonoBitmap {
        var image = gray
        if a.autoLevels, a.style != .document {
            image = image.autoLevels()
        }
        let dithered = a.style != .threshold && a.style != .document
        image = image.adjusted(brightness: a.brightness, contrast: a.contrast, gamma: dithered ? 1.1 : 1)
        if a.sharpness > 0, a.style != .threshold {
            image = image.sharpened(amount: a.sharpness * 1.5)
        }
        if a.invert {
            image = image.inverted()
        }
        return Dither.apply(image, style: a.style, threshold: Float(a.threshold))
    }
}
