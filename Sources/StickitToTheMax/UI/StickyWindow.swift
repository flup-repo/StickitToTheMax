import AppKit

/// A borderless, resizable window pinned to the macOS desktop wallpaper layer.
/// It stays strictly behind all normal application windows and remains stationary
/// across Spaces and during Mission Control / "Show Desktop".
final class StickyWindow: NSWindow {
    static var wallpaperLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    var onFontSizeIncrease: (() -> Void)?
    var onFontSizeDecrease: (() -> Void)?
    var onFontSizeReset: (() -> Void)?
    var onCommandClick: (() -> Void)?
    var onPlainClick: (() -> Void)?
    var onEscapeKey: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        self.level = Self.wallpaperLevel
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.minSize = StickyNote.minSize
        self.maxSize = StickyNote.maxSize
        self.isMovableByWindowBackground = false
        self.tabbingMode = .disallowed
        // Stickies always use light pastel surfaces, so use aqua appearance for crisp dark text/cursors
        self.appearance = NSAppearance(named: .aqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command), !flags.contains(.option), !flags.contains(.control) {
                onCommandClick?()
                return
            } else {
                onPlainClick?()
            }
        } else if event.type == .keyDown, event.keyCode == 53 {
            onEscapeKey?()
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), !flags.contains(.option), !flags.contains(.control) {
            let chars = event.charactersIgnoringModifiers ?? ""
            if chars == "+" || chars == "=" {
                onFontSizeIncrease?()
                return true
            }
            if chars == "-" || chars == "_" {
                onFontSizeDecrease?()
                return true
            }
            if chars == "0" {
                onFontSizeReset?()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
