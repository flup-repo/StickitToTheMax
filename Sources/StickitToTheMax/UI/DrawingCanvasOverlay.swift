import AppKit

enum DrawingTool: Equatable {
    case pen
    case eraser
}

protocol DrawingCanvasOverlayDelegate: AnyObject {
    func drawingCanvasDidUpdateStrokes(_ strokes: [DrawingStroke])
    func drawingCanvasDidRequestExit()
    func drawingCanvasDidChangeLineWidth(_ width: Double)
    func drawingCanvasDidChangeTool(_ tool: DrawingTool)
}

/// Transparent full-desktop canvas pinned to the wallpaper layer that renders persistent freehand strokes
/// and captures pointer input only while Drawing Mode is active.
final class DrawingCanvasOverlay {
    weak var delegate: DrawingCanvasOverlayDelegate?

    private let window: DrawingCanvasWindow
    private let canvasView: DrawingCanvasView

    private(set) var strokes: [DrawingStroke] = []
    private var undoStack: [[DrawingStroke]] = []
    private let maxUndoSteps = 30

    var isDrawingMode: Bool = false {
        didSet {
            guard isDrawingMode != oldValue else { return }
            updateWindowInteractivity()
        }
    }

    var tool: DrawingTool = .pen {
        didSet {
            canvasView.tool = tool
            canvasView.window?.invalidateCursorRects(for: canvasView)
        }
    }

    var penColor: PenColor = .yellow {
        didSet {
            canvasView.penColor = penColor
            canvasView.window?.invalidateCursorRects(for: canvasView)
        }
    }

    var lineWidth: Double = DrawingStroke.defaultLineWidth {
        didSet {
            let clamped = DrawingStroke.clampedLineWidth(lineWidth)
            if clamped != lineWidth { lineWidth = clamped }
            canvasView.lineWidth = clamped
            canvasView.window?.invalidateCursorRects(for: canvasView)
        }
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var displayTransform: CanvasTransform = .identity {
        didSet {
            guard displayTransform != oldValue else { return }
            canvasView.displayTransform = displayTransform
        }
    }

    init() {
        let unionFrame = Self.allScreensUnionFrame()
        window = DrawingCanvasWindow(contentRect: unionFrame)
        canvasView = DrawingCanvasView(frame: NSRect(origin: .zero, size: unionFrame.size))
        window.contentView = canvasView

        canvasView.onFinishStroke = { [weak self] stroke in
            self?.appendStroke(stroke)
        }
        canvasView.onEraseAtPoint = { [weak self] screenPoint, radius, isStartOfGesture in
            self?.eraseStrokes(at: screenPoint, radius: radius, recordUndo: isStartOfGesture) ?? false
        }
        canvasView.onFinishEraseGesture = { [weak self] didErase in
            guard let self, didErase else { return }
            self.delegate?.drawingCanvasDidUpdateStrokes(self.strokes)
        }

        window.onEscapeKey = { [weak self] in
            self?.delegate?.drawingCanvasDidRequestExit()
        }
        window.onUndoKey = { [weak self] in
            self?.undo()
        }
        window.onDecreaseSizeKey = { [weak self] in
            guard let self else { return }
            self.lineWidth = DrawingStroke.clampedLineWidth(self.lineWidth - 2)
            self.delegate?.drawingCanvasDidChangeLineWidth(self.lineWidth)
        }
        window.onIncreaseSizeKey = { [weak self] in
            guard let self else { return }
            self.lineWidth = DrawingStroke.clampedLineWidth(self.lineWidth + 2)
            self.delegate?.drawingCanvasDidChangeLineWidth(self.lineWidth)
        }
        window.onSelectToolKey = { [weak self] newTool in
            guard let self else { return }
            self.tool = newTool
            self.delegate?.drawingCanvasDidChangeTool(newTool)
        }
    }

    func setStrokes(_ newStrokes: [DrawingStroke]) {
        strokes = newStrokes
        canvasView.strokes = strokes
        syncVisibility(visible: true)
    }

    func syncFrameToScreens() {
        let unionFrame = Self.allScreensUnionFrame()
        if !unionFrame.isEmpty && window.frame != unionFrame {
            window.setFrame(unionFrame, display: false)
            canvasView.frame = NSRect(origin: .zero, size: unionFrame.size)
            canvasView.needsDisplay = true
        }
    }

    func setVisible(_ visible: Bool) {
        if !visible && isDrawingMode {
            isDrawingMode = false
        }
        syncVisibility(visible: visible)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        strokes = previous
        canvasView.strokes = strokes
        delegate?.drawingCanvasDidUpdateStrokes(strokes)
    }

    func clearAll() {
        guard !strokes.isEmpty else { return }
        pushUndoSnapshot()
        strokes = []
        canvasView.strokes = []
        delegate?.drawingCanvasDidUpdateStrokes(strokes)
    }

    // MARK: - Private

    private func appendStroke(_ stroke: DrawingStroke) {
        pushUndoSnapshot()
        strokes.append(stroke)
        canvasView.strokes = strokes
        delegate?.drawingCanvasDidUpdateStrokes(strokes)
    }

    private var didSnapshotCurrentEraseGesture = false

    private func eraseStrokes(at screenPoint: NSPoint, radius: CGFloat, recordUndo: Bool) -> Bool {
        if recordUndo {
            didSnapshotCurrentEraseGesture = false
        }
        let canonicalPoint = displayTransform.invert(screenPoint)
        let canonicalRadius = radius / displayTransform.scale
        let matchingIndices = strokes.indices.filter {
            strokes[$0].intersects(point: canonicalPoint, radius: canonicalRadius)
        }
        guard !matchingIndices.isEmpty else { return false }

        if !didSnapshotCurrentEraseGesture {
            pushUndoSnapshot()
            didSnapshotCurrentEraseGesture = true
        }
        let toRemove = Set(matchingIndices)
        strokes = strokes.enumerated().compactMap { toRemove.contains($0.offset) ? nil : $0.element }
        canvasView.strokes = strokes
        return true
    }

    private func pushUndoSnapshot() {
        undoStack.append(strokes)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst(undoStack.count - maxUndoSteps)
        }
    }

    private func updateWindowInteractivity() {
        syncFrameToScreens()
        window.ignoresMouseEvents = !isDrawingMode
        canvasView.isDrawingMode = isDrawingMode
        if isDrawingMode {
            window.level = NSWindow.Level(rawValue: StickyWindow.wallpaperLevel.rawValue + 1)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.invalidateCursorRects(for: canvasView)
        } else {
            window.level = NSWindow.Level(rawValue: StickyWindow.wallpaperLevel.rawValue + 1)
            if strokes.isEmpty {
                window.orderOut(nil)
            } else {
                window.orderFront(nil)
            }
        }
    }

    private func syncVisibility(visible: Bool) {
        syncFrameToScreens()
        if !visible {
            window.orderOut(nil)
            return
        }
        if isDrawingMode || !strokes.isEmpty {
            window.orderFront(nil)
        } else {
            window.orderOut(nil)
        }
    }

    private static func allScreensUnionFrame() -> NSRect {
        let union = NSScreen.screens.reduce(NSRect.zero) { partial, screen in
            partial.isEmpty ? screen.frame : partial.union(screen.frame)
        }
        return union.isEmpty ? NSRect(x: 0, y: 0, width: 1440, height: 900) : union
    }
}

// MARK: - Window

private final class DrawingCanvasWindow: NSWindow {
    var onEscapeKey: (() -> Void)?
    var onUndoKey: (() -> Void)?
    var onDecreaseSizeKey: (() -> Void)?
    var onIncreaseSizeKey: (() -> Void)?
    var onSelectToolKey: ((DrawingTool) -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: StickyWindow.wallpaperLevel.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscapeKey?()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command), chars == "z" {
            onUndoKey?()
            return
        }
        if flags.isEmpty {
            if chars == "[" {
                onDecreaseSizeKey?()
                return
            }
            if chars == "]" {
                onIncreaseSizeKey?()
                return
            }
            if chars == "e" {
                onSelectToolKey?(.eraser)
                return
            }
            if chars == "p" {
                onSelectToolKey?(.pen)
                return
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.contains(.command), chars == "z" {
            onUndoKey?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Canvas View

private final class DrawingCanvasView: NSView {
    var strokes: [DrawingStroke] = [] {
        didSet { needsDisplay = true }
    }
    var displayTransform: CanvasTransform = .identity {
        didSet { needsDisplay = true }
    }
    var isDrawingMode: Bool = false {
        didSet { needsDisplay = true }
    }
    var tool: DrawingTool = .pen
    var penColor: PenColor = .yellow
    var lineWidth: Double = DrawingStroke.defaultLineWidth

    var onFinishStroke: ((DrawingStroke) -> Void)?
    var onEraseAtPoint: ((NSPoint, CGFloat, Bool) -> Bool)?
    var onFinishEraseGesture: ((Bool) -> Void)?

    private var activeStroke: DrawingStroke?
    private var eraserCursorPoint: NSPoint?
    private var didEraseInCurrentGesture = false

    private var eraserRadius: CGFloat {
        max(12, CGFloat(lineWidth) * 1.4)
    }

    override func resetCursorRects() {
        guard isDrawingMode else { return }
        let cursor = makeToolCursor()
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard isDrawingMode else { return }
        let screenPoint = NSEvent.mouseLocation

        switch tool {
        case .pen:
            let canonicalPoint = displayTransform.invert(screenPoint)
            let canonicalWidth = DrawingStroke.clampedLineWidth(lineWidth / Double(displayTransform.scale))
            activeStroke = DrawingStroke(
                points: [DrawingPoint(point: canonicalPoint)],
                color: penColor,
                lineWidth: canonicalWidth
            )
            needsDisplay = true

        case .eraser:
            didEraseInCurrentGesture = false
            eraserCursorPoint = screenPoint
            if onEraseAtPoint?(screenPoint, eraserRadius, true) == true {
                didEraseInCurrentGesture = true
            }
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDrawingMode else { return }
        let screenPoint = NSEvent.mouseLocation

        switch tool {
        case .pen:
            guard var current = activeStroke else { return }
            let canonicalPoint = displayTransform.invert(screenPoint)
            if let last = current.points.last {
                let lastScreen = displayTransform.apply(to: last.nsPoint)
                let dx = screenPoint.x - lastScreen.x
                let dy = screenPoint.y - lastScreen.y
                guard (dx * dx + dy * dy) >= 2.25 else { return }
            }
            current.points.append(DrawingPoint(point: canonicalPoint))
            activeStroke = current
            needsDisplay = true

        case .eraser:
            eraserCursorPoint = screenPoint
            if onEraseAtPoint?(screenPoint, eraserRadius, false) == true {
                didEraseInCurrentGesture = true
            }
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isDrawingMode else { return }

        switch tool {
        case .pen:
            if let finished = activeStroke {
                activeStroke = nil
                onFinishStroke?(finished)
                needsDisplay = true
            }

        case .eraser:
            eraserCursorPoint = nil
            let didErase = didEraseInCurrentGesture
            didEraseInCurrentGesture = false
            onFinishEraseGesture?(didErase)
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let origin = window?.frame.origin else { return }

        for stroke in strokes {
            drawStroke(stroke, windowOrigin: origin)
        }
        if let activeStroke {
            drawStroke(activeStroke, windowOrigin: origin)
        }

        if isDrawingMode, tool == .eraser, let pt = eraserCursorPoint {
            let local = NSPoint(x: pt.x - origin.x, y: pt.y - origin.y)
            let r = eraserRadius
            let circleRect = NSRect(x: local.x - r, y: local.y - r, width: r * 2, height: r * 2)
            let ring = NSBezierPath(ovalIn: circleRect)
            NSColor.white.withAlphaComponent(0.18).setFill()
            ring.fill()
            NSColor.white.withAlphaComponent(0.85).setStroke()
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

    private func drawStroke(_ stroke: DrawingStroke, windowOrigin: NSPoint) {
        guard !stroke.points.isEmpty else { return }
        let color = stroke.color.nsColor
        let width = displayTransform.applyLineWidth(stroke.lineWidth)

        if stroke.points.count == 1 {
            let screenPt = displayTransform.apply(to: stroke.points[0].nsPoint)
            let local = NSPoint(x: screenPt.x - windowOrigin.x, y: screenPt.y - windowOrigin.y)
            let dotRect = NSRect(x: local.x - width / 2, y: local.y - width / 2, width: width, height: width)
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return
        }

        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let localPoints = stroke.points.map { pt -> NSPoint in
            let screenPt = displayTransform.apply(to: pt.nsPoint)
            return NSPoint(x: screenPt.x - windowOrigin.x, y: screenPt.y - windowOrigin.y)
        }

        path.move(to: localPoints[0])
        if localPoints.count == 2 {
            path.line(to: localPoints[1])
        } else {
            for i in 1..<(localPoints.count - 1) {
                let mid = NSPoint(
                    x: (localPoints[i].x + localPoints[i + 1].x) * 0.5,
                    y: (localPoints[i].y + localPoints[i + 1].y) * 0.5
                )
                path.curve(
                    to: mid,
                    controlPoint1: localPoints[i],
                    controlPoint2: localPoints[i]
                )
            }
            path.line(to: localPoints[localPoints.count - 1])
        }

        color.setStroke()
        path.stroke()
    }

    private func makeToolCursor() -> NSCursor {
        switch tool {
        case .pen:
            let diameter = min(max(CGFloat(lineWidth) + 4, 10), 28)
            let size = diameter + 4
            let image = NSImage(size: NSSize(width: size, height: size))
            image.lockFocus()
            let rect = NSRect(x: 2, y: 2, width: diameter, height: diameter)
            let circle = NSBezierPath(ovalIn: rect)
            penColor.nsColor.setFill()
            circle.fill()
            let outlineColor: NSColor = (penColor == .black) ? .white : NSColor(calibratedWhite: 0.1, alpha: 0.85)
            outlineColor.setStroke()
            circle.lineWidth = 1.4
            circle.stroke()
            image.unlockFocus()
            return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))

        case .eraser:
            let diameter = min(max(eraserRadius * 2, 18), 44)
            let size = diameter + 4
            let image = NSImage(size: NSSize(width: size, height: size))
            image.lockFocus()
            let rect = NSRect(x: 2, y: 2, width: diameter, height: diameter)
            let circle = NSBezierPath(ovalIn: rect)
            NSColor.white.withAlphaComponent(0.22).setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.75).setStroke()
            circle.lineWidth = 2.0
            circle.stroke()
            NSColor.white.withAlphaComponent(0.95).setStroke()
            circle.lineWidth = 1.0
            circle.stroke()
            image.unlockFocus()
            return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
        }
    }
}
