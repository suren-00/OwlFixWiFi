import Foundation
import SwiftUI

/// Log level severity
public enum LogLevel: String, Codable, CaseIterable {
    case info
    case success
    case warning
    case error
    
    public var iconName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .info:
            return Color.blue
        case .success:
            return Color.green
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        }
    }
    
    public var label: String {
        switch self {
        case .info:
            return "ℹ️"
        case .success:
            return "✅"
        case .warning:
            return "⚠️"
        case .error:
            return "❌"
        }
    }
}

/// Structure representing a log record in the app log console
public struct LogEntry: Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel = .info, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
    
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    public var formattedLogLine: String {
        return "[\(formattedTime)] \(level.label) \(message)"
    }
}
