import Foundation

public final class StickyStore {
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
                .appendingPathComponent("stickies.json")
        }
        self.debounceInterval = debounceInterval

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public var imagesDirectoryURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
    }

    public func imageURL(for filename: String) -> URL {
        imagesDirectoryURL.appendingPathComponent(filename)
    }

    public func importImage(from sourceURL: URL) throws -> String {
        try FileManager.default.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = imagesDirectoryURL.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return filename
    }

    public func saveImageData(_ data: Data, fileExtension: String = "png") throws -> String {
        try FileManager.default.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).\(fileExtension)"
        let destination = imagesDirectoryURL.appendingPathComponent(filename)
        try data.write(to: destination, options: [.atomic])
        return filename
    }

    public func deleteImage(filename: String?) {
        guard let filename else { return }
        let url = imagesDirectoryURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    public func load() -> [StickyNote]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([StickyNote].self, from: data)
        } catch {
            NSLog("StickitToTheMax: Failed to load stickies from %@: %@", fileURL.path, error.localizedDescription)
            return nil
        }
    }

    public func saveImmediately(_ notes: [StickyNote]) {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        writeToDisk(notes)
    }

    public func scheduleSave(_ notes: [StickyNote]) {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.writeToDisk(notes)
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func writeToDisk(_ notes: [StickyNote]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(notes)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("StickitToTheMax: Failed to save stickies to %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
