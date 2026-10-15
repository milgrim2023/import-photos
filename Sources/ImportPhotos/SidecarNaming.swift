import Foundation

/// Sidecar conventions. Both exist in the wild:
///  - `IMG_0001.xmp`      (named after the stem)
///  - `R0001173.DNG.xmp`  (named after the full file name, e.g. Ricoh GR, Lightroom)
enum SidecarNaming {
    /// Per-photo companion files written by common tools (lower-case; matching ignores case).
    /// Deliberately excluded because they are generic or playable files that must stay importable:
    /// `xml`, `json`, `txt`, and proxy videos such as GoPro `lrv`.
    static let extensions: Set<String> = [
        "xmp",                    // Adobe (Lightroom/ACR/Bridge), darktable, Photo Mechanic, Capture One, many more
        "rrdata",                 // JSON rating/tag/adjustment files written by some RAW tools
        "pp3", "pp2", "arp",      // RawTherapee (pp3, legacy pp2), ART
        "dop",                    // DxO PhotoLab
        "cos",                    // Capture One settings
        "vrd", "dr4",             // Canon Digital Photo Professional recipes
        "thm",                    // Canon / GoPro video thumbnails
        "aae",                    // Apple Photos edit instructions
        "on1",                    // ON1 Photo RAW
        "ufraw",                  // UFRaw
        "exv", "mie",             // Exiv2, ExifTool sidecars
    ]

    static func isSidecar(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    /// What a sidecar of `media` is named after (full path, sidecar extension removed).
    static func keys(forMedia media: URL) -> [String] { [media.path, media.deletingPathExtension().path] }

    static func key(forSidecar sidecar: URL) -> String { sidecar.deletingPathExtension().path }

    /// Where `sidecar` (which sat beside `source`) goes beside the imported `destinationMedia`.
    static func destination(of sidecar: URL, source: URL, destinationMedia: URL) -> URL {
        let fullNameStyle = sidecar.deletingPathExtension().lastPathComponent == source.lastPathComponent
        return (fullNameStyle ? destinationMedia : destinationMedia.deletingPathExtension())
            .appendingPathExtension(sidecar.pathExtension)
    }
}
