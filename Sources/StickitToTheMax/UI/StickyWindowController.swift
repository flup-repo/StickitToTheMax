import AppKit

protocol StickyWindowControllerDelegate: AnyObject {
    func stickyControllerDidUpdate(_ note: StickyNote)
    func stickyControllerDidRequestNew(near note: StickyNote)
    func stickyControllerDidRequestDelete(_ note: StickyNote)
}

final class StickyWindowController: NSWindowController, NSWindowDelegate, StickyContentViewDelegate {
    private(set) var note: StickyNote
    weak var delegate: StickyWindowControllerDelegate?

    private let stickyContentView: StickyContentView

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
            self?.adjustFontSize(by: StickyNote.fontSizeStep)
        }
        window.onFontSizeDecrease = { [weak self] in
            self?.adjustFontSize(by: -StickyNote.fontSizeStep)
        }
        window.onFontSizeReset = { [weak self] in
            self?.resetFontSize()
        }
    }

    func adjustFontSize(by delta: Double) {
        let nextSize = StickyNote.clampedFontSize(note.fontSize + delta)
        guard nextSize != note.fontSize else { return }
        note.fontSize = nextSize
        note.updatedAt = Date()
        stickyContentView.apply(note: note)
        delegate?.stickyControllerDidUpdate(note)
    }

    func resetFontSize() {
        guard note.fontSize != StickyNote.defaultFontSize else { return }
        note.fontSize = StickyNote.defaultFontSize
        note.updatedAt = Date()
        stickyContentView.apply(note: note)
        delegate?.stickyControllerDidUpdate(note)
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

    func update(note: StickyNote) {
        self.note = note
        stickyContentView.apply(note: note)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        syncFrameFromWindow()
    }

    func windowDidResize(_ notification: Notification) {
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
}
