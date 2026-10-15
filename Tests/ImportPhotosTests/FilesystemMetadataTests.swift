import XCTest
@testable import ImportPhotos

final class FilesystemMetadataTests: XCTestCase {
    
    func testMetadataExtractionFromFilesystem() async throws {
        let provider: MediaMetadataProvider = RealMediaMetadataProvider()
        let tempDirectory = FileManager.default.temporaryDirectory
        let testURL = tempDirectory.appendingPathComponent("test_image.jpg")
        let dummyData = "fake-image-content".data(using: .utf8)!
        try dummyData.write(to: testURL)
        
        // Ensure file is cleaned up after test
        defer { try? FileManager.default.removeItem(at: testURL) }

        let metadata = try await provider.fetchMetadata(for: testURL)
        
        XCTAssertEqual(metadata.name, "test_image.jpg")
        XCTAssertEqual(metadata.size, Int64(dummyData.count))
        
        // Verify that the timestamp is close to the creation time of the dummy file
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: testURL.path)
        let creationDate = fileAttributes[.modificationDate] as? Date ?? Date()
        
        // Allow a small margin for timing differences during the test execution
        XCTAssertTrue(abs(metadata.timestamp.timeIntervalSince(creationDate)) < 1.0, "Timestamp should match modification date for non-media files")
    }
}
