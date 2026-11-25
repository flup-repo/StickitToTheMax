import AppKit
import Foundation

public struct DrawingPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(point: NSPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    public var nsPoint: NSPoint {
        NSPoint(x: x, y: y)
    }
}

public enum PenColor: String, Codable, CaseIterable, Sendable {
    case white
    case yellow
    case blue
    case green
    case pink
    case orange
    case purple
    case black

    public var displayName: String {
        switch self {
        case .white:  return "White"
        case .yellow: return "Yellow"
        case .blue:   return "Blue"
        case .green:  return "Green"
        case .pink:   return "Pink"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .black:  return "Black"
        }
    }

    public var nsColor: NSColor {
        switch self {
        case .white:  return NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.99, alpha: 0.96)
        case .yellow: return NSColor(calibratedRed: 1.00, green: 0.86, blue: 0.25, alpha: 0.96)
        case .blue:   return NSColor(calibratedRed: 0.36, green: 0.72, blue: 1.00, alpha: 0.96)
        case .green:  return NSColor(calibratedRed: 0.35, green: 0.88, blue: 0.52, alpha: 0.96)
        case .pink:   return NSColor(calibratedRed: 1.00, green: 0.45, blue: 0.64, alpha: 0.96)
        case .orange: return NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.24, alpha: 0.96)
        case .purple: return NSColor(calibratedRed: 0.72, green: 0.56, blue: 1.00, alpha: 0.96)
        case .black:  return NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 0.96)
        }
    }
}

public struct DrawingStroke: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var points: [DrawingPoint]
    public var color: PenColor
    public var lineWidth: Double

    public static let defaultLineWidth: Double = 4.0
    public static let minLineWidth: Double = 2.0
    public static let maxLineWidth: Double = 24.0

    public init(
        id: UUID = UUID(),
        points: [DrawingPoint],
        color: PenColor = .yellow,
        lineWidth: Double = DrawingStroke.defaultLineWidth
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.lineWidth = Self.clampedLineWidth(lineWidth)
    }

    public static func clampedLineWidth(_ width: Double) -> Double {
        min(max(width, minLineWidth), maxLineWidth)
    }

    /// Hit-tests whether a point (in global AppKit screen coordinates) touches this stroke
    /// within the given eraser radius.
    public func intersects(point: NSPoint, radius: CGFloat) -> Bool {
        guard !points.isEmpty else { return false }
        let hitThreshold = radius + CGFloat(lineWidth) * 0.5
        let thresholdSq = hitThreshold * hitThreshold

        if points.count == 1 {
            let p = points[0].nsPoint
            let dx = point.x - p.x
            let dy = point.y - p.y
            return (dx * dx + dy * dy) <= thresholdSq
        }

        for i in 0..<(points.count - 1) {
            let a = points[i].nsPoint
            let b = points[i + 1].nsPoint
            if Self.distanceSquared(from: point, toSegmentA: a, b: b) <= thresholdSq {
                return true
            }
        }
        return false
    }

    private static func distanceSquared(from p: NSPoint, toSegmentA a: NSPoint, b: NSPoint) -> CGFloat {
        let abX = b.x - a.x
        let abY = b.y - a.y
        let abLenSq = abX * abX + abY * abY
        if abLenSq <= 0.0001 {
            let dx = p.x - a.x
            let dy = p.y - a.y
            return dx * dx + dy * dy
        }
        let t = max(0, min(1, ((p.x - a.x) * abX + (p.y - a.y) * abY) / abLenSq))
        let projX = a.x + t * abX
        let projY = a.y + t * abY
        let dx = p.x - projX
        let dy = p.y - projY
        return dx * dx + dy * dy
    }
}
