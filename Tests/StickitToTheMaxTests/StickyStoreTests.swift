import Foundation
import XCTest
@testable import StickitToTheMax

final class StickyStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StickitToTheMaxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testSaveAndLoadRoundTrip() {
        let fileURL = tempDir.appendingPathComponent("stickies.json")
        let store = StickyStore(fileURL: fileURL)

        XCTAssertNil(store.load(), "Fresh store should return nil before any save")

        let workNote = StickyNote(
            title: "Work",
            body: "Ship MVP",
            color: .blue,
            isDone: false,
            frame: StickyFrame(x: 100, y: 200, width: 260, height: 220)
        )
        let personalNote = StickyNote(
            title: "Personal",
            body: "Buy coffee",
            color: .yellow,
            isDone: true,
            frame: StickyFrame(x: 400, y: 200, width: 300, height: 180)
        )

        store.saveImmediately([workNote, personalNote])

        let loaded = store.load()
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?[0].id, workNote.id)
        XCTAssertEqual(loaded?[0].title, "Work")
        XCTAssertEqual(loaded?[0].color, .blue)
        XCTAssertEqual(loaded?[0].isDone, false)
        XCTAssertEqual(loaded?[0].frame, workNote.frame)

        XCTAssertEqual(loaded?[1].id, personalNote.id)
        XCTAssertEqual(loaded?[1].title, "Personal")
        XCTAssertEqual(loaded?[1].color, .yellow)
        XCTAssertEqual(loaded?[1].isDone, true)
    }

    func testEmptyArrayPersistsDistinctFromNil() {
        let fileURL = tempDir.appendingPathComponent("stickies.json")
        let store = StickyStore(fileURL: fileURL)

        store.saveImmediately([])
        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 0)
    }

    func testAllStickyColorsHaveValidDisplayNames() {
        XCTAssertEqual(StickyColor.allCases.count, 6)
        for color in StickyColor.allCases {
            XCTAssertFalse(color.displayName.isEmpty)
        }
    }

    func testWallpaperWindowLevelIsStrictlyBelowNormalWindows() {
        let wallpaperLevel = StickyWindow.wallpaperLevel.rawValue
        let normalLevel = NSWindow.Level.normal.rawValue
        XCTAssertLessThan(wallpaperLevel, normalLevel)
    }

    func testFontSizePersistsAndClamps() {
        let fileURL = tempDir.appendingPathComponent("stickies.json")
        let store = StickyStore(fileURL: fileURL)

        let bigNote = StickyNote(
            title: "Big",
            body: "Large text",
            fontSize: 99.0,
            frame: StickyFrame(x: 10, y: 10, width: 260, height: 220)
        )
        let smallNote = StickyNote(
            title: "Small",
            body: "Tiny text",
            fontSize: 2.0,
            frame: StickyFrame(x: 300, y: 10, width: 260, height: 220)
        )
        XCTAssertEqual(bigNote.fontSize, StickyNote.maxFontSize)
        XCTAssertEqual(smallNote.fontSize, StickyNote.minFontSize)

        store.saveImmediately([bigNote, smallNote])
        let loaded = store.load()
        XCTAssertEqual(loaded?[0].fontSize, StickyNote.maxFontSize)
        XCTAssertEqual(loaded?[1].fontSize, StickyNote.minFontSize)
    }

    func testLegacyJSONWithoutFontSizeDefaultsCleanly() throws {
        let fileURL = tempDir.appendingPathComponent("legacy.json")
        let legacyJSON = """
        [
          {
            "body": "Legacy item",
            "color": "yellow",
            "createdAt": "2026-11-25T07:00:00Z",
            "frame": { "height": 220, "width": 260, "x": 100, "y": 200 },
            "id": "11111111-1111-1111-1111-111111111111",
            "isDone": false,
            "title": "Personal",
            "updatedAt": "2026-11-25T07:00:00Z"
          }
        ]
        """
        try legacyJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = StickyStore(fileURL: fileURL)
        let loaded = store.load()
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?[0].fontSize, StickyNote.defaultFontSize)
    }

    func testStickyGeometryBottomRightResizeAnchorsTopLeft() {
        let initial = NSRect(x: 100, y: 200, width: 260, height: 220)
        let resized = StickyGeometry.resizedRect(from: initial, edge: .bottomRight, deltaX: 40, deltaY: 30)

        XCTAssertEqual(resized.origin.x, 100)
        XCTAssertEqual(resized.maxY, initial.maxY)
        XCTAssertEqual(resized.width, 300)
        XCTAssertEqual(resized.height, 250)
    }

    func testStickyGeometryLeftEdgeResizeAnchorsRightEdgeAndClamps() {
        let initial = NSRect(x: 100, y: 200, width: 260, height: 220)
        let shrunk = StickyGeometry.resizedRect(from: initial, edge: .left, deltaX: 500, deltaY: 0)

        XCTAssertEqual(shrunk.width, StickyNote.minSize.width)
        XCTAssertEqual(shrunk.maxX, initial.maxX)
        XCTAssertEqual(shrunk.origin.y, initial.origin.y)
        XCTAssertEqual(shrunk.height, initial.height)
    }

    func testDrawingStoreSaveLoadAndClamping() {
        let fileURL = tempDir.appendingPathComponent("drawings.json")
        let store = DrawingStore(fileURL: fileURL)

        XCTAssertTrue(store.load().isEmpty)

        let stroke = DrawingStroke(
            points: [DrawingPoint(x: 10, y: 20), DrawingPoint(x: 110, y: 120)],
            color: .pink,
            lineWidth: 99.0
        )
        XCTAssertEqual(stroke.lineWidth, DrawingStroke.maxLineWidth)

        store.saveImmediately([stroke])
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0], stroke)
    }

    func testDrawingStrokeHitTestingForEraser() {
        let stroke = DrawingStroke(
            points: [DrawingPoint(x: 0, y: 0), DrawingPoint(x: 100, y: 0)],
            color: .yellow,
            lineWidth: 4.0
        )
        XCTAssertTrue(stroke.intersects(point: NSPoint(x: 50, y: 6), radius: 10))
        XCTAssertFalse(stroke.intersects(point: NSPoint(x: 50, y: 30), radius: 10))
        XCTAssertFalse(stroke.intersects(point: NSPoint(x: 130, y: 0), radius: 10))
    }

    func testPictureStickyPersistenceAndImageFileLifecycle() throws {
        let fileURL = tempDir.appendingPathComponent("stickies.json")
        let store = StickyStore(fileURL: fileURL)

        let fakePNG = Data([0x89, 0x50, 0x4E, 0x47])
        let filename = try store.saveImageData(fakePNG, fileExtension: "png")
        let savedImageURL = store.imageURL(for: filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedImageURL.path))

        let note = StickyNote(
            title: "Photo",
            imageFilename: filename,
            frame: StickyFrame(x: 50, y: 60, width: 320, height: 240)
        )
        XCTAssertTrue(note.isImageSticky)
        store.saveImmediately([note])

        let loaded = store.load()
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?[0].imageFilename, filename)
        XCTAssertTrue(loaded?[0].isImageSticky == true)

        store.deleteImage(filename: filename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedImageURL.path))
    }

    func testPictureStickyCornerResizePreservesAspectRatio() {
        let chrome: CGFloat = 45
        // 2:1 landscape image: 300w x 150h body => 300 x 195 window
        let initial = NSRect(x: 100, y: 200, width: 300, height: 195)
        let resized = StickyGeometry.resizedRect(
            from: initial,
            edge: .bottomRight,
            deltaX: 100,
            deltaY: 0,
            imageAspectRatio: 2.0,
            chromeHeight: chrome
        )
        XCTAssertEqual(resized.width, 400, accuracy: 0.5)
        XCTAssertEqual(resized.height, 200 + chrome, accuracy: 0.5)
        XCTAssertEqual(resized.maxY, initial.maxY, accuracy: 0.5)
    }

    func testCanvasTransformPreservesOrderAndDrawingAlignmentAcrossMonitors() {
        let externalScreen = NSRect(x: 0, y: 0, width: 3440, height: 1410)
        let macbookScreen = NSRect(x: 0, y: 0, width: 1800, height: 1130)

        let leftSticky = StickyNote(
            title: "Personal",
            frame: StickyFrame(x: 1200, y: 900, width: 260, height: 180)
        )
        let rightSticky = StickyNote(
            title: "Work",
            frame: StickyFrame(x: 2900, y: 900, width: 260, height: 180)
        )
        let bottomSticky = StickyNote(
            title: "Picture",
            frame: StickyFrame(x: 1200, y: 300, width: 320, height: 220)
        )
        // Arrow connecting bottom of leftSticky (1330, 900) to top of bottomSticky (1330, 520)
        let arrow = DrawingStroke(
            points: [DrawingPoint(x: 1330, y: 900), DrawingPoint(x: 1330, y: 520)],
            color: .yellow,
            lineWidth: 4.0
        )

        // On external monitor, everything fits -> identity transform
        let externalTransform = CanvasTransform.fit(
            notes: [leftSticky, rightSticky, bottomSticky],
            strokes: [arrow],
            visibleScreenFrames: [externalScreen],
            fallbackVisibleFrame: externalScreen
        )
        XCTAssertTrue(externalTransform.isIdentity)

        // Switching to MacBook -> fits uniformly inside 1800x1130
        let macbookTransform = CanvasTransform.fit(
            notes: [leftSticky, rightSticky, bottomSticky],
            strokes: [arrow],
            visibleScreenFrames: [macbookScreen],
            fallbackVisibleFrame: macbookScreen
        )
        XCTAssertLessThan(macbookTransform.scale, 1.0)

        let dispLeft = macbookTransform.apply(to: leftSticky.frame.nsRect)
        let dispRight = macbookTransform.apply(to: rightSticky.frame.nsRect)
        let dispBottom = macbookTransform.apply(to: bottomSticky.frame.nsRect)
        let dispArrowStart = macbookTransform.apply(to: arrow.points[0].nsPoint)
        let dispArrowEnd = macbookTransform.apply(to: arrow.points[1].nsPoint)

        // Relative order preserved
        XCTAssertLessThan(dispLeft.maxX, dispRight.minX)
        XCTAssertGreaterThan(dispLeft.minY, dispBottom.maxY)

        // Everything stays inside MacBook visible frame
        XCTAssertTrue(macbookScreen.contains(dispLeft))
        XCTAssertTrue(macbookScreen.contains(dispRight))
        XCTAssertTrue(macbookScreen.contains(dispBottom))
        XCTAssertTrue(macbookScreen.contains(dispArrowStart))
        XCTAssertTrue(macbookScreen.contains(dispArrowEnd))

        // Arrow remains aligned horizontally with leftSticky's center
        XCTAssertEqual(dispArrowStart.x, dispLeft.midX, accuracy: 1.5)
        XCTAssertEqual(dispArrowEnd.x, dispLeft.midX, accuracy: 1.5)

        // Inverse transform round-trips cleanly back to canonical coordinates
        let roundTripped = macbookTransform.invert(dispArrowStart)
        XCTAssertEqual(roundTripped.x, 1330, accuracy: 0.5)
        XCTAssertEqual(roundTripped.y, 900, accuracy: 0.5)
    }
}
