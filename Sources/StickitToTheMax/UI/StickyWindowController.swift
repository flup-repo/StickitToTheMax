import AppKit

/// Pure geometry helper for single and group resizing (kept separate for easy unit testing).
enum StickyGeometry {
    static func resizedRect(
        from initial: NSRect,
        edge: StickyResizeEdge,
        deltaX: CGFloat,
        deltaY: CGFloat,
        minSize: NSSize = StickyNote.minSize,
        maxSize: NSSize = StickyNote.maxSize
    ) -> NSRect {
        var newX = initial.origin.x
        var newY = initial.origin.y
        var newWidth = initial.width
        var newHeight = initial.height

        switch edge {
        case .bottomRight:
            newWidth = clamp(initial.width + deltaX, min: minSize.width, max: maxSize.width)
            newHeight = clamp(initial.height + deltaY, min: minSize.height, max: maxSize.height)
            newY = initial.maxY - newHeight

        case .right:
            newWidth = clamp(initial.width + deltaX, min: minSize.width, max: maxSize.width)

        case .bottom:
            newHeight = clamp(initial.height + deltaY, min: minSize.height, max: maxSize.height)
            newY = initial.maxY - newHeight

        case .left:
            newWidth = clamp(initial.width - deltaX, min: minSize.width, max: maxSize.width)
            newX = initial.maxX - newWidth

        case .bottomLeft:
            newWidth = clamp(initial.width - deltaX, min: minSize.width, max: maxSize.width)
            newHeight = clamp(initial.height + deltaY, min: minSize.height, max: maxSize.height)
            newX = initial.maxX - newWidth
            newY = initial.maxY - newHeight
        }

        return NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minValue), maxValue)
    }
}

protocol StickyWindowControllerDelegate: AnyObject {
    func stickyControllerDidUpdate(_ note: StickyNote)
    func stickyControllerDidRequestNew(near note: StickyNote)
    func stickyControllerDidRequestDelete(_ note: StickyNote)
    func stickyControllerDidCommandClick(id: UUID)
    func stickyControllerDidPlainClick(id: UUID)
    func stickyControllerDidRequestClearSelection()
    func stickyControllerDidBeginMove(id: UUID)
    func stickyControllerDidDragMove(deltaX: CGFloat, deltaY: CGFloat)
    func stickyControllerDidEndMove()
    func stickyControllerDidBeginResize(id: UUID, edge: StickyResizeEdge)
    func stickyControllerDidDragResize(edge: StickyResizeEdge, deltaX: CGFloat, deltaY: CGFloat)
    func stickyControllerDidEndResize()
    func stickyControllerDidAdjustFontSize(id: UUID, delta: Double)
    func stickyControllerDidResetFontSize(id: UUID)
}

final class StickyWindowController: NSWindowController, NSWindowDelegate, StickyContentViewDelegate {
    private(set) var note: StickyNote
    weak var delegate: StickyWindowControllerDelegate?

    private let stickyContentView: StickyContentView
    private var isProgrammaticFrameChange = false

    init(note: StickyNote) {
        self.note = note
        let window = StickyWindow(contentRect: note.frame.nsRect)
        self.stickyContentView = StickyContentView(frame: NSRect(origin: .zero, size: note.frame.nsRect.size))
        super.init(window: window)

        window.contentView = stickyContentView
        window.delegate = self
        stickyContentView.delegate = self
        stickyContentView.apply(note: note)

        window.onFontSizeIncrease = { [weak self] in
            guard let self else { return }
            self.delegate?.stickyControllerDidAdjustFontSize(id: self.note.id, delta: StickyNote.fontSizeStep)
        }
        window.onFontSizeDecrease = { [weak self] in
            guard let self else { return }
            self.delegate?.stickyControllerDidAdjustFontSize(id: self.note.id, delta: -StickyNote.fontSizeStep)
        }
        window.onFontSizeReset = { [weak self] in
            guard let self else { return }
            self.delegate?.stickyControllerDidResetFontSize(id: self.note.id)
        }
        window.onCommandClick = { [weak self] in
            guard let self else { return }
            self.delegate?.stickyControllerDidCommandClick(id: self.note.id)
        }
        window.onPlainClick = { [weak self] in
            guard let self else { return }
            self.delegate?.stickyControllerDidPlainClick(id: self.note.id)
        }
        window.onEscapeKey = { [weak self] in
            self?.delegate?.stickyControllerDidRequestClearSelection()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showOnDesktop(focus: Bool = false) {
        guard let window else { return }
        window.level = StickyWindow.wallpaperLevel
        window.orderFront(nil)
        if focus {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            stickyContentView.focusTitle()
        }
    }

    func setSelected(_ selected: Bool) {
        stickyContentView.setSelected(selected)
    }

    func applyFontSize(_ size: Double) {
        let clamped = StickyNote.clampedFontSize(size)
        guard clamped != note.fontSize else { return }
        note.fontSize = clamped
        note.updatedAt = Date()
        stickyContentView.apply(note: note)
    }

    func setFrameProgrammatically(_ rect: NSRect) {
        isProgrammaticFrameChange = true
        window?.setFrame(rect, display: true)
        isProgrammaticFrameChange = false
    }

    func commitCurrentFrameToModel() -> StickyNote {
        if let frame = window?.frame {
            let updatedFrame = StickyFrame(rect: frame)
            if updatedFrame != note.frame {
                note.frame = updatedFrame
                note.updatedAt = Date()
            }
        }
        return note
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticFrameChange else { return }
        syncFrameFromWindow()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isProgrammaticFrameChange else { return }
        syncFrameFromWindow()
    }

    private func syncFrameFromWindow() {
        guard let frame = window?.frame else { return }
        let updatedFrame = StickyFrame(rect: frame)
        guard updatedFrame != note.frame else { return }
        note.frame = updatedFrame
        note.updatedAt = Date()
        delegate?.stickyControllerDidUpdate(note)
    }

    // MARK: - StickyContentViewDelegate

    func stickyViewDidChangeTitle(_ title: String) {
        note.title = title
        note.updatedAt = Date()
        delegate?.stickyControllerDidUpdate(note)
    }

    func stickyViewDidChangeBody(_ body: String) {
        note.body = body
        note.updatedAt = Date()
        delegate?.stickyControllerDidUpdate(note)
    }

    func stickyViewDidToggleDone() {
        note.isDone.toggle()
        note.updatedAt = Date()
        stickyContentView.apply(note: note)
        delegate?.stickyControllerDidUpdate(note)
    }

    func stickyViewDidSelectColor(_ color: StickyColor) {
        note.color = color
        note.updatedAt = Date()
        stickyContentView.apply(note: note)
        delegate?.stickyControllerDidUpdate(note)
    }

    func stickyViewDidRequestNewSticky() {
        delegate?.stickyControllerDidRequestNew(near: note)
    }

    func stickyViewDidRequestDelete() {
        delegate?.stickyControllerDidRequestDelete(note)
    }

    func stickyViewDidBeginMove() {
        delegate?.stickyControllerDidBeginMove(id: note.id)
    }

    func stickyViewDidDragMove(deltaX: CGFloat, deltaY: CGFloat) {
        delegate?.stickyControllerDidDragMove(deltaX: deltaX, deltaY: deltaY)
    }

    func stickyViewDidEndMove() {
        delegate?.stickyControllerDidEndMove()
    }

    func stickyViewDidBeginResize(edge: StickyResizeEdge) {
        delegate?.stickyControllerDidBeginResize(id: note.id, edge: edge)
    }

    func stickyViewDidDragResize(edge: StickyResizeEdge, deltaX: CGFloat, deltaY: CGFloat) {
        delegate?.stickyControllerDidDragResize(edge: edge, deltaX: deltaX, deltaY: deltaY)
    }

    func stickyViewDidEndResize() {
        delegate?.stickyControllerDidEndResize()
    }
}
