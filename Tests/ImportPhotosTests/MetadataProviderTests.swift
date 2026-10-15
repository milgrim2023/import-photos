import XCTest
@testable import ImportPhotos

final class MetadataProviderTests: XCTestCase {

    func testExifDateTimeOriginalWinsOverFileModificationDate() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let url = fx.source.appendingPathComponent("exif.jpg")
        try writeJPEGWithExif(at: url, exifDate: "2020:02:03 04:05:06")
        try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: url.path)

        let metadata = try await RealMediaMetadataProvider().fetchMetadata(for: url)

        var c = DateComponents(); c.year = 2020; c.month = 2; c.day = 3; c.hour = 4; c.minute = 5; c.second = 6
        XCTAssertEqual(metadata.timestamp, Calendar.current.date(from: c))
    }
}

import AVFoundation

final class VideoMetadataTests: XCTestCase {

    func testVideoCreationDateWinsOverFileModificationDate() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let url = fx.source.appendingPathComponent("clip.mov")
        let created = Date(timeIntervalSince1970: 1_600_000_000)
        try await writeTinyMovie(at: url, creationDate: created)
        try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: url.path)

        let metadata = try await RealMediaMetadataProvider().fetchMetadata(for: url)

        XCTAssertEqual(metadata.timestamp.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 1)
    }

    private func writeTinyMovie(at url: URL, creationDate: Date) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierCreationDate
        item.value = ISO8601DateFormatter().string(from: creationDate) as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [item]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32ARGB, nil, &buffer)
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        adaptor.append(buffer!, withPresentationTime: .zero)
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
    }
}
