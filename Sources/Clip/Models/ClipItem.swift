import Foundation
import AppKit

public enum ClipType: String, Codable, CaseIterable {
    case text
    case code
    case link
    case color
    case image
    case file

    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .code: return "Code"
        case .link: return "Link"
        case .color: return "Color"
        case .image: return "Image"
        case .file: return "File"
        }
    }

    public var systemIcon: String {
        switch self {
        case .text: return "doc.text.fill"
        case .code: return "curlybraces"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .image: return "photo.fill"
        case .file: return "doc.fill"
        }
    }

    public var accentColorHex: String {
        switch self {
        case .text: return "#60A5FA"   // Blue
        case .code: return "#F472B6"   // Pink/Magenta
        case .link: return "#34D399"   // Emerald
        case .color: return "#FBBF24"  // Amber
        case .image: return "#A78BFA"  // Purple
        case .file: return "#38BDF8"   // Sky
        }
    }
}

public struct ClipItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var createdAt: Date
    public var type: ClipType
    public var textValue: String?
    public var rtfData: Data?
    public var htmlData: Data?
    public var imageFileName: String?
    public var imageWidth: CGFloat?
    public var imageHeight: CGFloat?
    public var imageHash: String?
    public var fileURLString: String?
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        type: ClipType,
        textValue: String? = nil,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        imageFileName: String? = nil,
        imageWidth: CGFloat? = nil,
        imageHeight: CGFloat? = nil,
        imageHash: String? = nil,
        fileURLString: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.type = type
        self.textValue = textValue
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageHash = imageHash
        self.fileURLString = fileURLString
        self.isPinned = isPinned
    }

    public var timeAgo: String {
        let seconds = -createdAt.timeIntervalSinceNow
        if seconds < 10 {
            return "just now"
        } else if seconds < 60 {
            return "\(Int(seconds))s ago"
        } else if seconds < 3600 {
            let mins = Int(seconds / 60)
            return "\(mins)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }

    public var previewTitle: String {
        if let text = textValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let firstLine = text.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? text
            return firstLine.isEmpty ? text : firstLine
        }
        if type == .image {
            if let w = imageWidth, let h = imageHeight {
                return "Image (\(Int(w)) × \(Int(h)))"
            }
            return "Image"
        }
        if let path = fileURLString {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "Clipboard Item"
    }

    public var isFileMissing: Bool {
        guard type == .file, let path = fileURLString else { return false }
        return !FileManager.default.fileExists(atPath: path)
    }

    public var previewSubtitle: String {
        switch type {
        case .link:
            if let text = textValue, let url = URL(string: text) {
                return url.host ?? text
            }
            return textValue ?? ""
        case .color:
            return textValue ?? ""
        case .image:
            if let w = imageWidth, let h = imageHeight {
                return "\(Int(w)) × \(Int(h)) px"
            }
            return "PNG Image"
        case .file:
            // fileURLString holds a plain filesystem path, not a URL string
            return fileURLString ?? "Local file"
        case .code:
            let lines = (textValue ?? "").components(separatedBy: .newlines).count
            let chars = (textValue ?? "").count
            return "\(lines) lines • \(chars) chars"
        case .text:
            let chars = (textValue ?? "").count
            let words = (textValue ?? "").split { $0.isWhitespace }.count
            return "\(words) words • \(chars) chars"
        }
    }

    public var detectedHexColor: NSColor? {
        guard type == .color, let text = textValue?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return NSColor(hex: text)
    }

    /// Normalized signature used to detect duplicate content across clipboard items
    public var uniquenessSignature: String {
        switch type {
        case .image:
            if let hash = imageHash {
                return "image:\(hash)"
            }
            if let fileName = imageFileName {
                return "image:\(fileName)"
            }
            return "image:\(id.uuidString)"

        case .file:
            if let path = fileURLString {
                let standardized = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
                return "file:\(standardized)"
            }
            return "file:\(textValue ?? "")"

        case .text, .code, .link, .color:
            if let text = textValue {
                let normalized = text
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .precomposedStringWithCanonicalMapping
                return "text:\(normalized)"
            }
            return "text:\(id.uuidString)"
        }
    }
}

// MARK: - Color Hex Extension
extension NSColor {
    convenience init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        if cleanHex.count == 3 {
            cleanHex = cleanHex.map { "\($0)\($0)" }.joined()
        }
        guard cleanHex.count == 6 || cleanHex.count == 8 else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&rgbValue) else { return nil }

        let r, g, b, a: CGFloat
        if cleanHex.count == 6 {
            r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgbValue & 0x0000FF) / 255.0
            a = 1.0
        } else {
            r = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgbValue & 0x000000FF) / 255.0
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
