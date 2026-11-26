import AppKit
import Foundation

/// Uniform, aspect-preserving affine transform that maps canonical wallpaper coordinates
/// (stickies + drawing strokes together) onto the currently active screen layout whenever
/// displays are connected, disconnected, or resized.
public struct CanvasTransform: Equatable, Sendable {
    public let scale: CGFloat
    public let offsetX: CGFloat
    public let offsetY: CGFloat

    public static let identity = CanvasTransform(scale: 1.0, offsetX: 0.0, offsetY: 0.0)

    public init(scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        self.scale = max(scale, 0.1)
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    public var isIdentity: Bool {
        abs(scale - 1.0) < 0.0001 && abs(offsetX) < 0.5 && abs(offsetY) < 0.5
    }

    // MARK: - Forward (Canonical -> Display)

    public func apply(to point: NSPoint) -> NSPoint {
        NSPoint(
            x: point.x * scale + offsetX,
            y: point.y * scale + offsetY
        )
    }

    public func apply(to rect: NSRect) -> NSRect {
        let minDisplayW = max(120, StickyNote.minSize.width * scale)
        let minDisplayH = max(90, StickyNote.minSize.height * scale)
        let width = max(minDisplayW, rect.width * scale)
        let height = max(minDisplayH, rect.height * scale)
        let center = apply(to: NSPoint(x: rect.midX, y: rect.midY))
        return NSRect(
            x: round(center.x - width * 0.5),
            y: round(center.y - height * 0.5),
            width: round(width),
            height: round(height)
        )
    }

    public func applyLineWidth(_ width: Double) -> CGFloat {
        max(1.0, CGFloat(width) * scale)
    }

    // MARK: - Inverse (Display -> Canonical)

    public func invert(_ point: NSPoint) -> NSPoint {
        NSPoint(
            x: (point.x - offsetX) / scale,
            y: (point.y - offsetY) / scale
        )
    }

    public func invert(_ rect: NSRect) -> NSRect {
        let width = rect.width / scale
        let height = rect.height / scale
        let center = invert(NSPoint(x: rect.midX, y: rect.midY))
        return NSRect(
            x: center.x - width * 0.5,
            y: center.y - height * 0.5,
            width: width,
            height: height
        )
    }

    // MARK: - Layout Fitting

    /// Computes the combined canonical bounding box of all stickies and drawing strokes.
    public static func contentBounds(notes: [StickyNote], strokes: [DrawingStroke]) -> NSRect? {
        var bounds: NSRect?

        for note in notes {
            let rect = note.frame.nsRect
            bounds = bounds?.union(rect) ?? rect
        }

        for stroke in strokes {
            let pad = CGFloat(stroke.lineWidth) * 0.5
            for pt in stroke.points {
                let r = NSRect(x: CGFloat(pt.x) - pad, y: CGFloat(pt.y) - pad, width: pad * 2, height: pad * 2)
                bounds = bounds?.union(r) ?? r
            }
        }

        return bounds
    }

    /// Computes a display transform that keeps every sticky and stroke visible and in exact
    /// relative alignment across monitor switches. Returns `.identity` when everything already
    /// fits comfortably on the currently connected screens.
    public static func fit(
        notes: [StickyNote],
        strokes: [DrawingStroke],
        visibleScreenFrames: [NSRect],
        fallbackVisibleFrame: NSRect,
        padding: CGFloat = 16
    ) -> CanvasTransform {
        guard !visibleScreenFrames.isEmpty else { return .identity }
        guard let content = contentBounds(notes: notes, strokes: strokes),
              content.width > 1, content.height > 1 else {
            return .identity
        }

        // If every sticky and stroke point is already comfortably inside the connected screens,
        // keep 1:1 canonical coordinates.
        let allNotesVisible = notes.allSatisfy { note in
            let rect = note.frame.nsRect
            return visibleScreenFrames.contains { screen in
                screen.insetBy(dx: -4, dy: -4).contains(rect)
            }
        }
        let allStrokesVisible = strokes.allSatisfy { stroke in
            stroke.points.allSatisfy { pt in
                let p = pt.nsPoint
                return visibleScreenFrames.contains { screen in
                    screen.insetBy(dx: -4, dy: -4).contains(p)
                }
            }
        }
        if allNotesVisible && allStrokesVisible {
            return .identity
        }

        // Fit the entire canonical layout uniformly into the target screen's visible frame.
        let target = fallbackVisibleFrame.insetBy(dx: padding, dy: padding)
        guard target.width > 100, target.height > 100 else { return .identity }

        let scaleX = target.width / content.width
        let scaleY = target.height / content.height
        let scale = min(1.0, min(scaleX, scaleY))

        let offsetX = target.midX - content.midX * scale
        let offsetY = target.midY - content.midY * scale

        return CanvasTransform(scale: scale, offsetX: offsetX, offsetY: offsetY)
    }
}
