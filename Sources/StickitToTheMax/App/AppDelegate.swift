import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, StickyWindowControllerDelegate, DrawingCanvasOverlayDelegate, DrawingToolbarDelegate {
    private let store: StickyStore
    private let drawingStore: DrawingStore
    private var statusItem: NSStatusItem?
    private var controllers: [UUID: StickyWindowController] = [:]
    private var notes: [StickyNote] = []
    private var stickiesVisible = true

    // Wallpaper drawing & multi-monitor layout state
    private let drawingCanvas = DrawingCanvasOverlay()
    private let drawingToolbar = DrawingToolbarWindow()
    private var displayTransform: CanvasTransform = .identity
    private var drawHotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?

    // Multi-selection & group drag/resize state
    private var selectedIDs: Set<UUID> = []
    private var activeGroupFrames: [UUID: NSRect] = [:]
    private let marqueeOverlay = MarqueeSelectionOverlay()
    private var marqueeAnchor: NSPoint?
    private var marqueeBaseSelection: Set<UUID> = []
    private var globalMouseMonitor: Any?
    private var localMouseUpMonitor: Any?

    override init() {
        self.store = StickyStore()
        self.drawingStore = DrawingStore()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        drawingCanvas.delegate = self
        drawingToolbar.toolbarDelegate = self

        setupEditMenu()
        setupStatusItem()
        loadInitialNotes()
        loadInitialDrawings()
        refreshDisplayTransform()
        observeScreenChanges()
        installDesktopMarqueeMonitor()
        registerDrawingHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterDrawingHotKey()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseUpMonitor {
            NSEvent.removeMonitor(localMouseUpMonitor)
            self.localMouseUpMonitor = nil
        }
        store.saveImmediately(notes)
        drawingStore.saveImmediately(drawingCanvas.strokes)
    }

    // MARK: - Edit Menu (enables Cmd+C/V/X/A/Z in LSUIElement accessory apps)

    private func setupEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "StickitToTheMax")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "StickitToTheMax — Wallpaper Stickies"
        }
        statusItem = item
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "StickitToTheMax", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let newStickyItem = NSMenuItem(title: "New Sticky", action: #selector(handleNewDefaultSticky), keyEquivalent: "n")
        newStickyItem.target = self
        menu.addItem(newStickyItem)

        let newPictureItem = NSMenuItem(title: "New Picture Sticky…", action: #selector(handleNewPictureSticky), keyEquivalent: "i")
        newPictureItem.target = self
        menu.addItem(newPictureItem)

        let pastePictureItem = NSMenuItem(title: "Paste Picture Sticky", action: #selector(handlePastePictureSticky), keyEquivalent: "")
        pastePictureItem.target = self
        pastePictureItem.isEnabled = clipboardHasImage()
        menu.addItem(pastePictureItem)

        let presetRoot = NSMenuItem(title: "New with Category", action: nil, keyEquivalent: "")
        let presetMenu = NSMenu()
        for preset in StickyPreset.defaults {
            let item = NSMenuItem(
                title: "\(preset.title) (\(preset.color.displayName))",
                action: #selector(handleNewPresetSticky(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset
            presetMenu.addItem(item)
        }
        presetRoot.submenu = presetMenu
        menu.addItem(presetRoot)

        menu.addItem(.separator())

        let drawItem = NSMenuItem(
            title: drawingCanvas.isDrawingMode ? "Exit Drawing Mode" : "Draw on Wallpaper",
            action: #selector(handleToggleDrawingMode),
            keyEquivalent: "d"
        )
        drawItem.keyEquivalentModifierMask = [.option, .shift]
        drawItem.target = self
        drawItem.state = drawingCanvas.isDrawingMode ? .on : .off
        menu.addItem(drawItem)

        if !drawingCanvas.strokes.isEmpty {
            let clearDrawingsItem = NSMenuItem(
                title: "Clear All Drawings (\(drawingCanvas.strokes.count))",
                action: #selector(handleClearAllDrawings),
                keyEquivalent: ""
            )
            clearDrawingsItem.target = self
            menu.addItem(clearDrawingsItem)
        }

        menu.addItem(.separator())

        if notes.isEmpty {
            let emptyItem = NSMenuItem(title: "No stickies on wallpaper", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            let activeCount = notes.filter { !$0.isDone }.count
            let doneCount = notes.count - activeCount
            let summaryTitle = doneCount > 0
                ? "Stickies: \(activeCount) active, \(doneCount) done"
                : "Stickies: \(activeCount) active"
            let summaryItem = NSMenuItem(title: summaryTitle, action: nil, keyEquivalent: "")
            summaryItem.isEnabled = false
            menu.addItem(summaryItem)

            if doneCount > 0 {
                let clearDoneItem = NSMenuItem(
                    title: "Delete All Done Stickies (\(doneCount))",
                    action: #selector(handleDeleteAllDone),
                    keyEquivalent: ""
                )
                clearDoneItem.target = self
                menu.addItem(clearDoneItem)
            }
        }

        menu.addItem(.separator())

        let toggleVisibilityItem = NSMenuItem(
            title: stickiesVisible ? "Hide All Stickies" : "Show All Stickies",
            action: #selector(handleToggleVisibility),
            keyEquivalent: ""
        )
        toggleVisibilityItem.target = self
        menu.addItem(toggleVisibilityItem)

        let loginStatus = SMAppService.mainApp.status
        let loginTitle = loginStatus == .requiresApproval
            ? "Launch at Login (Approve in Settings…)"
            : "Launch at Login"
        let launchAtLoginItem = NSMenuItem(
            title: loginTitle,
            action: #selector(handleToggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = (loginStatus == .enabled) ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit StickitToTheMax", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        let loginStatus = SMAppService.mainApp.status
        if let item = menu.items.first(where: { $0.action == #selector(handleToggleLaunchAtLogin) }) {
            item.title = loginStatus == .requiresApproval
                ? "Launch at Login (Approve in Settings…)"
                : "Launch at Login"
            item.state = (loginStatus == .enabled) ? .on : .off
        }
        if let pasteItem = menu.items.first(where: { $0.action == #selector(handlePastePictureSticky) }) {
            pasteItem.isEnabled = clipboardHasImage()
        }
    }

    // MARK: - Selection Management

    private func updateSelection(_ newSelection: Set<UUID>) {
        guard newSelection != selectedIDs else { return }
        selectedIDs = newSelection
        for (id, controller) in controllers {
            controller.setSelected(selectedIDs.contains(id))
        }
    }

    private func clearSelection() {
        updateSelection([])
    }

    private func targetIDs(for initiatorID: UUID) -> [UUID] {
        if selectedIDs.contains(initiatorID), selectedIDs.count > 1 {
            return Array(selectedIDs)
        }
        return [initiatorID]
    }

    // MARK: - Desktop Marquee Selection

    private func installDesktopMarqueeMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            if Thread.isMainThread {
                self?.handleGlobalMouseEvent(event)
            } else {
                DispatchQueue.main.async {
                    self?.handleGlobalMouseEvent(event)
                }
            }
        }

        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.finishMarqueeIfActive()
            return event
        }
    }

    private func finishMarqueeIfActive() {
        if marqueeAnchor != nil {
            marqueeAnchor = nil
            marqueeBaseSelection = []
            marqueeOverlay.hide()
        }
    }

    private func handleGlobalMouseEvent(_ event: NSEvent) {
        guard stickiesVisible, !drawingCanvas.isDrawingMode else { return }
        let location = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            // Ignore clicks over any sticky or over any normal app window
            let isOverSticky = controllers.values.contains { controller in
                controller.window?.frame.contains(location) == true
            }
            if isOverSticky || DesktopHitTest.isPointOverNormalWindow(location) {
                finishMarqueeIfActive()
                return
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCommandHeld = flags.contains(.command)
            marqueeAnchor = location
            marqueeBaseSelection = isCommandHeld ? selectedIDs : []
            if !isCommandHeld && !selectedIDs.isEmpty {
                clearSelection()
            }

        case .leftMouseDragged:
            guard let anchor = marqueeAnchor else { return }
            if (NSEvent.pressedMouseButtons & 1) == 0 {
                finishMarqueeIfActive()
                return
            }

            let dx = abs(location.x - anchor.x)
            let dy = abs(location.y - anchor.y)
            guard dx > 4 || dy > 4 else { return }

            let rect = NSRect(
                x: min(anchor.x, location.x),
                y: min(anchor.y, location.y),
                width: dx,
                height: dy
            )
            marqueeOverlay.update(screenRect: rect)

            var hitIDs = marqueeBaseSelection
            for (id, controller) in controllers {
                if let frame = controller.window?.frame, frame.intersects(rect) {
                    hitIDs.insert(id)
                }
            }
            updateSelection(hitIDs)

        case .leftMouseUp:
            finishMarqueeIfActive()

        default:
            break
        }
    }

    // MARK: - Loading & Lifecycle

    private func loadInitialNotes() {
        if let saved = store.load() {
            notes = saved
        } else {
            notes = makeStarterNotes()
            store.saveImmediately(notes)
        }

        for note in notes {
            spawnController(for: note, focus: false)
        }
        rebuildStatusMenu()
    }

    private func makeStarterNotes() -> [StickyNote] {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 36
        let width = CGFloat(StickyNote.defaultWidth)
        let height = CGFloat(StickyNote.defaultHeight)

        let workFrame = StickyFrame(rect: NSRect(
            x: screenFrame.maxX - width - margin,
            y: screenFrame.maxY - height - margin,
            width: width,
            height: height
        ))

        let personalFrame = StickyFrame(rect: NSRect(
            x: screenFrame.maxX - width - margin,
            y: screenFrame.maxY - (height * 2) - margin - 20,
            width: width,
            height: height
        ))

        return [
            StickyNote(
                title: "Work",
                body: "• Review project priorities\n• Reply to team updates\n• Prepare sprint notes",
                color: .blue,
                frame: workFrame
            ),
            StickyNote(
                title: "Personal",
                body: "• Groceries & errands\n• Evening workout\n• Click ✓ above to cross off when done!",
                color: .yellow,
                frame: personalFrame
            ),
        ]
    }

    private func loadInitialDrawings() {
        let savedStrokes = drawingStore.load()
        drawingCanvas.setStrokes(savedStrokes)
        rebuildStatusMenu()
    }

    private func spawnController(for note: StickyNote, focus: Bool) {
        let image: NSImage?
        if let filename = note.imageFilename {
            image = NSImage(contentsOf: store.imageURL(for: filename))
        } else {
            image = nil
        }
        let controller = StickyWindowController(note: note, image: image)
        controller.delegate = self
        controllers[note.id] = controller
        controller.applyDisplayTransform(displayTransform)
        if stickiesVisible {
            controller.showOnDesktop(focus: focus)
        }
    }

    private func nextPlacementFrame(near reference: StickyNote? = nil) -> StickyFrame {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = CGFloat(StickyNote.defaultWidth)
        let height = CGFloat(StickyNote.defaultHeight)

        var origin: NSPoint
        if let ref = reference {
            origin = NSPoint(x: CGFloat(ref.frame.x) - 28, y: CGFloat(ref.frame.y) - 28)
        } else {
            let offset = CGFloat(notes.count % 8) * 26
            origin = NSPoint(
                x: screenFrame.maxX - width - 48 - offset,
                y: screenFrame.maxY - height - 48 - offset
            )
        }

        origin.x = min(max(origin.x, screenFrame.minX + 16), screenFrame.maxX - width - 16)
        origin.y = min(max(origin.y, screenFrame.minY + 16), screenFrame.maxY - height - 16)

        let displayRect = NSRect(origin: origin, size: NSSize(width: width, height: height))
        let canonicalRect = displayTransform.invert(displayRect)
        return StickyFrame(rect: canonicalRect)
    }

    private func createSticky(title: String, color: StickyColor, near reference: StickyNote? = nil) {
        let frame = nextPlacementFrame(near: reference)
        let note = StickyNote(title: title, body: "", color: color, frame: frame)
        notes.append(note)
        stickiesVisible = true
        clearSelection()
        spawnController(for: note, focus: true)
        store.scheduleSave(notes)
        rebuildStatusMenu()
    }

    private func createPictureSticky(image: NSImage, filename: String, title: String) {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = StickyGeometry.initialImageStickySize(imageSize: image.size)
        let offset = CGFloat(notes.count % 8) * 26
        var origin = NSPoint(
            x: screenFrame.midX - size.width / 2 + offset,
            y: screenFrame.midY - size.height / 2 - offset
        )
        origin.x = min(max(origin.x, screenFrame.minX + 16), screenFrame.maxX - size.width - 16)
        origin.y = min(max(origin.y, screenFrame.minY + 16), screenFrame.maxY - size.height - 16)

        let displayRect = NSRect(origin: origin, size: size)
        let canonicalRect = displayTransform.invert(displayRect)
        let note = StickyNote(
            title: title,
            body: "",
            color: .yellow,
            imageFilename: filename,
            frame: StickyFrame(rect: canonicalRect)
        )
        notes.append(note)
        stickiesVisible = true
        clearSelection()
        spawnController(for: note, focus: false)
        store.scheduleSave(notes)
        rebuildStatusMenu()
    }

    private func removeSticky(id: UUID) {
        selectedIDs.remove(id)
        if let removed = notes.first(where: { $0.id == id }) {
            store.deleteImage(filename: removed.imageFilename)
        }
        if let controller = controllers.removeValue(forKey: id) {
            controller.window?.orderOut(nil)
            controller.close()
        }
        notes.removeAll { $0.id == id }
        store.scheduleSave(notes)
        rebuildStatusMenu()
    }

    // MARK: - Screen Changes

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleScreenParametersChanged() {
        refreshDisplayTransform()
        // macOS WindowServer sometimes finishes repositioning windows slightly after
        // didChangeScreenParametersNotification fires; re-apply once more to lock alignment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshDisplayTransform()
        }
    }

    /// Maps the canonical layout (stickies + drawings together) uniformly onto the current
    /// monitor setup without destructively overwriting saved positions. Switching back to a
    /// larger monitor restores the exact original layout.
    private func refreshDisplayTransform() {
        let screens = NSScreen.screens
        guard let fallback = NSScreen.main ?? screens.first else { return }
        let visibleFrames = screens.map(\.visibleFrame)

        let nextTransform = CanvasTransform.fit(
            notes: notes,
            strokes: drawingCanvas.strokes,
            visibleScreenFrames: visibleFrames,
            fallbackVisibleFrame: fallback.visibleFrame
        )
        displayTransform = nextTransform

        drawingCanvas.syncFrameToScreens()
        drawingCanvas.displayTransform = nextTransform
        for controller in controllers.values {
            controller.applyDisplayTransform(nextTransform)
        }
    }

    // MARK: - Menu Actions

    @objc private func handleNewDefaultSticky() {
        createSticky(title: "", color: .yellow)
    }

    @objc private func handleNewPictureSticky() {
        setDrawingMode(false)
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Choose a Picture for Your Sticky"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else { return }

        do {
            let filename = try store.importImage(from: url)
            let title = url.deletingPathExtension().lastPathComponent
            createPictureSticky(image: image, filename: filename, title: title)
        } catch {
            NSLog("StickitToTheMax: Failed to import image: %@", error.localizedDescription)
        }
    }

    private func clipboardHasImage() -> Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    @objc private func handlePastePictureSticky() {
        guard let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              let image = images.first,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return
        }
        setDrawingMode(false)
        do {
            let filename = try store.saveImageData(pngData, fileExtension: "png")
            createPictureSticky(image: image, filename: filename, title: "Picture")
        } catch {
            NSLog("StickitToTheMax: Failed to save pasted image: %@", error.localizedDescription)
        }
    }

    @objc private func handleToggleDrawingMode() {
        setDrawingMode(!drawingCanvas.isDrawingMode)
    }

    // MARK: - Global Hotkey (Option + Shift + D)

    private func registerDrawingHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.handleToggleDrawingMode()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &hotKeyHandlerRef
        )
        guard status == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: 0x53544D58, id: 1) // "STMX"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(optionKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &drawHotKeyRef
        )
    }

    private func unregisterDrawingHotKey() {
        if let drawHotKeyRef {
            UnregisterEventHotKey(drawHotKeyRef)
            self.drawHotKeyRef = nil
        }
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
    }

    @objc private func handleClearAllDrawings() {
        drawingCanvas.clearAll()
        syncDrawingToolbarState()
        rebuildStatusMenu()
    }

    private func setDrawingMode(_ enabled: Bool) {
        if enabled {
            if !stickiesVisible {
                stickiesVisible = true
                for controller in controllers.values {
                    controller.showOnDesktop(focus: false)
                }
            }
            clearSelection()
            finishMarqueeIfActive()
            drawingCanvas.isDrawingMode = true
            syncDrawingToolbarState()
            drawingToolbar.showCenteredNearTop()
        } else {
            drawingCanvas.isDrawingMode = false
            drawingToolbar.orderOut(nil)
        }
        rebuildStatusMenu()
    }

    private func syncDrawingToolbarState() {
        drawingToolbar.updateState(
            tool: drawingCanvas.tool,
            color: drawingCanvas.penColor,
            lineWidth: drawingCanvas.lineWidth,
            canUndo: drawingCanvas.canUndo,
            hasStrokes: !drawingCanvas.strokes.isEmpty
        )
    }

    @objc private func handleNewPresetSticky(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? StickyPreset else { return }
        createSticky(title: preset.title, color: preset.color)
    }

    @objc private func handleDeleteAllDone() {
        let doneIDs = notes.filter(\.isDone).map(\.id)
        for id in doneIDs {
            selectedIDs.remove(id)
            if let controller = controllers.removeValue(forKey: id) {
                controller.window?.orderOut(nil)
                controller.close()
            }
        }
        notes.removeAll(where: \.isDone)
        store.scheduleSave(notes)
        rebuildStatusMenu()
    }

    @objc private func handleToggleVisibility() {
        stickiesVisible.toggle()
        if !stickiesVisible {
            setDrawingMode(false)
            clearSelection()
            marqueeOverlay.hide()
        }
        drawingCanvas.setVisible(stickiesVisible)
        for controller in controllers.values {
            if stickiesVisible {
                controller.showOnDesktop(focus: false)
            } else {
                controller.window?.orderOut(nil)
            }
        }
        rebuildStatusMenu()
    }

    @objc private func handleToggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could not update Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMake sure you are running StickitToTheMax.app (ideally from /Applications)."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Login Items")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        rebuildStatusMenu()
    }

    @objc private func handleQuit() {
        store.saveImmediately(notes)
        NSApp.terminate(nil)
    }

    // MARK: - StickyWindowControllerDelegate

    func stickyControllerDidUpdate(_ note: StickyNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            let doneChanged = notes[index].isDone != note.isDone
            notes[index] = note
            store.scheduleSave(notes)
            if doneChanged {
                rebuildStatusMenu()
            }
        }
    }

    func stickyControllerDidRequestNew(near note: StickyNote) {
        createSticky(title: note.title, color: note.color, near: note)
    }

    func stickyControllerDidRequestDelete(_ note: StickyNote) {
        let hasContent = note.isImageSticky || !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasContent {
            removeSticky(id: note.id)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Delete this sticky?"
        let label = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled sticky" : "\"\(note.title)\""
        alert.informativeText = "\(label) will be permanently removed from your wallpaper."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            removeSticky(id: note.id)
        }
    }

    func stickyControllerDidCommandClick(id: UUID) {
        var next = selectedIDs
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        updateSelection(next)
    }

    func stickyControllerDidPlainClick(id: UUID) {
        if !selectedIDs.contains(id), !selectedIDs.isEmpty {
            clearSelection()
        }
    }

    func stickyControllerDidRequestClearSelection() {
        clearSelection()
    }

    func stickyControllerDidBeginMove(id: UUID) {
        let ids = targetIDs(for: id)
        activeGroupFrames = [:]
        for targetID in ids {
            if let frame = controllers[targetID]?.window?.frame {
                activeGroupFrames[targetID] = frame
            }
        }
    }

    func stickyControllerDidDragMove(deltaX: CGFloat, deltaY: CGFloat) {
        for (id, startFrame) in activeGroupFrames {
            let movedRect = NSRect(
                x: startFrame.origin.x + deltaX,
                y: startFrame.origin.y + deltaY,
                width: startFrame.width,
                height: startFrame.height
            )
            controllers[id]?.setFrameProgrammatically(movedRect)
        }
    }

    func stickyControllerDidEndMove() {
        commitActiveGroupFrames()
    }

    func stickyControllerDidBeginResize(id: UUID, edge: StickyResizeEdge) {
        let ids = targetIDs(for: id)
        activeGroupFrames = [:]
        for targetID in ids {
            if let frame = controllers[targetID]?.window?.frame {
                activeGroupFrames[targetID] = frame
            }
        }
    }

    func stickyControllerDidDragResize(edge: StickyResizeEdge, deltaX: CGFloat, deltaY: CGFloat) {
        let isSingle = activeGroupFrames.count == 1
        for (id, startFrame) in activeGroupFrames {
            let controller = controllers[id]
            let aspectRatio = isSingle ? controller?.imageAspectRatio : nil
            let minSize = controller?.window?.minSize ?? StickyNote.minSize
            let resized = StickyGeometry.resizedRect(
                from: startFrame,
                edge: edge,
                deltaX: deltaX,
                deltaY: deltaY,
                minSize: minSize,
                imageAspectRatio: aspectRatio
            )
            controller?.setFrameProgrammatically(resized)
        }
    }

    func stickyControllerDidEndResize() {
        commitActiveGroupFrames()
    }

    private func commitActiveGroupFrames() {
        var didChange = false
        for id in activeGroupFrames.keys {
            if let controller = controllers[id],
               let index = notes.firstIndex(where: { $0.id == id }) {
                let updated = controller.commitCurrentFrameToModel()
                if notes[index] != updated {
                    notes[index] = updated
                    didChange = true
                }
            }
        }
        activeGroupFrames = [:]
        if didChange {
            store.scheduleSave(notes)
        }
    }

    func stickyControllerDidAdjustFontSize(id: UUID, delta: Double) {
        let ids = targetIDs(for: id)
        var didChange = false
        for targetID in ids {
            if let controller = controllers[targetID],
               let index = notes.firstIndex(where: { $0.id == targetID }) {
                controller.applyFontSize(controller.note.fontSize + delta)
                if notes[index] != controller.note {
                    notes[index] = controller.note
                    didChange = true
                }
            }
        }
        if didChange {
            store.scheduleSave(notes)
        }
    }

    func stickyControllerDidResetFontSize(id: UUID) {
        let ids = targetIDs(for: id)
        var didChange = false
        for targetID in ids {
            if let controller = controllers[targetID],
               let index = notes.firstIndex(where: { $0.id == targetID }) {
                controller.applyFontSize(StickyNote.defaultFontSize)
                if notes[index] != controller.note {
                    notes[index] = controller.note
                    didChange = true
                }
            }
        }
        if didChange {
            store.scheduleSave(notes)
        }
    }

    // MARK: - DrawingCanvasOverlayDelegate

    func drawingCanvasDidUpdateStrokes(_ strokes: [DrawingStroke]) {
        drawingStore.scheduleSave(strokes)
        syncDrawingToolbarState()
        rebuildStatusMenu()
    }

    func drawingCanvasDidRequestExit() {
        setDrawingMode(false)
    }

    func drawingCanvasDidChangeLineWidth(_ width: Double) {
        syncDrawingToolbarState()
    }

    func drawingCanvasDidChangeTool(_ tool: DrawingTool) {
        syncDrawingToolbarState()
    }

    // MARK: - DrawingToolbarDelegate

    func drawingToolbarDidSelectTool(_ tool: DrawingTool) {
        drawingCanvas.tool = tool
        syncDrawingToolbarState()
    }

    func drawingToolbarDidSelectColor(_ color: PenColor) {
        drawingCanvas.penColor = color
        syncDrawingToolbarState()
    }

    func drawingToolbarDidChangeLineWidth(_ width: Double) {
        drawingCanvas.lineWidth = width
        syncDrawingToolbarState()
    }

    func drawingToolbarDidRequestUndo() {
        drawingCanvas.undo()
        syncDrawingToolbarState()
    }

    func drawingToolbarDidRequestClearAll() {
        drawingCanvas.clearAll()
        syncDrawingToolbarState()
        rebuildStatusMenu()
    }

    func drawingToolbarDidRequestDone() {
        setDrawingMode(false)
    }
}
