import AppKit

protocol DrawingToolbarDelegate: AnyObject {
    func drawingToolbarDidSelectTool(_ tool: DrawingTool)
    func drawingToolbarDidSelectColor(_ color: PenColor)
    func drawingToolbarDidChangeLineWidth(_ width: Double)
    func drawingToolbarDidRequestUndo()
    func drawingToolbarDidRequestClearAll()
    func drawingToolbarDidRequestDone()
}

/// Compact floating frosted-glass HUD pill for choosing pen/eraser, color, tip size, undo, and clear.
final class DrawingToolbarWindow: NSPanel {
    weak var toolbarDelegate: DrawingToolbarDelegate?

    private let penButton = ToolbarIconButton()
    private let eraserButton = ToolbarIconButton()
    private var colorSwatches: [PenColor: ColorSwatchView] = [:]
    private let sizePreviewDot = SizeDotView()
    private let sizeSlider = NSSlider()
    private let undoButton = ToolbarIconButton()
    private let clearButton = ToolbarIconButton()
    private let doneButton = NSButton()

    private var selectedTool: DrawingTool = .pen
    private var selectedColor: PenColor = .yellow
    private var selectedWidth: Double = DrawingStroke.defaultLineWidth

    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 570, height: 48)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        setupUI()
        refreshSelectionUI()
    }

    func showCenteredNearTop() {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let x = visible.midX - frame.width / 2
            let y = visible.maxY - frame.height - 20
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        orderFront(nil)
    }

    func updateState(tool: DrawingTool, color: PenColor, lineWidth: Double, canUndo: Bool, hasStrokes: Bool) {
        selectedTool = tool
        selectedColor = color
        selectedWidth = lineWidth
        sizeSlider.doubleValue = lineWidth
        undoButton.isEnabled = canUndo
        clearButton.isEnabled = hasStrokes
        refreshSelectionUI()
    }

    // MARK: - Setup

    private func setupUI() {
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        contentView = effectView

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        // Pen & Eraser buttons
        configureToolButton(penButton, symbol: "pencil.tip", tooltip: "Pen (P)", action: #selector(handlePen))
        configureToolButton(eraserButton, symbol: "eraser", tooltip: "Stroke Eraser (E)", action: #selector(handleEraser))
        stack.addArrangedSubview(penButton)
        stack.addArrangedSubview(eraserButton)
        stack.addArrangedSubview(makeSeparator())

        // Color swatches
        let swatchStack = NSStackView()
        swatchStack.orientation = .horizontal
        swatchStack.alignment = .centerY
        swatchStack.spacing = 6
        for color in PenColor.allCases {
            let swatch = ColorSwatchView(color: color)
            swatch.toolTip = color.displayName
            swatch.onSelect = { [weak self] picked in
                self?.selectColor(picked)
            }
            swatch.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                swatch.widthAnchor.constraint(equalToConstant: 20),
                swatch.heightAnchor.constraint(equalToConstant: 20),
            ])
            colorSwatches[color] = swatch
            swatchStack.addArrangedSubview(swatch)
        }
        stack.addArrangedSubview(swatchStack)
        stack.addArrangedSubview(makeSeparator())

        // Tip size preview + slider
        sizePreviewDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sizePreviewDot.widthAnchor.constraint(equalToConstant: 22),
            sizePreviewDot.heightAnchor.constraint(equalToConstant: 22),
        ])
        stack.addArrangedSubview(sizePreviewDot)

        sizeSlider.minValue = DrawingStroke.minLineWidth
        sizeSlider.maxValue = DrawingStroke.maxLineWidth
        sizeSlider.doubleValue = selectedWidth
        sizeSlider.controlSize = .small
        sizeSlider.target = self
        sizeSlider.action = #selector(handleSizeSlider(_:))
        sizeSlider.toolTip = "Pen / Eraser size ([ / ])"
        sizeSlider.translatesAutoresizingMaskIntoConstraints = false
        sizeSlider.widthAnchor.constraint(equalToConstant: 78).isActive = true
        stack.addArrangedSubview(sizeSlider)
        stack.addArrangedSubview(makeSeparator())

        // Undo & Clear
        configureActionButton(undoButton, symbol: "arrow.uturn.backward", tooltip: "Undo (⌘Z)", action: #selector(handleUndo))
        configureActionButton(clearButton, symbol: "trash", tooltip: "Clear All Drawings", action: #selector(handleClear))
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(clearButton)

        // Done pill button
        doneButton.title = "Done"
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .regular
        doneButton.keyEquivalent = "\u{1b}"
        doneButton.target = self
        doneButton.action = #selector(handleDone)
        doneButton.toolTip = "Exit Drawing Mode (Esc)"
        stack.addArrangedSubview(doneButton)
    }

    private func configureToolButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func configureActionButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .labelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    private func makeSeparator() -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sep.widthAnchor.constraint(equalToConstant: 1),
            sep.heightAnchor.constraint(equalToConstant: 22),
        ])
        return sep
    }

    private func refreshSelectionUI() {
        let accent = NSColor.controlAccentColor
        penButton.layer?.backgroundColor = (selectedTool == .pen) ? accent.withAlphaComponent(0.85).cgColor : NSColor.clear.cgColor
        penButton.contentTintColor = (selectedTool == .pen) ? .white : .labelColor

        eraserButton.layer?.backgroundColor = (selectedTool == .eraser) ? accent.withAlphaComponent(0.85).cgColor : NSColor.clear.cgColor
        eraserButton.contentTintColor = (selectedTool == .eraser) ? .white : .labelColor

        for (color, swatch) in colorSwatches {
            swatch.isSelected = (selectedTool == .pen && selectedColor == color)
        }

        sizePreviewDot.dotDiameter = min(max(CGFloat(selectedWidth), 4), 18)
        sizePreviewDot.dotColor = (selectedTool == .eraser) ? NSColor.white.withAlphaComponent(0.75) : selectedColor.nsColor
    }

    // MARK: - Actions

    @objc private func handlePen() {
        selectedTool = .pen
        refreshSelectionUI()
        toolbarDelegate?.drawingToolbarDidSelectTool(.pen)
    }

    @objc private func handleEraser() {
        selectedTool = .eraser
        refreshSelectionUI()
        toolbarDelegate?.drawingToolbarDidSelectTool(.eraser)
    }

    private func selectColor(_ color: PenColor) {
        selectedColor = color
        selectedTool = .pen
        refreshSelectionUI()
        toolbarDelegate?.drawingToolbarDidSelectTool(.pen)
        toolbarDelegate?.drawingToolbarDidSelectColor(color)
    }

    @objc private func handleSizeSlider(_ sender: NSSlider) {
        selectedWidth = DrawingStroke.clampedLineWidth(sender.doubleValue)
        refreshSelectionUI()
        toolbarDelegate?.drawingToolbarDidChangeLineWidth(selectedWidth)
    }

    @objc private func handleUndo() {
        toolbarDelegate?.drawingToolbarDidRequestUndo()
    }

    @objc private func handleClear() {
        toolbarDelegate?.drawingToolbarDidRequestClearAll()
    }

    @objc private func handleDone() {
        toolbarDelegate?.drawingToolbarDidRequestDone()
    }
}

private final class ToolbarIconButton: NSButton {
    override var mouseDownCanMoveWindow: Bool { false }
}

private final class ColorSwatchView: NSView {
    let color: PenColor
    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }
    var onSelect: ((PenColor) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    init(color: PenColor) {
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(color)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let size = min(bounds.width, bounds.height)
        if isSelected {
            let ring = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: size - 2, height: size - 2))
            NSColor.white.setStroke()
            ring.lineWidth = 2.0
            ring.stroke()
        }
        let inset: CGFloat = isSelected ? 4 : 3
        let dot = NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2))
        color.nsColor.setFill()
        dot.fill()
        NSColor.black.withAlphaComponent(0.28).setStroke()
        dot.lineWidth = 0.8
        dot.stroke()
    }
}

private final class SizeDotView: NSView {
    var dotDiameter: CGFloat = 6 {
        didSet { needsDisplay = true }
    }
    var dotColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let d = min(dotDiameter, min(bounds.width, bounds.height) - 2)
        let rect = NSRect(
            x: (bounds.width - d) / 2,
            y: (bounds.height - d) / 2,
            width: d,
            height: d
        )
        let path = NSBezierPath(ovalIn: rect)
        dotColor.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }
}
