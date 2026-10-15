import Foundation
import ImageIO
import AVFoundation

public class RealMediaMetadataProvider: MediaMetadataProvider {
    public init() {}
    
    public func fetchMetadata(for url: URL) async throws -> MediaMetadata {
        let name = url.lastPathComponent
        
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        
        let size = Int64(resourceValues.fileSize ?? 0)
        let baseTimestamp = resourceValues.contentModificationDate ?? Date()
        
        var finalTimestamp = baseTimestamp
        
        if let enrichedDate = await extractEnrichedTimestamp(from: url) {
            finalTimestamp = enrichedDate
        }

        return MediaMetadata(name: name, size: size, timestamp: finalTimestamp)
    }
    
    private func extractEnrichedTimestamp(from url: URL) async -> Date? {
        if let exifDate = getExifDate(from: url) {
            return exifDate
        }
        
        if let videoDate = await getVideoDate(from: url) {
            return videoDate
        }
        
        return nil
    }
    
    private func getExifDate(from url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        
        if let exif = properties?[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let dateTimeString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            return formatter.date(from: dateTimeString)
        }
        return nil
    }
    
    private func getVideoDate(from url: URL) async -> Date? {
        let asset = AVURLAsset(url: url)
        do {
            guard let item = try await asset.load(.creationDate) else { return nil }
            return try await item.load(.dateValue)
        } catch {
            return nil
        }
    }
}
