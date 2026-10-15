import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ImportPhotos

/// Temp-dir sandbox for engine tests: `source/` and `destination/` under a unique root.
struct Fixture {
    let root: URL
    let source: URL
    let destination: URL

    init() throws {
        // realpath: enumerators return /private/var/... for temp dirs, so match that form.
        let tmp = FileManager.default.temporaryDirectory.path
        let real = realpath(tmp, nil).map { String(cString: $0) } ?? tmp
        root = URL(fileURLWithPath: real).appendingPathComponent(UUID().uuidString)
        source = root.appendingPathComponent("source")
        destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func write(_ content: String, to url: URL, modified: Date) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    func makeEngine() -> RealIngestionEngine {
        RealIngestionEngine(
            metadataProvider: RealMediaMetadataProvider(),
            pathTemplater: RealPathTemplater(),
            collisionJudge: RealCollisionJudge(),
            mediaTransferrer: RealMediaTransferrer()
        )
    }
}

/// Whole-second reference date so filesystem round-trips compare equal.
let t0 = Date(timeIntervalSince1970: 1_700_000_000)

/// Thread-safe collector for `@Sendable` progress callbacks.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ImportProgress] = []
    func record(_ p: ImportProgress) { lock.lock(); items.append(p); lock.unlock() }
    var events: [ImportProgress] { lock.lock(); defer { lock.unlock() }; return items }
}


/// A real 2x2 JPEG whose EXIF DateTimeOriginal is `exifDate` ("yyyy:MM:dd HH:mm:ss", local time).
func writeJPEGWithExif(at url: URL, exifDate: String, file: StaticString = #filePath, line: UInt = #line) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    let props: [CFString: Any] = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: exifDate]]
    CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(dest), file: file, line: line)
}
