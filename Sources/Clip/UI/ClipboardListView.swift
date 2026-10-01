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
                    .padding(8)
                }
            }
            .onChange(of: clipboardManager.selectedItemID) { newID in
                if let newID = newID {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
        .frame(width: settings.windowWidth, height: settings.windowHeight)
        .liquidGlassContainer(cornerRadius: 16)
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
        }
        .onAppear {
            if clipboardManager.selectedItemID == nil || !clipboardManager.items.contains(where: { $0.id == clipboardManager.selectedItemID }) {
                clipboardManager.selectedItemID = clipboardManager.items.first?.id
            }
        }
    }
}

// MARK: - Minimalistic Clipboard Row
private struct ClipboardRowView: View {
    let item: ClipItem
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false
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
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                }
                Text(item.textValue ?? "")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)

            case .file:
                Image(systemName: "doc")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(item.previewTitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)

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
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.25 : 0.20)
                        : (isHovered
                           ? Color.white.opacity(colorScheme == .dark ? 0.08 : 0.15)
                           : Color.white.opacity(colorScheme == .dark ? 0.03 : 0.06))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.accentColor.opacity(0.6)
                        : (isHovered
                           ? Color.white.opacity(colorScheme == .dark ? 0.20 : 0.28)
                           : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12)),
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
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
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        } else {
            Image(systemName: "photo")
                .foregroundColor(.secondary)
                .frame(height: 36)
                .task(id: item.imageFileName) {
                    guard let url = ClipboardManager.shared.imageURL(for: item) else { return }
                    let key = item.imageFileName ?? url.lastPathComponent
                    thumbnail = await Task.detached(priority: .userInitiated) {
                        ThumbnailCache.load(url: url, key: key)
                    }.value
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

    static func load(url: URL, key: String) -> NSImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
        cache.setObject(image, forKey: key as NSString, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
