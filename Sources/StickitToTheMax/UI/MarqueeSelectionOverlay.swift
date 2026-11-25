import AppKit

/// Tracks a desktop marquee selection rectangle and renders it on the wallpaper layer.
final class MarqueeSelectionOverlay {
    private let window: NSWindow
    private let selectionView: MarqueeSelectionView

    init() {
        let initialFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: StickyWindow.wallpaperLevel.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false

        selectionView = MarqueeSelectionView(frame: NSRect(origin: .zero, size: initialFrame.size))
        window.contentView = selectionView
    }

    func update(screenRect: NSRect) {
        let unionFrame = NSScreen.screens.reduce(NSRect.zero) { partial, screen in
            partial.isEmpty ? screen.frame : partial.union(screen.frame)
        }
        if !unionFrame.isEmpty && window.frame != unionFrame {
            window.setFrame(unionFrame, display: false)
            selectionView.frame = NSRect(origin: .zero, size: unionFrame.size)
        }

        let localRect = NSRect(
            x: screenRect.origin.x - window.frame.origin.x,
            y: screenRect.origin.y - window.frame.origin.y,
            width: screenRect.width,
            height: screenRect.height
        )
        selectionView.selectionRect = localRect
        if !window.isVisible {
            window.orderFront(nil)
        }
    }

    func hide() {
        selectionView.selectionRect = nil
        window.orderOut(nil)
    }
}

private final class MarqueeSelectionView: NSView {
    var selectionRect: NSRect? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rect = selectionRect, rect.width > 1 || rect.height > 1 else { return }

        let accent = NSColor.controlAccentColor
        accent.withAlphaComponent(0.14).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.fill()

        accent.withAlphaComponent(0.80).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

/// Checks whether a global screen point (in AppKit bottom-left coordinates) sits on open desktop wallpaper
/// rather than over a normal application window.
enum DesktopHitTest {
    static func isPointOverNormalWindow(_ appKitPoint: NSPoint) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        // CGWindow bounds use top-left origin relative to the primary screen.
        let cgPoint = CGPoint(x: appKitPoint.x, y: primaryHeight - appKitPoint.y)

        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        for info in infoList {
            if let pid = info[kCGWindowOwnerPID as String] as? Int32, pid == ownPID {
                continue
            }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            // Ignore desktop/wallpaper layers (< 0)
            if layer < 0 { continue }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            if alpha <= 0.01 { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"],
                  w > 0, h > 0 else {
                continue
            }

            let rect = CGRect(x: x, y: y, width: w, height: h)
            if rect.contains(cgPoint) {
                return true
            }
        }
        return false
    }
}
