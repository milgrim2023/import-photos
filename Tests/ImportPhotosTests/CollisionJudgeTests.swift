import XCTest
@testable import ImportPhotos

final class CollisionJudgeTests: XCTestCase {
    
    func testEvaluateNewFile() {
        let judge: CollisionJudge = RealCollisionJudge()
        let incoming = MediaMetadata(name: "photo.jpg", size: 1024, timestamp: Date())
        let destination: [MediaMetadata] = []
        
        let decision = judge.evaluate(incoming: incoming, destinationFiles: destination)
        
        XCTAssertEqual(decision, .new)
    }
    
    func testEvaluateDuplicateFile() {
        let judge: CollisionJudge = RealCollisionJudge()
        let date = Date()
        let incoming = MediaMetadata(name: "photo.jpg", size: 1024, timestamp: date)
        let destination: [MediaMetadata] = [
            MediaMetadata(name: "photo.jpg", size: 1024, timestamp: date)
        ]
        
        let decision = judge.evaluate(incoming: incoming, destinationFiles: destination)
        
        XCTAssertEqual(decision, .skip)
    }
    
    func testEvaluateDifferentName() {
        let judge: CollisionJudge = RealCollisionJudge()
        let date = Date()
        let incoming = MediaMetadata(name: "photo.jpg", size: 1024, timestamp: date)
        let destination: [MediaMetadata] = [
            MediaMetadata(name: "other.jpg", size: 1024, timestamp: date)
        ]
        
        let decision = judge.evaluate(incoming: incoming, destinationFiles: destination)
        
        XCTAssertEqual(decision, .new)
    }
    
    func testEvaluateDifferentSize() {
        let judge: CollisionJudge = RealCollisionJudge()
        let date = Date()
        let incoming = MediaMetadata(name: "photo.jpg", size: 1024, timestamp: date)
        let destination: [MediaMetadata] = [
            MediaMetadata(name: "photo.jpg", size: 2048, timestamp: date)
        ]
        
        let decision = judge.evaluate(incoming: incoming, destinationFiles: destination)
        
        XCTAssertEqual(decision, .new)
    }
    
    func testEvaluateDifferentTimestamp() {
        let judge: CollisionJudge = RealCollisionJudge()
        let date = Date()
        let incoming = MediaMetadata(name: "photo.jpg", size: 1024, timestamp: date)
        let destination: [MediaMetadata] = [
            MediaMetadata(name: "photo.jpg", size: 1024, timestamp: date.addingTimeInterval(1))
        ]
        
        let decision = judge.evaluate(incoming: incoming, destinationFiles: destination)
        
        XCTAssertEqual(decision, .new)
    }
}
