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
}
