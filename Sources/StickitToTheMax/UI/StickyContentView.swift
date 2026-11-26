import AppKit

enum StickyResizeEdge {
    case bottomRight
    case bottomLeft
    case right
    case bottom
    case left
}

protocol StickyContentViewDelegate: AnyObject {
    func stickyViewDidChangeTitle(_ title: String)
    func stickyViewDidChangeBody(_ body: String)
    func stickyViewDidToggleDone()
    func stickyViewDidSelectColor(_ color: StickyColor)
    func stickyViewDidRequestNewSticky()
    func stickyViewDidRequestDelete()
    func stickyViewDidBeginMove()
    func stickyViewDidDragMove(deltaX: CGFloat, deltaY: CGFloat)
    func stickyViewDidEndMove()
    func stickyViewDidBeginResize(edge: StickyResizeEdge)
    func stickyViewDidDragResize(edge: StickyResizeEdge, deltaX: CGFloat, deltaY: CGFloat)
    func stickyViewDidEndResize()
}

/// Crisp custom diagonal resize cursors using standard AppKit drawing (no private APIs).
private enum ResizeCursors {
    static let diagonalNWSE: NSCursor = makeDiagonalCursor(nwToSE: true)
    static let diagonalNESW: NSCursor = makeDiagonalCursor(nwToSE: false)

    private static func makeDiagonalCursor(nwToSE: Bool) -> NSCursor {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: size / 2, yBy: size / 2)
        transform.rotate(byDegrees: nwToSE ? -45 : 45)
        transform.concat()

        // Double-headed horizontal arrow rotated ±45°
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: -7, y: 0))
        arrow.line(to: NSPoint(x: -3, y: 3.5))
        arrow.line(to: NSPoint(x: -3, y: 1.2))
        arrow.line(to: NSPoint(x: 3, y: 1.2))
        arrow.line(to: NSPoint(x: 3, y: 3.5))
        arrow.line(to: NSPoint(x: 7, y: 0))
        arrow.line(to: NSPoint(x: 3, y: -3.5))
        arrow.line(to: NSPoint(x: 3, y: -1.2))
        arrow.line(to: NSPoint(x: -3, y: -1.2))
        arrow.line(to: NSPoint(x: -3, y: -3.5))
        arrow.close()

        NSColor.white.setStroke()
        arrow.lineWidth = 2.2
        arrow.lineJoinStyle = .round
        arrow.stroke()

        NSColor.black.setFill()
        arrow.fill()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }
}

/// Shared drag-tracking helper for smooth group-aware window moving.
private func runMoveDragLoop(
    window: NSWindow,
    onBegin: () -> Void,
    onDrag: (CGFloat, CGFloat) -> Void,
    onEnd: () -> Void
) {
    let startMouse = NSEvent.mouseLocation
    onBegin()
    NSCursor.closedHand.push()
    defer {
        NSCursor.pop()
        onEnd()
    }

    while let nextEvent = window.nextEvent(
        matching: [.leftMouseDragged, .leftMouseUp],
        until: .distantFuture,
        inMode: .eventTracking,
        dequeue: true
    ) {
        switch nextEvent.type {
        case .leftMouseDragged:
            let current = NSEvent.mouseLocation
            onDrag(current.x - startMouse.x, current.y - startMouse.y)
        case .leftMouseUp:
            return
        default:
            break
        }
    }
}

/// Dedicated top grab bar with a centered macOS-style pill indicator and open-hand cursor.
private final class DragHandleBarView: NSView {
    var pillColor: NSColor = NSColor(calibratedWhite: 0.2, alpha: 0.35) {
        didSet { needsDisplay = true }
    }
    var onBeginMove: (() -> Void)?
    var onDragMove: ((CGFloat, CGFloat) -> Void)?
    var onEndMove: (() -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let pillWidth: CGFloat = 38
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
        guard let window else { return }
        runMoveDragLoop(
            window: window,
            onBegin: { self.onBeginMove?() },
            onDrag: { dx, dy in self.onDragMove?(dx, dy) },
            onEnd: { self.onEndMove?() }
        )
    }
}

/// Header strip that initiates group-aware window dragging when dragged outside interactive controls.
private final class DraggableHeaderView: NSView {
    var onBeginMove: (() -> Void)?
    var onDragMove: ((CGFloat, CGFloat) -> Void)?
    var onEndMove: (() -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        runMoveDragLoop(
            window: window,
            onBegin: { self.onBeginMove?() },
            onDrag: { dx, dy in self.onDragMove?(dx, dy) },
            onEnd: { self.onEndMove?() }
        )
    }
}

/// Title field that drags the sticky (or selected group) on drag, and edits on a plain click.
private final class DraggableTitleField: NSTextField {
    var onBeginMove: (() -> Void)?
    var onDragMove: ((CGFloat, CGFloat) -> Void)?
    var onEndMove: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if currentEditor() != nil {
            super.mouseDown(with: event)
            return
        }

        guard let window else {
            super.mouseDown(with: event)
            return
        }

        let startWindowLoc = event.locationInWindow
        let startMouse = NSEvent.mouseLocation
        let dragThreshold: CGFloat = 3.0
        var isDragging = false

        while let nextEvent = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .leftMouseDragged:
                let dx = nextEvent.locationInWindow.x - startWindowLoc.x
                let dy = nextEvent.locationInWindow.y - startWindowLoc.y
                if !isDragging && hypot(dx, dy) >= dragThreshold {
                    isDragging = true
                    onBeginMove?()
                    NSCursor.closedHand.push()
                }
                if isDragging {
                    let current = NSEvent.mouseLocation
                    onDragMove?(current.x - startMouse.x, current.y - startMouse.y)
                }
            case .leftMouseUp:
                if isDragging {
                    NSCursor.pop()
                    onEndMove?()
                } else {
                    window.makeFirstResponder(self)
                }
                return
            default:
                break
            }
        }
    }
}

/// Prominent, easy-to-grab bottom-right resize corner with hover feedback and diagonal cursor.
private final class ResizeCornerView: NSView {
    var gripColor: NSColor = NSColor(calibratedWhite: 0.2, alpha: 0.55) {
        didSet { needsDisplay = true }
    }
    var badgeColor: NSColor = NSColor(calibratedWhite: 0.0, alpha: 0.06) {
        didSet { needsDisplay = true }
    }
    var onBeginResize: (() -> Void)?
    var onDragResize: ((CGFloat, CGFloat) -> Void)?
    var onEndResize: (() -> Void)?

    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: ResizeCursors.diagonalNWSE)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Subtle corner triangle background so the resize spot is immediately visible
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: bounds.maxX, y: bounds.minY))
        triangle.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        triangle.line(to: NSPoint(x: bounds.minX, y: bounds.minY))
        triangle.close()
        badgeColor.withAlphaComponent(isHovered ? 0.16 : 0.08).setFill()
        triangle.fill()

        // 3 clear diagonal grip lines
        gripColor.withAlphaComponent(isHovered ? 0.95 : 0.65).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round

        let offsets: [CGFloat] = [5, 10, 15]
        for offset in offsets {
            path.move(to: NSPoint(x: bounds.maxX - offset, y: 4))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: offset))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let startMouse = NSEvent.mouseLocation
        onBeginResize?()
        ResizeCursors.diagonalNWSE.push()
        defer {
            NSCursor.pop()
            onEndResize?()
        }

        while let nextEvent = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .leftMouseDragged:
                let current = NSEvent.mouseLocation
                onDragResize?(current.x - startMouse.x, startMouse.y - current.y)
            case .leftMouseUp:
                return
            default:
                break
            }
        }
    }
}

/// Invisible generous edge/corner hit zone for effortless resizing from edges too.
private final class ResizeEdgeHitView: NSView {
    let edge: StickyResizeEdge
    var onBeginResize: ((StickyResizeEdge) -> Void)?
    var onDragResize: ((StickyResizeEdge, CGFloat, CGFloat) -> Void)?
    var onEndResize: (() -> Void)?

    init(edge: StickyResizeEdge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var resizeCursor: NSCursor {
        switch edge {
        case .left, .right:
            return .resizeLeftRight
        case .bottom:
            return .resizeUpDown
        case .bottomRight:
            return ResizeCursors.diagonalNWSE
        case .bottomLeft:
            return ResizeCursors.diagonalNESW
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: resizeCursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let startMouse = NSEvent.mouseLocation
        onBeginResize?(edge)
        resizeCursor.push()
        defer {
            NSCursor.pop()
            onEndResize?()
        }

        while let nextEvent = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .leftMouseDragged:
                let current = NSEvent.mouseLocation
                onDragResize?(edge, current.x - startMouse.x, startMouse.y - current.y)
            case .leftMouseUp:
                return
            default:
                break
            }
        }
    }
}

/// Image view whose intrinsicContentSize does not lock window resizing to the image's pixel dimensions.
private final class StickyImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

final class StickyContentView: NSView, NSTextFieldDelegate, NSTextViewDelegate {
    static let chromeHeight: CGFloat = 45

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
    private let imageView = StickyImageView()

    private var doneButtonWidthConstraint: NSLayoutConstraint?
    private var titleLeadingConstraint: NSLayoutConstraint?

    private let resizeCorner = ResizeCornerView()
    private let rightEdgeHit = ResizeEdgeHitView(edge: .right)
    private let bottomEdgeHit = ResizeEdgeHitView(edge: .bottom)
    private let leftEdgeHit = ResizeEdgeHitView(edge: .left)
    private let bottomLeftHit = ResizeEdgeHitView(edge: .bottomLeft)

    private var currentColor: StickyColor = .yellow
    private var isDone: Bool = false
    private var isImageSticky: Bool = false
    private var isSelected: Bool = false
    private var currentFontSize: Double = StickyNote.defaultFontSize
    private var displayScale: CGFloat = 1.0
    private var isUpdatingProgrammatically = false

    private var bodyFont: NSFont {
        let scaled = max(9.5, CGFloat(currentFontSize) * displayScale)
        return NSFont.systemFont(ofSize: scaled, weight: .regular)
    }

    private var titleFont: NSFont {
        let base = min(max(currentFontSize * 0.93, 12.0), 18.0)
        let scaled = max(10.0, CGFloat(base) * displayScale)
        return NSFont.systemFont(ofSize: scaled, weight: .semibold)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        setupHeader()
        setupBody()
        setupResizeHandles()
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
        isImageSticky = note.isImageSticky
        currentFontSize = note.fontSize

        if titleField.stringValue != note.title {
            titleField.stringValue = note.title
        }
        if !isImageSticky && textView.string != note.body {
            textView.string = note.body
        }

        scrollView.isHidden = isImageSticky
        imageView.isHidden = !isImageSticky
        doneButton.isHidden = isImageSticky
        doneButtonWidthConstraint?.constant = isImageSticky ? 0 : 20
        titleLeadingConstraint?.constant = isImageSticky ? 2 : 6

        refreshAppearance()
    }

    func setImage(_ image: NSImage?) {
        imageView.image = image
    }

    func setDisplayScale(_ scale: CGFloat) {
        let clamped = min(max(scale, 0.5), 1.0)
        guard abs(displayScale - clamped) > 0.01 else { return }
        displayScale = clamped
        refreshAppearance()
    }

    func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        refreshBorderAppearance()
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
        dragHandleBar.onBeginMove = { [weak self] in self?.delegate?.stickyViewDidBeginMove() }
        dragHandleBar.onDragMove = { [weak self] dx, dy in self?.delegate?.stickyViewDidDragMove(deltaX: dx, deltaY: dy) }
        dragHandleBar.onEndMove = { [weak self] in self?.delegate?.stickyViewDidEndMove() }
        addSubview(dragHandleBar)

        headerView.wantsLayer = true
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.onBeginMove = { [weak self] in self?.delegate?.stickyViewDidBeginMove() }
        headerView.onDragMove = { [weak self] dx, dy in self?.delegate?.stickyViewDidDragMove(deltaX: dx, deltaY: dy) }
        headerView.onEndMove = { [weak self] in self?.delegate?.stickyViewDidEndMove() }
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
        titleField.onBeginMove = { [weak self] in self?.delegate?.stickyViewDidBeginMove() }
        titleField.onDragMove = { [weak self] dx, dy in self?.delegate?.stickyViewDidDragMove(deltaX: dx, deltaY: dy) }
        titleField.onEndMove = { [weak self] in self?.delegate?.stickyViewDidEndMove() }

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

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.isHidden = true
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.92).cgColor
        imageView.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        imageView.setContentCompressionResistancePriority(.init(1), for: .vertical)
        imageView.setContentHuggingPriority(.init(1), for: .horizontal)
        imageView.setContentHuggingPriority(.init(1), for: .vertical)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
    }

    private func setupResizeHandles() {
        for edgeView in [rightEdgeHit, bottomEdgeHit, leftEdgeHit, bottomLeftHit] {
            edgeView.translatesAutoresizingMaskIntoConstraints = false
            edgeView.onBeginResize = { [weak self] edge in
                self?.delegate?.stickyViewDidBeginResize(edge: edge)
            }
            edgeView.onDragResize = { [weak self] edge, dx, dy in
                self?.delegate?.stickyViewDidDragResize(edge: edge, deltaX: dx, deltaY: dy)
            }
            edgeView.onEndResize = { [weak self] in
                self?.delegate?.stickyViewDidEndResize()
            }
            addSubview(edgeView)
        }

        resizeCorner.toolTip = "Drag to resize sticky"
        resizeCorner.translatesAutoresizingMaskIntoConstraints = false
        resizeCorner.onBeginResize = { [weak self] in
            self?.delegate?.stickyViewDidBeginResize(edge: .bottomRight)
        }
        resizeCorner.onDragResize = { [weak self] dx, dy in
            self?.delegate?.stickyViewDidDragResize(edge: .bottomRight, deltaX: dx, deltaY: dy)
        }
        resizeCorner.onEndResize = { [weak self] in
            self?.delegate?.stickyViewDidEndResize()
        }
        addSubview(resizeCorner)
    }

    private func setupLayout() {
        let edgeThickness: CGFloat = 8
        let cornerSize: CGFloat = 24

        let doneWidth = doneButton.widthAnchor.constraint(equalToConstant: 20)
        doneButtonWidthConstraint = doneWidth
        let titleLead = titleField.leadingAnchor.constraint(equalTo: doneButton.trailingAnchor, constant: 6)
        titleLeadingConstraint = titleLead

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
            doneWidth,
            doneButton.heightAnchor.constraint(equalToConstant: 20),

            titleLead,
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

            imageView.topAnchor.constraint(equalTo: separatorView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Generous invisible resize hit zones along left, right, bottom edges
            rightEdgeHit.topAnchor.constraint(equalTo: separatorView.bottomAnchor),
            rightEdgeHit.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightEdgeHit.bottomAnchor.constraint(equalTo: resizeCorner.topAnchor),
            rightEdgeHit.widthAnchor.constraint(equalToConstant: edgeThickness),

            leftEdgeHit.topAnchor.constraint(equalTo: separatorView.bottomAnchor),
            leftEdgeHit.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftEdgeHit.bottomAnchor.constraint(equalTo: bottomLeftHit.topAnchor),
            leftEdgeHit.widthAnchor.constraint(equalToConstant: edgeThickness),

            bottomEdgeHit.leadingAnchor.constraint(equalTo: bottomLeftHit.trailingAnchor),
            bottomEdgeHit.trailingAnchor.constraint(equalTo: resizeCorner.leadingAnchor),
            bottomEdgeHit.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomEdgeHit.heightAnchor.constraint(equalToConstant: edgeThickness),

            bottomLeftHit.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomLeftHit.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomLeftHit.widthAnchor.constraint(equalToConstant: 16),
            bottomLeftHit.heightAnchor.constraint(equalToConstant: 16),

            // Prominent bottom-right resize corner
            resizeCorner.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeCorner.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeCorner.widthAnchor.constraint(equalToConstant: cornerSize),
            resizeCorner.heightAnchor.constraint(equalToConstant: cornerSize),
        ])
    }

    // MARK: - Styling

    private func refreshAppearance() {
        layer?.backgroundColor = currentColor.bodyColor.cgColor
        dragHandleBar.layer?.backgroundColor = currentColor.headerColor.cgColor
        dragHandleBar.pillColor = currentColor.borderColor.withAlphaComponent(0.60)
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

        resizeCorner.gripColor = currentColor.borderColor.blended(withFraction: 0.35, of: .black) ?? currentColor.borderColor
        resizeCorner.badgeColor = currentColor.borderColor

        window?.alphaValue = isDone ? 0.80 : 1.0

        refreshBorderAppearance()
        applyTitleStyling(inkColor: inkColor)
        applyBodyStyling(inkColor: inkColor)
    }

    private func refreshBorderAppearance() {
        if isSelected {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 2.5
        } else {
            layer?.borderColor = currentColor.borderColor.cgColor
            layer?.borderWidth = 1.0
        }
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
        titleField.font = titleFont
        titleField.textColor = inkColor
        if window?.firstResponder != titleField.currentEditor() {
            titleField.attributedStringValue = NSAttributedString(string: titleText, attributes: attrs)
        } else if let editor = titleField.currentEditor() as? NSTextView {
            editor.textColor = inkColor
            editor.insertionPointColor = inkColor
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
