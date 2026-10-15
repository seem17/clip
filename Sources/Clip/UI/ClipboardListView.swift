import SwiftUI
import AppKit

public struct ClipboardListView: View {
    @ObservedObject var clipboardManager: ClipboardManager = .shared
    @ObservedObject var settings: ClipSettings = .shared

    public var onDismiss: () -> Void
    public var onPasteItem: (ClipItem) -> Void

    @Environment(\.colorScheme) var colorScheme

    public init(
        onDismiss: @escaping () -> Void,
        onPasteItem: @escaping (ClipItem) -> Void
    ) {
        self.onDismiss = onDismiss
        self.onPasteItem = onPasteItem
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                if clipboardManager.items.isEmpty {
                    VStack {
                        Text("Clipboard is empty")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, 40)
                    }
                } else {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id("SCROLL_TOP")

                        LazyVStack(spacing: 6) {
                            ForEach(clipboardManager.items) { item in
                                ClipboardRowView(
                                    item: item,
                                    isSelected: clipboardManager.selectedItemID == item.id,
                                    onSelect: {
                                        clipboardManager.selectedItemID = item.id
                                        onPasteItem(item)
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
            .onAppear {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo("SCROLL_TOP", anchor: .top)
                }
            }
            .onChange(of: clipboardManager.openTrigger) { _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo("SCROLL_TOP", anchor: .top)
                }
            }
            .onChange(of: clipboardManager.selectedItemID) { newID in
                guard let newID = newID else { return }
                if let index = clipboardManager.items.firstIndex(where: { $0.id == newID }) {
                    if index <= 1 {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            proxy.scrollTo("SCROLL_TOP", anchor: .top)
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(newID)
                        }
                    }
                }
            }
        }
        .frame(width: settings.windowWidth, height: settings.windowHeight)
        .liquidGlassContainer(cornerRadius: 16)
        .preferredColorScheme(settings.appearanceMode == .dark ? .dark : (settings.appearanceMode == .light ? .light : nil))
        .background {
            // Invisible shortcuts
            Button("") { onDismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()

            Button("") {
                if let selectedID = clipboardManager.selectedItemID,
                   let item = clipboardManager.items.first(where: { $0.id == selectedID }) {
                    onPasteItem(item)
                } else if let first = clipboardManager.items.first {
                    onPasteItem(first)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .hidden()

            Button("") {
                if let selectedID = clipboardManager.selectedItemID {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        clipboardManager.deleteItem(withID: selectedID)
                    }
                }
            }
            .keyboardShortcut(.delete, modifiers: [])
            .hidden()

            Button("") {
                if let selectedID = clipboardManager.selectedItemID {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        clipboardManager.deleteItem(withID: selectedID)
                    }
                }
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .hidden()
        }
        .onAppear {
            clipboardManager.resetSelectionForOpen()
        }
    }
}

// MARK: - Minimalistic Clipboard Row
private struct ClipboardRowView: View {
    let item: ClipItem
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false
    @State private var isDeleteHovered: Bool = false
    @State private var thumbnail: NSImage?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            switch item.type {
            case .image:
                imageThumbnail

            case .color:
                if let hexColor = item.detectedHexColor {
                    Circle()
                        .fill(Color(nsColor: hexColor))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2), lineWidth: 1))
                }
                Text(item.textValue ?? "")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)

            case .file:
                if item.isFileMissing {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(item.previewTitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                        .strikethrough(true, color: .secondary.opacity(0.5))
                        .lineLimit(1)
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(item.previewTitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

            case .code:
                Text(item.previewTitle)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(ClipSettings.shared.previewLines)
                    .truncationMode(.tail)

            case .text, .link:
                Text(item.previewTitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(ClipSettings.shared.previewLines)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, item.type == .image ? 6 : 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .overlay(alignment: .trailing) {
            if isHovered {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        ClipboardManager.shared.deleteItem(withID: item.id)
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isDeleteHovered ? .white : .secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(isDeleteHovered
                                    ? Color.red.opacity(0.85)
                                    : (colorScheme == .dark ? Color(white: 0.22, opacity: 0.95) : Color(white: 0.92, opacity: 0.95)))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .help("Delete item (⌫)")
                .transition(.opacity)
                .onHover { isDeleteHovered = $0 }
            }
        }
        .liquidGlassCard(isSelected: isSelected, isHovered: isHovered, cornerRadius: 10)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    ClipboardManager.shared.deleteItem(withID: item.id)
                }
            } label: {
                Label("Delete Item", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var imageThumbnail: some View {
        if let nsImage = thumbnail ?? ThumbnailCache.cached(for: item) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.10), lineWidth: 0.5)
                )
        } else {
            Image(systemName: "photo")
                .foregroundColor(.secondary)
                .frame(height: 36)
                .task(id: item.imageFileName) {
                    guard let key = item.imageFileName,
                          let url = ClipboardManager.shared.imageURL(for: item) else { return }
                    // Decode a CGImage off the main thread; wrap it in NSImage back here, since
                    // NSImage's Sendable conformance needs macOS 14
                    let decoded = await Task.detached(priority: .userInitiated) {
                        ThumbnailCache.decode(url: url)
                    }.value
                    if let decoded = decoded {
                        thumbnail = ThumbnailCache.store(decoded, forKey: key)
                    }
                }
        }
    }
}

// MARK: - Thumbnail Cache
/// Downsampled row thumbnails, so the list never decodes full-resolution images.
private enum ThumbnailCache {
    private static let maxPixelSize = 320
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func cached(for item: ClipItem) -> NSImage? {
        guard let key = item.imageFileName else { return nil }
        return cache.object(forKey: key as NSString)
    }

    static func decode(url: URL) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Returns the image directly so callers don't depend on the cache keeping it.
    static func store(_ cgImage: CGImage, forKey key: String) -> NSImage {
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
        cache.setObject(image, forKey: key as NSString, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
