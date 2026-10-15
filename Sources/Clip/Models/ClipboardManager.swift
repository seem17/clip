import Foundation
import AppKit
import Combine
import CryptoKit

public final class ClipboardManager: ObservableObject {
    public static let shared = ClipboardManager()

    @Published public private(set) var items: [ClipItem] = []
    @Published public var searchQuery: String = ""
    @Published public var selectedFilter: ClipFilter = .all
    @Published public var selectedItemID: UUID?

    public var maxItems: Int {
        return ClipSettings.shared.historyLimit
    }

    @Published public var openTrigger: Int = 0

    public func resetSelectionForOpen() {
        if items.count > 1 {
            selectedItemID = items[1].id
        } else if let first = items.first {
            selectedItemID = first.id
        } else {
            selectedItemID = nil
        }
        openTrigger += 1
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
    // Keeps image file reads and hashing off the pasteboard poll timer
    private let hashQueue = DispatchQueue(label: "com.clip.imagehash", qos: .utility)

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
        backfillImageHashesIfNeeded()
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

        let fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL]) ?? []
        let fileURL = fileURLs.first

        // 1. Check for File URLs (before images: Finder also puts the file's icon on the pasteboard).
        // Temp/cache files are skipped here: screenshot tools pair real image data with a
        // throwaway file that may be deleted later, so the image bytes are the thing to keep.
        if let fileURL = fileURL, !isTemporaryLocation(fileURL) {
            if isExceedingSizeLimit(urls: fileURLs) {
                return
            }
            handleFileURLCopy(fileURL, allURLs: fileURLs)
            return
        }

        // 2. Check for Image
        if let image = NSImage(pasteboard: pasteboard) {
            handleImageCopy(image)
            return
        }

        // 3. Temp/cache file with no image data alongside it
        if let fileURL = fileURL {
            if isExceedingSizeLimit(urls: fileURLs) {
                return
            }
            handleFileURLCopy(fileURL, allURLs: fileURLs)
            return
        }

        // 4. Check for String / Rich Text
        if let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
            let rtfData = pasteboard.data(forType: .rtf)
            let htmlData = pasteboard.data(forType: .html)
            handleStringCopy(string, rtfData: rtfData, htmlData: htmlData)
            return
        }
    }

    private func isTemporaryLocation(_ url: URL) -> Bool {
        // Resolve symlinks so /var/folders and /private/var/folders compare equal
        let path = url.resolvingSymlinksInPath().path
        var roots = [
            URL(fileURLWithPath: NSTemporaryDirectory()),
            URL(fileURLWithPath: "/private/tmp"),
            URL(fileURLWithPath: "/private/var/folders")
        ]
        roots += fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return roots.contains { path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }
    }

    // MARK: - Handle Copy Types
    private func handleStringCopy(_ text: String, rtfData: Data?, htmlData: Data?) {
        let type = detectStringType(text)
        let incomingSignature = ClipItem.textSignature(for: text)

        // Deduplication: match on the item's own signature, which is namespaced by
        // type, so a file item's name can never collide with copied text
        if let existingIndex = items.firstIndex(where: { $0.uniquenessSignature == incomingSignature }) {
            // If already at the top of the list, do not re-add or duplicate
            if existingIndex == 0 {
                return
            }

            var existing = items.remove(at: existingIndex)
            existing.createdAt = Date()
            existing.rtfData = rtfData ?? existing.rtfData
            existing.htmlData = htmlData ?? existing.htmlData
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

    private static func hexDigest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func handleImageCopy(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return
        }

        let sha256 = Self.hexDigest(of: pngData)
        let incomingSignature = ClipItem.imageSignature(forHash: sha256)

        // Deduplication: compare stored hashes only. Reading and re-hashing every
        // image here would put disk I/O on the pasteboard poll timer; hashes absent
        // from older history are filled in once by backfillImageHashesIfNeeded().
        if let existingIndex = items.firstIndex(where: { $0.uniquenessSignature == incomingSignature }) {
            if existingIndex == 0 {
                return
            }

            var existing = items.remove(at: existingIndex)
            existing.createdAt = Date()
            items.insert(existing, at: 0)
            persistItems()
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
                imageHeight: image.size.height,
                imageHash: sha256
            )
            insertItem(newItem)
        } catch {
            print("Failed to save clipboard image: \(error)")
        }
    }

    /// Fills in `imageHash` for images persisted before hashes were stored, so the
    /// dedup check in `handleImageCopy` stays a pure in-memory comparison. Reads and
    /// hashes off the main thread, then applies the results back on it. Runs once at
    /// launch: every image saved since carries its hash from the start.
    private func backfillImageHashesIfNeeded() {
        let pending: [(id: UUID, fileName: String)] = items.compactMap { item in
            guard item.type == .image, item.imageHash == nil,
                  let fileName = item.imageFileName else { return nil }
            return (item.id, fileName)
        }
        guard !pending.isEmpty else { return }

        let folder = imagesFolderURL
        hashQueue.async { [weak self] in
            var hashes: [UUID: String] = [:]
            for entry in pending {
                guard let data = try? Data(contentsOf: folder.appendingPathComponent(entry.fileName)) else { continue }
                hashes[entry.id] = Self.hexDigest(of: data)
            }
            guard !hashes.isEmpty else { return }

            DispatchQueue.main.async {
                guard let self = self else { return }
                var updated = self.items
                var changed = false
                for index in updated.indices {
                    guard updated[index].imageHash == nil,
                          let hash = hashes[updated[index].id] else { continue }
                    updated[index].imageHash = hash
                    changed = true
                }
                guard changed else { return }
                self.items = updated
                self.persistItems()
            }
        }
    }

    // MARK: - File/Folder Size Limit (100MB)
    public static let maxFileSizeLimitBytes: Int64 = 100 * 1024 * 1024 // 100 MB

    /// Calculates the size of a file or folder on disk, exiting early once limitBytes is reached.
    public func calculateSize(at url: URL, limitBytes: Int64) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? Int64) ?? 0
        }

        // Folder size calculation: recursively accumulate regular file sizes
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else {
            return 0
        }

        var folderSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else {
                continue
            }
            folderSize += Int64(size)
            if folderSize > limitBytes {
                return folderSize
            }
        }
        return folderSize
    }

    /// Checks if any single item or the total size of copied files/folders exceeds 100MB.
    public func isExceedingSizeLimit(urls: [URL]) -> Bool {
        var totalSize: Int64 = 0
        for url in urls {
            let remaining = Self.maxFileSizeLimitBytes - totalSize
            let size = calculateSize(at: url, limitBytes: max(remaining, 0))
            if size > Self.maxFileSizeLimitBytes {
                return true
            }
            totalSize += size
            if totalSize > Self.maxFileSizeLimitBytes {
                return true
            }
        }
        return false
    }

    private func handleFileURLCopy(_ url: URL, allURLs: [URL] = []) {
        let urlsToCheck = allURLs.isEmpty ? [url] : allURLs
        if isExceedingSizeLimit(urls: urlsToCheck) {
            return
        }

        let standardizedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        if let existingIndex = items.firstIndex(where: { item in
            guard let existingPath = item.fileURLString else { return false }
            return URL(fileURLWithPath: existingPath).resolvingSymlinksInPath().standardizedFileURL.path == standardizedPath
        }) {
            if existingIndex == 0 {
                return
            }

            var existing = items.remove(at: existingIndex)
            existing.createdAt = Date()
            items.insert(existing, at: 0)
            persistItems()
            return
        }

        let newItem = ClipItem(
            type: .file,
            textValue: url.lastPathComponent,
            fileURLString: standardizedPath
        )
        insertItem(newItem)
    }

    private func insertItem(_ item: ClipItem) {
        var item = item
        let sig = item.uniquenessSignature
        let superseded = items.filter { $0.uniquenessSignature == sig }

        // A replacement inherits the pin, otherwise re-copying a pinned item unpins it
        if superseded.contains(where: { $0.isPinned }) {
            item.isPinned = true
        }
        items.removeAll(where: { $0.uniquenessSignature == sig })

        items.insert(item, at: 0)
        for old in superseded where old.imageFileName != item.imageFileName {
            cleanUpImageFile(for: old)
        }
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
            if let path = item.fileURLString {
                if fileManager.fileExists(atPath: path) {
                    // fileURLWithPath escapes spaces and non-ASCII; URL(string:) returns nil for them
                    pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
                } else {
                    // File was deleted: fall back to writing the filename as plain text
                    let fallback = item.textValue ?? URL(fileURLWithPath: path).lastPathComponent
                    pasteboard.setString(fallback, forType: .string)
                }
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
                if index < items.count {
                    selectedItemID = items[index].id
                } else if !items.isEmpty {
                    selectedItemID = items.last?.id
                } else {
                    selectedItemID = nil
                }
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

            // Deduplicate loaded items, keeping the most recent of each signature.
            // Signature normalization is broader than the exact matching used when
            // these items were written, so history can hold near-duplicates whose
            // pin sits on the older copy; carry it over rather than lose it.
            var keptIndexBySignature: [String: Int] = [:]
            var unique: [ClipItem] = []
            var dropped: [ClipItem] = []
            for item in loaded {
                let sig = item.uniquenessSignature
                if let keptIndex = keptIndexBySignature[sig] {
                    if item.isPinned {
                        unique[keptIndex].isPinned = true
                    }
                    dropped.append(item)
                } else {
                    keptIndexBySignature[sig] = unique.count
                    unique.append(item)
                }
            }

            let kept = Array(unique.prefix(maxItems))
            dropped.append(contentsOf: unique.dropFirst(kept.count))

            self.items = kept
            self.selectedItemID = self.items.first?.id

            // Nothing references the dropped items' images any more
            let stillReferenced = Set(kept.compactMap { $0.imageFileName })
            for item in dropped {
                guard let fileName = item.imageFileName,
                      !stillReferenced.contains(fileName) else { continue }
                cleanUpImageFile(for: item)
            }
        } catch {
            print("Failed to load clipboard items: \(error)")
        }
    }
}
