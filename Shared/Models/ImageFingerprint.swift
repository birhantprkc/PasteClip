import CoreGraphics
import Foundation
import ImageIO

/// Recognizes the same picture across encodings.
///
/// One copy reaches each device as different bytes: the Mac keeps what the pasteboard
/// gives (often TIFF), sync uploads PNG, and Universal Clipboard hands the iPhone PNG or
/// JPEG. Their hashes never match, so images are also compared by pixel size and a
/// 32x32 grayscale sample of the decoded picture.
///
/// The match is strict on purpose: merging two different screenshots would drop a clip,
/// while missing a match only leaves a duplicate card.
struct ImageFingerprint: Equatable, Sendable {
    static let side = 32
    /// Largest difference any one sample may have. Resampling and high-quality JPEG
    /// stay well under it; a changed word or icon in a screenshot goes over it.
    static let maxSampleDifference = 10
    /// Largest average difference per sample.
    static let maxMeanDifference = 2

    let width: Int
    let height: Int
    let samples: [UInt8]

    init?(data: Data) {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        // EXIF orientations 5 to 8 rotate by 90 degrees; the thumbnail below is upright.
        if let orientation = properties[kCGImagePropertyOrientation] as? UInt32, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let side = Self.side
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            // Transparent areas count as white on every device.
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .high
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.samples = pixels
    }

    func matches(_ other: ImageFingerprint) -> Bool {
        guard width == other.width, height == other.height, samples.count == other.samples.count else { return false }
        var total = 0
        for (a, b) in zip(samples, other.samples) {
            let difference = abs(Int(a) - Int(b))
            if difference > Self.maxSampleDifference { return false }
            total += difference
        }
        return total <= samples.count * Self.maxMeanDifference
    }
}
