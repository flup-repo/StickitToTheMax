import AppKit

protocol StickyContentViewDelegate: AnyObject {
    func stickyViewDidChangeTitle(_ title: String)
    func stickyViewDidChangeBody(_ body: String)
    func stickyViewDidToggleDone()
    func stickyViewDidSelectColor(_ color: StickyColor)
    func stickyViewDidRequestNewSticky()
    func stickyViewDidRequestDelete()
}

/// Dedicated top grab bar with a centered macOS-style pill indicator and open-hand cursor.
private final class DragHandleBarView: NSView {
    var pillColor: NSColor = NSColor(calibratedWhite: 0.2, alpha: 0.28) {
        didSet { needsDisplay = true }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let pillWidth: CGFloat = 36
        let pillHeight: CGFloat = 3.5
        let pillRect = NSRect(
            x: (bounds.width - pillWidth) / 2,
            y: (bounds.height - pillHeight) / 2 - 1,
            width: pillWidth,
            height: pillHeight
        )
        pillColor.setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2).fill()
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        window?.performDrag(with: event)
        NSCursor.pop()
    }
}

/// Header strip that initiates native window dragging when dragged outside interactive controls.
private final class DraggableHeaderView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        window?.performDrag(with: event)
        NSCursor.pop()
    }
}

/// Title field that drags the window if the user clicks & drags, and edits on a plain click.
private final class DraggableTitleField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        // If already editing, let normal text selection / caret placement happen.
        if currentEditor() != nil {
            super.mouseDown(with: event)
            return
        }

        guard let window else {
            super.mouseDown(with: event)
            return
        }

        let startLocation = event.locationInWindow
        let dragThreshold: CGFloat = 3.0

        while let nextEvent = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .leftMouseDragged:
                let dx = nextEvent.locationInWindow.x - startLocation.x
                let dy = nextEvent.locationInWindow.y - startLocation.y
                if hypot(dx, dy) >= dragThreshold {
                    NSCursor.closedHand.push()
                    window.performDrag(with: event)
                    NSCursor.pop()
                    return
                }
            case .leftMouseUp:
                window.makeFirstResponder(self)
                return
            default:
                break
            }
        }
    }
}

/// Subtle bottom-right diagonal resize handle so users have a clear visual affordance for resizing.
private final class ResizeGripView: NSView {
    var lineColor: NSColor = NSColor(calibratedWhite: 0.25, alpha: 0.35) {
        didSet { needsDisplay = true }
    }

    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowFrame: NSRect = .zero

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        lineColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round

        let offsets: [CGFloat] = [4, 8, 12]
        for offset in offsets {
            path.move(to: NSPoint(x: bounds.maxX - offset, y: 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: offset))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let deltaX = current.x - initialMouseLocation.x
        let deltaY = initialMouseLocation.y - current.y

        let newWidth = min(max(initialWindowFrame.width + deltaX, window.minSize.width), window.maxSize.width)
        let newHeight = min(max(initialWindowFrame.height + deltaY, window.minSize.height), window.maxSize.height)
        let newOriginY = initialWindowFrame.maxY - newHeight

        let newFrame = NSRect(
            x: initialWindowFrame.origin.x,
            y: newOriginY,
            width: newWidth,
            height: newHeight
        )
        window.setFrame(newFrame, display: true)
    }
}

final class StickyContentView: NSView, NSTextFieldDelegate, NSTextViewDelegate {
    weak var delegate: StickyContentViewDelegate?

    private let dragHandleBar = DragHandleBarView()
    private let headerView = DraggableHeaderView()
    private let doneButton = NSButton()
    private let titleField = DraggableTitleField()
    private let colorButton = NSButton()
    private let addButton = NSButton()
    private let deleteButton = NSButton()
    private let separatorView = NSView()
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let resizeGrip = ResizeGripView()

    private var currentColor: StickyColor = .yellow
    private var isDone: Bool = false
    private var currentFontSize: Double = StickyNote.defaultFontSize
    private var isUpdatingProgrammatically = false

    private var bodyFont: NSFont {
        NSFont.systemFont(ofSize: CGFloat(currentFontSize), weight: .regular)
    }

    private var titleFont: NSFont {
        let scaled = min(max(currentFontSize * 0.93, 12.0), 18.0)
        return NSFont.systemFont(ofSize: CGFloat(scaled), weight: .semibold)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        setupHeader()
        setupBody()
        setupResizeGrip()
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(note: StickyNote) {
        isUpdatingProgrammatically = true
        defer { isUpdatingProgrammatically = false }

        currentColor = note.color
        isDone = note.isDone
        currentFontSize = note.fontSize

        if titleField.stringValue != note.title {
            titleField.stringValue = note.title
        }
        if textView.string != note.body {
            textView.string = note.body
        }

        refreshAppearance()
    }

    func focusBody() {
        window?.makeFirstResponder(textView)
    }

    func focusTitle() {
        window?.makeFirstResponder(titleField)
    }

    // MARK: - Setup

    private func setupHeader() {
        dragHandleBar.wantsLayer = true
        dragHandleBar.toolTip = "Drag to move sticky"
        dragHandleBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dragHandleBar)

        headerView.wantsLayer = true
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)

        configureIconButton(
            doneButton,
            symbolName: "checkmark.circle",
            tooltip: "Mark sticky as done (cross out)",
            action: #selector(handleDoneToggle)
        )

        titleField.isBordered = false
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.font = titleFont
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.usesSingleLineMode = true
        titleField.placeholderString = "Title..."
        titleField.delegate = self
        titleField.translatesAutoresizingMaskIntoConstraints = false

        colorButton.isBordered = false
        colorButton.bezelStyle = .inline
        colorButton.title = ""
        colorButton.toolTip = "Change sticky color"
        colorButton.target = self
        colorButton.action = #selector(handleColorMenu(_:))
        colorButton.translatesAutoresizingMaskIntoConstraints = false

        configureIconButton(
            addButton,
            symbolName: "plus",
            tooltip: "New sticky",
            action: #selector(handleAdd)
        )

        configureIconButton(
            deleteButton,
            symbolName: "xmark",
            tooltip: "Delete sticky",
            action: #selector(handleDelete)
        )

        headerView.addSubview(doneButton)
        headerView.addSubview(titleField)
        headerView.addSubview(colorButton)
        headerView.addSubview(addButton)
        headerView.addSubview(deleteButton)

        separatorView.wantsLayer = true
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separatorView)
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, tooltip: String, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .inline
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupBody() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.font = bodyFont
        textView.insertionPointColor = NSColor(calibratedWhite: 0.15, alpha: 1.0)
        textView.delegate = self

        scrollView.documentView = textView
        addSubview(scrollView)
    }

    private func setupResizeGrip() {
        resizeGrip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resizeGrip)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            dragHandleBar.topAnchor.constraint(equalTo: topAnchor),
            dragHandleBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            dragHandleBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            dragHandleBar.heightAnchor.constraint(equalToConstant: 14),

            headerView.topAnchor.constraint(equalTo: dragHandleBar.bottomAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 30),

            doneButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            doneButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            doneButton.widthAnchor.constraint(equalToConstant: 20),
            doneButton.heightAnchor.constraint(equalToConstant: 20),

            titleField.leadingAnchor.constraint(equalTo: doneButton.trailingAnchor, constant: 6),
            titleField.trailingAnchor.constraint(equalTo: colorButton.leadingAnchor, constant: -6),
            titleField.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            colorButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -4),
            colorButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            colorButton.widthAnchor.constraint(equalToConstant: 18),
            colorButton.heightAnchor.constraint(equalToConstant: 18),

            addButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -2),
            addButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 20),
            addButton.heightAnchor.constraint(equalToConstant: 20),

            deleteButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),

            separatorView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            separatorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: separatorView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            resizeGrip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            resizeGrip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            resizeGrip.widthAnchor.constraint(equalToConstant: 16),
            resizeGrip.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    // MARK: - Styling

    private func refreshAppearance() {
        layer?.backgroundColor = currentColor.bodyColor.cgColor
        layer?.borderColor = currentColor.borderColor.cgColor
        dragHandleBar.layer?.backgroundColor = currentColor.headerColor.cgColor
        dragHandleBar.pillColor = currentColor.borderColor.withAlphaComponent(0.55)
        headerView.layer?.backgroundColor = currentColor.headerColor.cgColor
        separatorView.layer?.backgroundColor = currentColor.borderColor.withAlphaComponent(0.35).cgColor

        let inkColor = isDone
            ? NSColor(calibratedWhite: 0.28, alpha: 0.65)
            : NSColor(calibratedWhite: 0.12, alpha: 0.96)
        let iconTint = NSColor(calibratedWhite: 0.18, alpha: isDone ? 0.65 : 0.85)

        doneButton.image = NSImage(
            systemSymbolName: isDone ? "checkmark.circle.fill" : "checkmark.circle",
            accessibilityDescription: isDone ? "Mark as not done" : "Mark as done"
        )
        doneButton.contentTintColor = isDone
            ? NSColor(calibratedRed: 0.15, green: 0.52, blue: 0.24, alpha: 0.95)
            : iconTint
        addButton.contentTintColor = iconTint
        deleteButton.contentTintColor = iconTint
        colorButton.image = makeColorDotImage(color: currentColor.swatchColor, size: 12)
        resizeGrip.lineColor = currentColor.borderColor.withAlphaComponent(0.55)

        window?.alphaValue = isDone ? 0.80 : 1.0

        applyTitleStyling(inkColor: inkColor)
        applyBodyStyling(inkColor: inkColor)
    }

    private func applyTitleStyling(inkColor: NSColor) {
        let placeholderAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 0.45),
        ]
        titleField.placeholderAttributedString = NSAttributedString(string: "Title...", attributes: placeholderAttrs)

        let titleText = titleField.stringValue
        var attrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: inkColor,
        ]
        if isDone {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = inkColor
        }
        // Only apply attributed string when not actively editing the field to avoid jumping the cursor
        if window?.firstResponder != titleField.currentEditor() {
            titleField.attributedStringValue = NSAttributedString(string: titleText, attributes: attrs)
        } else {
            titleField.font = titleFont
            titleField.textColor = inkColor
        }
    }

    private func applyBodyStyling(inkColor: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3

        var attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: inkColor,
            .paragraphStyle: paragraph,
        ]
        if isDone {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = inkColor
        }

        textView.typingAttributes = attrs

        guard let storage = textView.textStorage else { return }
        let selectedRanges = textView.selectedRanges
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(attrs, range: fullRange)
        storage.endEditing()
        textView.selectedRanges = selectedRanges
    }

    private func makeColorDotImage(color: NSColor, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let rect = NSRect(x: 1, y: 1, width: size - 2, height: size - 2)
        let path = NSBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()
        NSColor(calibratedWhite: 0.15, alpha: 0.4).setStroke()
        path.lineWidth = 1
        path.stroke()
        image.unlockFocus()
        return image
    }

    // MARK: - Actions

    @objc private func handleDoneToggle() {
        delegate?.stickyViewDidToggleDone()
    }

    @objc private func handleAdd() {
        delegate?.stickyViewDidRequestNewSticky()
    }

    @objc private func handleDelete() {
        delegate?.stickyViewDidRequestDelete()
    }

    @objc private func handleColorMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for color in StickyColor.allCases {
            let item = NSMenuItem(
                title: color.displayName,
                action: #selector(handleColorSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = color
            item.image = makeColorDotImage(color: color.swatchColor, size: 12)
            item.state = (color == currentColor) ? .on : .off
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func handleColorSelected(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? StickyColor else { return }
        delegate?.stickyViewDidSelectColor(color)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard !isUpdatingProgrammatically else { return }
        delegate?.stickyViewDidChangeTitle(titleField.stringValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let inkColor = isDone
            ? NSColor(calibratedWhite: 0.28, alpha: 0.65)
            : NSColor(calibratedWhite: 0.12, alpha: 0.96)
        applyTitleStyling(inkColor: inkColor)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !isUpdatingProgrammatically else { return }
        delegate?.stickyViewDidChangeBody(textView.string)
    }
}
