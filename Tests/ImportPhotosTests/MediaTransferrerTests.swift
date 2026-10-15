import XCTest
@testable import ImportPhotos

final class MediaTransferrerTests: XCTestCase {
    
    func testTransfer() async throws {
        let transferrer: MediaTransferrer = RealMediaTransferrer()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let sourceFile = tempDir.appendingPathComponent("test.jpg")
        let data = "test content".data(using: .utf8)!
        try data.write(to: sourceFile)
        
        let destinationDir = tempDir.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        
        let destinationURL = destinationDir.appendingPathComponent("test.jpg")
        
        try await transferrer.transfer(source: sourceFile, to: destinationURL, sidecars: [])
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        let destinationData = try Data(contentsOf: destinationURL)
        XCTAssertEqual(destinationData, data)
    }
}
