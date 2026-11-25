import Foundation

public final class DrawingStore {
    public let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil, debounceInterval: TimeInterval = 0.4) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            self.fileURL = appSupport
                .appendingPathComponent("StickitToTheMax", isDirectory: true)
                .appendingPathComponent("drawings.json")
        }
        self.debounceInterval = debounceInterval

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    public func load() -> [DrawingStroke] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([DrawingStroke].self, from: data)
        } catch {
            NSLog("StickitToTheMax: Failed to load drawings from %@: %@", fileURL.path, error.localizedDescription)
            return []
        }
    }

    public func saveImmediately(_ strokes: [DrawingStroke]) {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        writeToDisk(strokes)
    }

    public func scheduleSave(_ strokes: [DrawingStroke]) {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.writeToDisk(strokes)
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func writeToDisk(_ strokes: [DrawingStroke]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(strokes)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("StickitToTheMax: Failed to save drawings to %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
