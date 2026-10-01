import Foundation
import AppKit
import Combine

public final class ClipboardManager: ObservableObject {
    public static let shared = ClipboardManager()

    @Published public private(set) var items: [ClipItem] = []
    @Published public var searchQuery: String = ""
    @Published public var selectedFilter: ClipFilter = .all
    @Published public var selectedItemID: UUID?

    public var maxItems: Int {
        return ClipSettings.shared.historyLimit
    }

    public func enforceLimit() {
        pruneToMaxLimit()
        persistItems()
    }

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    // Serial so saves land on disk in the order they were requested
    private let persistQueue = DispatchQueue(label: "com.clip.persist", qos: .utility)

    private let fileManager = FileManager.default
    private let appSupportURL: URL
    private let imagesFolderURL: URL
    private let storageFileURL: URL

    public enum ClipFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case text = "Text"
        case images = "Images"
        case links = "Links"
        case pinned = "Pinned"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .text: return "doc.text"
            case .images: return "photo"
            case .links: return "link"
            case .pinned: return "pin.fill"
            }
        }
    }

    public init() {
        let defaultBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var resolvedDir = defaultBase.appendingPathComponent("Clip", isDirectory: true)

        // Verify or fallback if Application Support cannot be created
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: resolvedDir.path, isDirectory: &isDir) {
            do {
                try fileManager.createDirectory(at: resolvedDir, withIntermediateDirectories: true)
            } catch {
                let homeFallback = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".clip", isDirectory: true)
                do {
                    try fileManager.createDirectory(at: homeFallback, withIntermediateDirectories: true)
                    resolvedDir = homeFallback
                } catch {
                    let tmpFallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Clip", isDirectory: true)
                    try? fileManager.createDirectory(at: tmpFallback, withIntermediateDirectories: true)
                    resolvedDir = tmpFallback
                }
            }
        }

        self.appSupportURL = resolvedDir
        self.imagesFolderURL = appSupportURL.appendingPathComponent("Images", isDirectory: true)
        self.storageFileURL = appSupportURL.appendingPathComponent("clipboard_history.json")

        setupStorage()
        loadPersistedItems()
        self.lastChangeCount = pasteboard.changeCount

        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    private func setupStorage() {
        do {
            try fileManager.createDirectory(at: imagesFolderURL, withIntermediateDirectories: true)
        } catch {
            print("Failed to create storage directory: \(error)")
        }
    }

    // MARK: - Filtered Items
    public var filteredItems: [ClipItem] {
        items.filter { item in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .text:
                matchesFilter = (item.type == .text || item.type == .code || item.type == .color)
            case .images:
                matchesFilter = (item.type == .image)
            case .links:
                matchesFilter = (item.type == .link)
            case .pinned:
                matchesFilter = item.isPinned
            }

            guard matchesFilter else { return false }

            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                return true
            }

            let query = searchQuery.lowercased()
            if let text = item.textValue?.lowercased(), text.contains(query) {
                return true
            }
            if let file = item.fileURLString?.lowercased(), file.contains(query) {
                return true
            }
            if item.previewTitle.lowercased().contains(query) {
                return true
            }
            return false
        }
    }

    // MARK: - Monitoring Loop
    public func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboard() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        readPasteboard()
    }

    // MARK: - Read Pasteboard
    private func readPasteboard() {
        // Skip transient / concealed password types (1Password, Bitwarden, Keychain, etc.)
        let types = pasteboard.types ?? []
        for type in types {
            let identifier = type.rawValue
            if identifier.contains("TransientType") || identifier.contains("ConcealedType") || identifier.contains("AutoGeneratedType") {
                return
            }
        }

        // 1. Check for Image
        if let image = NSImage(pasteboard: pasteboard) {
            handleImageCopy(image)
            return
        }

        // 2. Check for File URLs
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], let firstURL = fileURLs.first {
            handleFileURLCopy(firstURL)
            return
        }

        // 3. Check for String / Rich Text
        if let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
            let rtfData = pasteboard.data(forType: .rtf)
            let htmlData = pasteboard.data(forType: .html)
            handleStringCopy(string, rtfData: rtfData, htmlData: htmlData)
            return
        }
    }

    // MARK: - Handle Copy Types
    private func handleStringCopy(_ text: String, rtfData: Data?, htmlData: Data?) {
        let type = detectStringType(text)

        // Deduplication: check if already exists
        if let existingIndex = items.firstIndex(where: { $0.textValue == text }) {
            var existing = items[existingIndex]
            existing.createdAt = Date()
            existing.rtfData = rtfData ?? existing.rtfData
            existing.htmlData = htmlData ?? existing.htmlData
            items.remove(at: existingIndex)
            items.insert(existing, at: 0)
            persistItems()
            return
        }

        let newItem = ClipItem(
            type: type,
            textValue: text,
            rtfData: rtfData,
            htmlData: htmlData
        )

        insertItem(newItem)
    }

    private func handleImageCopy(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return
        }

        let fileName = "\(UUID().uuidString).png"
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)

        do {
            try pngData.write(to: fileURL)
            let newItem = ClipItem(
                type: .image,
                imageFileName: fileName,
                imageWidth: image.size.width,
                imageHeight: image.size.height
            )
            insertItem(newItem)
        } catch {
            print("Failed to save clipboard image: \(error)")
        }
    }

    private func handleFileURLCopy(_ url: URL) {
        let path = url.path
        if let existingIndex = items.firstIndex(where: { $0.fileURLString == path }) {
            var existing = items[existingIndex]
            existing.createdAt = Date()
            items.remove(at: existingIndex)
            items.insert(existing, at: 0)
            persistItems()
            return
        }

        let newItem = ClipItem(
            type: .file,
            textValue: url.lastPathComponent,
            fileURLString: path
        )
        insertItem(newItem)
    }

    private func insertItem(_ item: ClipItem) {
        items.insert(item, at: 0)
        pruneToMaxLimit()
        persistItems()
        if selectedItemID == nil {
            selectedItemID = item.id
        }
    }

    private func pruneToMaxLimit() {
        guard items.count > maxItems else { return }

        // Find items to remove from the end, preferring unpinned
        while items.count > maxItems {
            if let lastUnpinnedIndex = items.lastIndex(where: { !$0.isPinned }) {
                let removed = items.remove(at: lastUnpinnedIndex)
                cleanUpImageFile(for: removed)
            } else {
                // If all are pinned, remove the oldest item
                let removed = items.removeLast()
                cleanUpImageFile(for: removed)
            }
        }
    }

    private func cleanUpImageFile(for item: ClipItem) {
        guard let fileName = item.imageFileName else { return }
        let fileURL = imagesFolderURL.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: - Detect String Type
    private func detectStringType(_ text: String) -> ClipType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // URL detection
        if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) && !trimmed.contains(" ") {
            return .link
        }

        // Color Hex detection (#FFF, #FFFFFF, #FFFFFFFF)
        let hexPattern = "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"
        if trimmed.range(of: hexPattern, options: .regularExpression) != nil {
            return .color
        }

        // Code detection
        let codeIndicators = [
            "func ", "function ", "import ", "export ", "class ", "struct ", "def ",
            "const ", "let ", "var ", "return ", "if (", "for (", "while (",
            "<?php", "<html", "<div", "</", "=>", "->", "public ", "private "
        ]
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count > 1 {
            let hasCodeKeyword = codeIndicators.contains { trimmed.contains($0) }
            let hasBracesOrIndentation = trimmed.contains("{") && trimmed.contains("}")
            if hasCodeKeyword || hasBracesOrIndentation {
                return .code
            }
        }

        return .text
    }

    // MARK: - Copy Item Back to Pasteboard
    public func copyToPasteboard(item: ClipItem) {
        pasteboard.clearContents()

        switch item.type {
        case .image:
            if let fileName = item.imageFileName {
                let url = imagesFolderURL.appendingPathComponent(fileName)
                if let image = NSImage(contentsOf: url) {
                    pasteboard.writeObjects([image])
                }
            }
        case .file:
            if let fileStr = item.fileURLString, let url = URL(string: "file://" + fileStr) {
                pasteboard.writeObjects([url as NSURL])
            }
        default:
            if let text = item.textValue {
                pasteboard.setString(text, forType: .string)
            }
            if let rtf = item.rtfData {
                pasteboard.setData(rtf, forType: .rtf)
            }
            if let html = item.htmlData {
                pasteboard.setData(html, forType: .html)
            }
        }

        // Recording our own change count stops the monitor from re-capturing this write
        lastChangeCount = pasteboard.changeCount

        // Bump item to top of list as most recently used
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            var updated = items.remove(at: idx)
            updated.createdAt = Date()
            items.insert(updated, at: 0)
            persistItems()
        }
    }

    // MARK: - Actions
    public func togglePin(for itemID: UUID) {
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            items[index].isPinned.toggle()
            persistItems()
        }
    }

    public func deleteItem(withID itemID: UUID) {
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            let item = items.remove(at: index)
            cleanUpImageFile(for: item)
            persistItems()

            if selectedItemID == itemID {
                selectedItemID = items.first?.id
            }
        }
    }

    public func clearAll(includePinned: Bool = false) {
        let toRemove = items.filter { includePinned || !$0.isPinned }
        for item in toRemove {
            cleanUpImageFile(for: item)
        }
        items.removeAll(where: { includePinned || !$0.isPinned })
        selectedItemID = items.first?.id
        persistItems()
    }

    public func imageURL(for item: ClipItem) -> URL? {
        guard let fileName = item.imageFileName else { return nil }
        return imagesFolderURL.appendingPathComponent(fileName)
    }

    // MARK: - Persistence
    private func persistItems() {
        // Snapshot on the calling (main) thread; `items` must never be read from the persist queue
        let snapshot = items
        let url = storageFileURL
        persistQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                print("Failed to save clipboard items: \(error)")
            }
        }
    }

    private func loadPersistedItems() {
        guard fileManager.fileExists(atPath: storageFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([ClipItem].self, from: data)
            self.items = Array(loaded.prefix(maxItems))
            self.selectedItemID = self.items.first?.id
        } catch {
            print("Failed to load clipboard items: \(error)")
        }
    }
}
