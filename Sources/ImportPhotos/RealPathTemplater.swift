import Foundation

public class RealPathTemplater: PathTemplater {
    public init() {}

    public func calculateRelativePath(from metadata: MediaMetadata, template: String) -> String {
        let calendar = Calendar.current
        let date = metadata.timestamp
        
        let year = String(calendar.component(.year, from: date))
        let month = String(format: "%02d", calendar.component(.month, from: date))
        let day = String(format: "%02d", calendar.component(.day, from: date))
        let hour = String(format: "%02d", calendar.component(.hour, from: date))
        let minute = String(format: "%02d", calendar.component(.minute, from: date))
        let second = String(format: "%02d", calendar.component(.second, from: date))
        
        var path = template
        path = path.replacingOccurrences(of: "{{YEAR}}", with: year)
        path = path.replacingOccurrences(of: "{{MONTH}}", with: month)
        path = path.replacingOccurrences(of: "{{DAY}}", with: day)
        path = path.replacingOccurrences(of: "{{HOUR}}", with: hour)
        path = path.replacingOccurrences(of: "{{MINUTE}}", with: minute)
        path = path.replacingOccurrences(of: "{{SECOND}}", with: second)
        path = path.replacingOccurrences(of: "{{NAME}}", with: metadata.name)
        
        return path
    }
}
