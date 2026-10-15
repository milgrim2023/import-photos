import Foundation
import XCTest
@testable import ImportPhotos

final class PathTemplaterTests: XCTestCase {
    
    func testPathTemplater() {
        let templater = RealPathTemplater()
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2023
        components.month = 10
        components.day = 13
        let date = calendar.date(from: components)!
        
        let metadata = MediaMetadata(name: "photo.jpg", size: 1024, timestamp: date)
        let template = "{{YEAR}}/{{MONTH}}/{{NAME}}"
        
        let result = templater.calculateRelativePath(from: metadata, template: template)
        
        XCTAssertEqual(result, "2023/10/photo.jpg")
    }
}

final class PathTemplaterTokenTests: XCTestCase {
    private func path(_ template: String) -> String {
        var c = DateComponents(); c.year = 2024; c.month = 3; c.day = 7; c.hour = 9; c.minute = 5; c.second = 2
        let date = Calendar(identifier: .gregorian).date(from: c)!
        return RealPathTemplater().calculateRelativePath(
            from: MediaMetadata(name: "IMG_1.ARW", size: 1, timestamp: date), template: template)
    }

    func testEveryTokenIsSubstitutedAndSingleDigitsAreZeroPadded() {
        XCTAssertEqual(path("{{YEAR}}-{{MONTH}}-{{DAY}} {{HOUR}}.{{MINUTE}}.{{SECOND}}/{{NAME}}"), "2024-03-07 09.05.02/IMG_1.ARW")
    }
    func testRepeatedTokensAreAllReplaced() {
        XCTAssertEqual(path("{{YEAR}}/{{YEAR}}{{MONTH}}/{{NAME}}"), "2024/202403/IMG_1.ARW")
    }
    func testUnknownTokensAndPlainTextAreLeftAlone() {
        XCTAssertEqual(path("Trips/{{CAMERA}}/{{NAME}}"), "Trips/{{CAMERA}}/IMG_1.ARW")
    }
}
