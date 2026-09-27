import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image handling for sync, shared by macOS and iOS (ImageIO only, no AppKit/UIKit).
enum SyncImages {
    /// Images larger than this (after conversion) stay on the device they were copied on.
    static let maxBytes = 10 * 1024 * 1024

    private static let keptFormats: Set<String> = [
        UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier,
    ]

    private static func source(_ data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, nil)
    }

    /// Cheap check used when deciding whether to queue an upload. TIFF from the Mac
    /// clipboard is often far larger than the PNG it becomes, so it is let through here
    /// and measured again when the record is built.
    static func mightFit(_ data: Data) -> Bool {
        if data.count <= maxBytes { return true }
        guard let source = source(data), let type = CGImageSourceGetType(source) as String? else { return false }
        return !keptFormats.contains(type)
    }

    /// PNG, JPEG, and HEIC are uploaded as-is; anything else (usually TIFF) as PNG.
    /// Returns nil when the result is still over the limit.
    static func uploadData(for data: Data) -> (data: Data, fileExtension: String)? {
        guard let source = source(data), let type = CGImageSourceGetType(source) as String? else { return nil }
        if keptFormats.contains(type) {
            guard data.count <= maxBytes else { return nil }
            let ext = UTType(type)?.preferredFilenameExtension ?? "img"
            return (data, ext)
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        guard CGImageDestinationFinalize(destination), output.length <= maxBytes else { return nil }
        return (output as Data, "png")
    }

    /// Small PNG preview for cards, made on the receiving device.
    static func thumbnail(for data: Data, maxPixelSize: Int = 480) -> Data? {
        guard let source = source(data) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    // MARK: - Asset files

    /// CKAsset uploads from a file. Files live here until the record is sent.
    static var stagingDirectory: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipbaraSyncAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func stage(_ data: Data, recordName: String, fileExtension: String) -> URL? {
        let url = stagingDirectory.appendingPathComponent("\(recordName).\(fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func removeStaged(recordName: String) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: stagingDirectory.path) else { return }
        for name in names where name.hasPrefix(recordName + ".") {
            try? fm.removeItem(at: stagingDirectory.appendingPathComponent(name))
        }
    }

    static func clearStaging() {
        try? FileManager.default.removeItem(at: stagingDirectory)
    }
}
