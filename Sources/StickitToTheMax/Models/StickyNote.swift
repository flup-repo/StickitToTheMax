import AppKit
import Foundation

public enum StickyColor: String, Codable, CaseIterable, Sendable {
    case yellow
    case blue
    case green
    case pink
    case purple
    case orange

    public var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .green: return "Green"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .orange: return "Orange"
        }
    }

    public var bodyColor: NSColor {
        switch self {
        case .yellow: return NSColor(calibratedRed: 1.00, green: 0.95, blue: 0.68, alpha: 0.96)
        case .blue:   return NSColor(calibratedRed: 0.78, green: 0.90, blue: 1.00, alpha: 0.96)
        case .green:  return NSColor(calibratedRed: 0.80, green: 0.96, blue: 0.80, alpha: 0.96)
        case .pink:   return NSColor(calibratedRed: 1.00, green: 0.83, blue: 0.88, alpha: 0.96)
        case .purple: return NSColor(calibratedRed: 0.89, green: 0.84, blue: 1.00, alpha: 0.96)
        case .orange: return NSColor(calibratedRed: 1.00, green: 0.87, blue: 0.72, alpha: 0.96)
        }
    }

    public var headerColor: NSColor {
        switch self {
        case .yellow: return NSColor(calibratedRed: 0.97, green: 0.88, blue: 0.45, alpha: 0.98)
        case .blue:   return NSColor(calibratedRed: 0.62, green: 0.81, blue: 0.98, alpha: 0.98)
        case .green:  return NSColor(calibratedRed: 0.62, green: 0.89, blue: 0.64, alpha: 0.98)
        case .pink:   return NSColor(calibratedRed: 0.98, green: 0.69, blue: 0.78, alpha: 0.98)
        case .purple: return NSColor(calibratedRed: 0.77, green: 0.69, blue: 0.97, alpha: 0.98)
        case .orange: return NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.50, alpha: 0.98)
        }
    }

    public var swatchColor: NSColor {
        switch self {
        case .yellow: return NSColor(calibratedRed: 0.96, green: 0.82, blue: 0.25, alpha: 1.0)
        case .blue:   return NSColor(calibratedRed: 0.35, green: 0.67, blue: 0.96, alpha: 1.0)
        case .green:  return NSColor(calibratedRed: 0.36, green: 0.78, blue: 0.44, alpha: 1.0)
        case .pink:   return NSColor(calibratedRed: 0.95, green: 0.49, blue: 0.64, alpha: 1.0)
        case .purple: return NSColor(calibratedRed: 0.63, green: 0.50, blue: 0.94, alpha: 1.0)
        case .orange: return NSColor(calibratedRed: 0.96, green: 0.60, blue: 0.25, alpha: 1.0)
        }
    }

    public var borderColor: NSColor {
        headerColor.blended(withFraction: 0.18, of: .black) ?? headerColor
    }
}

public struct StickyFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(rect: NSRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }

    public var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

public struct StickyNote: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var body: String
    public var color: StickyColor
    public var isDone: Bool
    public var fontSize: Double
    public var frame: StickyFrame
    public var createdAt: Date
    public var updatedAt: Date

    public static let defaultWidth: Double = 260
    public static let defaultHeight: Double = 220
    public static let defaultFontSize: Double = 14.0
    public static let minFontSize: Double = 10.0
    public static let maxFontSize: Double = 32.0
    public static let fontSizeStep: Double = 2.0
    public static let minSize = NSSize(width: 190, height: 140)
    public static let maxSize = NSSize(width: 720, height: 720)

    public init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        color: StickyColor = .yellow,
        isDone: Bool = false,
        fontSize: Double = StickyNote.defaultFontSize,
        frame: StickyFrame,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.color = color
        self.isDone = isDone
        self.fontSize = Self.clampedFontSize(fontSize)
        self.frame = frame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func clampedFontSize(_ size: Double) -> Double {
        min(max(size, minFontSize), maxFontSize)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, color, isDone, fontSize, frame, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        color = try container.decode(StickyColor.self, forKey: .color)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        let decodedFontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? Self.defaultFontSize
        fontSize = Self.clampedFontSize(decodedFontSize)
        frame = try container.decode(StickyFrame.self, forKey: .frame)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct StickyPreset: Sendable {
    public let title: String
    public let color: StickyColor

    public static let defaults: [StickyPreset] = [
        StickyPreset(title: "Work", color: .blue),
        StickyPreset(title: "Personal", color: .yellow),
        StickyPreset(title: "Ideas", color: .purple),
        StickyPreset(title: "Urgent", color: .pink),
        StickyPreset(title: "Errands", color: .green),
    ]
}
