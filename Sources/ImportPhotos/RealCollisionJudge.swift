import Foundation

public class RealCollisionJudge: CollisionJudge {
    public init() {}

    public func evaluate(incoming: MediaMetadata, destinationFiles: [MediaMetadata]) -> DeDuplicationDecision {
        for file in destinationFiles {
            if file.name == incoming.name &&
               file.size == incoming.size &&
               file.timestamp == incoming.timestamp {
                return .skip
            }
        }
        return .new
    }
}
