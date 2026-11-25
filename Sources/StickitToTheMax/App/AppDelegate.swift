import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, StickyWindowControllerDelegate {
    private let store: StickyStore
    private var statusItem: NSStatusItem?
    private var controllers: [UUID: StickyWindowController] = [:]
    private var notes: [StickyNote] = []
    private var stickiesVisible = true

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
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupEditMenu()
        setupStatusItem()
        loadInitialNotes()
        observeScreenChanges()
        installDesktopMarqueeMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseUpMonitor {
            NSEvent.removeMonitor(localMouseUpMonitor)
            self.localMouseUpMonitor = nil
        }
        store.saveImmediately(notes)
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
        guard stickiesVisible else { return }
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

    private func spawnController(for note: StickyNote, focus: Bool) {
        let controller = StickyWindowController(note: note)
        controller.delegate = self
        controllers[note.id] = controller
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

        return StickyFrame(rect: NSRect(origin: origin, size: NSSize(width: width, height: height)))
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

    private func removeSticky(id: UUID) {
        selectedIDs.remove(id)
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
        let screens = NSScreen.screens
        guard let fallback = NSScreen.main ?? screens.first else { return }

        var changed = false
        for index in notes.indices {
            let rect = notes[index].frame.nsRect
            let isOnAnyScreen = screens.contains { $0.visibleFrame.intersects(rect) }
            if !isOnAnyScreen {
                let target = fallback.visibleFrame
                let clampedX = min(max(rect.origin.x, target.minX + 20), target.maxX - rect.width - 20)
                let clampedY = min(max(rect.origin.y, target.minY + 20), target.maxY - rect.height - 20)
                let newRect = NSRect(x: clampedX, y: clampedY, width: rect.width, height: rect.height)
                notes[index].frame = StickyFrame(rect: newRect)
                controllers[notes[index].id]?.setFrameProgrammatically(newRect)
                changed = true
            }
        }
        if changed {
            store.scheduleSave(notes)
        }
    }

    // MARK: - Menu Actions

    @objc private func handleNewDefaultSticky() {
        createSticky(title: "", color: .yellow)
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
            clearSelection()
            marqueeOverlay.hide()
        }
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
        let hasContent = !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        for (id, startFrame) in activeGroupFrames {
            let resized = StickyGeometry.resizedRect(
                from: startFrame,
                edge: edge,
                deltaX: deltaX,
                deltaY: deltaY
            )
            controllers[id]?.setFrameProgrammatically(resized)
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
}
