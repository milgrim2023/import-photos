#if DEBUG
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ImportPhotos

/// Debug-only launch modes for the XCUITest suite (never compiled into Release builds).
///
/// - `-UITesting`               use a fake open panel, fixture photos and throwaway settings
/// - `-UITestPickFiles`         the fake panel returns individual photos instead of one folder
/// - `-UITestCannotListFolders` pretend the sandbox can't list folders (shows the sidecar warning)
/// - `-UITestSlowImport`        each file takes ~1 s to copy, so a test can press Cancel mid-import
///
/// Fixtures are created inside the app's own container, because the sandboxed app cannot read the
/// UI-test runner's temp folder.
enum UITestMode {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    static var isEnabled: Bool { args.contains("-UITesting") }

    static var slowImport: Bool { args.contains("-UITestSlowImport") }

    struct Environment {
        let selection: FileSelectionService
        let defaults: UserDefaults
        let canListFolder: (URL) -> Bool
    }

    static func makeEnvironment() -> Environment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoImportUITest-\(UUID().uuidString)")
        let card = root.appendingPathComponent("card"), library = root.appendingPathComponent("library")
        try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)

        // Named so that alphabetical order differs from date order (oldest -> newest: BRAVO, CHARLIE, ALPHA).
        let base = Calendar.current.date(from: DateComponents(year: 2024, month: 6, day: 10, hour: 12))!
        write("bravo", at: card.appendingPathComponent("BRAVO.ARW"), modified: base)
        write("<xmp/>", at: card.appendingPathComponent("BRAVO.ARW.xmp"), modified: base.addingTimeInterval(900))
        writeJPEG(at: card.appendingPathComponent("CHARLIE.JPG"), modified: base.addingTimeInterval(60))
        write("<xmp/>", at: card.appendingPathComponent("CHARLIE.xmp"), modified: base.addingTimeInterval(900))
        writeJPEG(at: card.appendingPathComponent("ALPHA.JPG"), modified: base.addingTimeInterval(120))
        writeJPEG(at: card.appendingPathComponent("Subfolder/DELTA.JPG"), modified: base.addingTimeInterval(30))

        let sources: [URL] = args.contains("-UITestPickFiles")
            ? [card.appendingPathComponent("ALPHA.JPG"), card.appendingPathComponent("BRAVO.ARW")]
            : [card]
        let suite = "PhotoImportUITest-\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return Environment(
            selection: UITestFileSelection(sources: sources, destination: library),
            defaults: UserDefaults(suiteName: suite)!,
            canListFolder: args.contains("-UITestCannotListFolders") ? { _ in false } : { _ in true })
    }

    private static func write(_ text: String, at url: URL, modified: Date) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
        try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    private static func writeJPEG(at url: URL, modified: Date) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil), let image = ctx.makeImage() {
            CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
        }
        try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }
}

/// Wraps the real transferrer with a delay so an import lasts long enough to cancel.
final class SlowTransferrer: MediaTransferrer, @unchecked Sendable {
    private let inner = RealMediaTransferrer()
    func transfer(source: URL, to destination: URL, sidecars: [URL]) async throws -> [URL] {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return try await inner.transfer(source: source, to: destination, sidecars: sidecars)
    }
}

/// Stands in for the system open panel: "choosing" returns the fixtures, nothing is persisted.
final class UITestFileSelection: FileSelectionService, @unchecked Sendable {
    private let sources: [URL], destination: URL
    init(sources: [URL], destination: URL) { self.sources = sources; self.destination = destination }

    func selectSources() async throws -> [URL] { sources }
    func selectDestination() async throws -> URL { destination }
    func persistSelection(sources: [URL]?, destination: URL?) async throws {}
    func loadLastSelection() async -> (sources: [URL], destination: URL?) { ([], nil) }
}
#endif
