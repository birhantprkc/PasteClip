import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class ImageFingerprintTests: XCTestCase {
    /// A screenshot-like picture: light background, a colored bar, some dark "text" blocks.
    private func picture(width: Int = 600, height: Int = 400, extraMark: CGRect? = nil, alpha: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
        if !alpha {
            context.setFillColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.setFillColor(red: 0.23, green: 0.44, blue: 0.95, alpha: 1)
        context.fill(CGRect(x: 0, y: height - 60, width: width, height: 60))
        context.setFillColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
        for row in 0..<8 {
            context.fill(CGRect(x: 40, y: 40 + row * 36, width: 180 + (row * 53) % 300, height: 14))
        }
        if let extraMark {
            context.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
            context.fill(extraMark)
        }
        return context.makeImage()!
    }

    private func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func fingerprint(_ data: Data) throws -> ImageFingerprint {
        try XCTUnwrap(ImageFingerprint(data: data))
    }

    /// The iPhone saves PNG, the Mac keeps the pasteboard's TIFF, and sync uploads PNG.
    /// JPEG is here as a lossy worst case.
    func testSamePictureMatchesAcrossFormats() throws {
        let image = picture()
        let png = try fingerprint(encode(image, as: .png))
        XCTAssertTrue(png.matches(try fingerprint(encode(image, as: .tiff))))
        XCTAssertTrue(png.matches(try fingerprint(encode(image, as: .jpeg, quality: 0.85))))
    }

    func testTransparentPictureMatchesAcrossFormats() throws {
        let image = picture(alpha: true)
        let png = try fingerprint(encode(image, as: .png))
        XCTAssertTrue(png.matches(try fingerprint(encode(image, as: .tiff))))
    }

    func testSmallChangeDoesNotMatch() throws {
        let original = try fingerprint(encode(picture(), as: .png))
        // Roughly one changed word in a 600x400 screenshot.
        let edited = try fingerprint(encode(picture(extraMark: CGRect(x: 300, y: 200, width: 24, height: 14)), as: .png))
        XCTAssertFalse(original.matches(edited))
        // An 8x8 mark, about one character.
        let dot = try fingerprint(encode(picture(extraMark: CGRect(x: 300, y: 200, width: 8, height: 8)), as: .png))
        XCTAssertFalse(original.matches(dot))
    }

    func testDifferentSizeDoesNotMatch() throws {
        let large = try fingerprint(encode(picture(width: 600, height: 400), as: .png))
        let small = try fingerprint(encode(picture(width: 300, height: 200), as: .png))
        XCTAssertFalse(large.matches(small))
    }

    func testNotAnImage() {
        XCTAssertNil(ImageFingerprint(data: Data("hello".utf8)))
        XCTAssertNil(ImageFingerprint(data: Data()))
    }
}
