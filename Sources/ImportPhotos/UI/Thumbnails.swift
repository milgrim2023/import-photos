import SwiftUI
import AppKit
import QuickLookThumbnailing

/// System boundary: QuickLook renders thumbnails (JPEG, RAW, video…). Cached; falls back to the file icon.
@MainActor
enum Thumbnails {
    private static let cache = NSCache<NSURL, NSImage>()

    static func icon(for url: URL) -> NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    static func load(_ url: URL, side: CGFloat) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = rep.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct ThumbnailView: View {
    let url: URL
    let isDirectory: Bool
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? Thumbnails.icon(for: url))
            .resizable().scaledToFit()
            .task(id: url) {
                guard !isDirectory else { return }
                image = await Thumbnails.load(url, side: 160)
            }
    }
}
