import Foundation
import SwiftUI
import Combine

public final class ClipSettings: ObservableObject {
    public static let shared = ClipSettings()

    private let defaults = UserDefaults.standard

    // Keys
    private let kHistoryLimit = "clip_historyLimit"
    private let kAutoPaste = "clip_autoPaste"
    private let kPlaySounds = "clip_playSounds"
    private let kPreviewLines = "clip_previewLines"
    private let kWindowWidth = "clip_windowWidth"
    private let kWindowHeight = "clip_windowHeight"
    private let kAppearanceMode = "clip_appearanceMode"

    public enum AppearanceMode: String, CaseIterable, Identifiable {
        case system = "System"
        case dark = "Dark"
        case light = "Light"

        public var id: String { rawValue }
    }

    @Published public var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: kAppearanceMode)
        }
    }

    @Published public var historyLimit: Int {
        didSet {
            defaults.set(historyLimit, forKey: kHistoryLimit)
            ClipboardManager.shared.enforceLimit()
        }
    }

    @Published public var autoPaste: Bool {
        didSet {
            defaults.set(autoPaste, forKey: kAutoPaste)
        }
    }

    @Published public var playSounds: Bool {
        didSet {
            defaults.set(playSounds, forKey: kPlaySounds)
        }
    }

    @Published public var previewLines: Int {
        didSet {
            defaults.set(previewLines, forKey: kPreviewLines)
        }
    }

    @Published public var windowWidth: CGFloat {
        didSet {
            defaults.set(Double(windowWidth), forKey: kWindowWidth)
        }
    }

    @Published public var windowHeight: CGFloat {
        didSet {
            defaults.set(Double(windowHeight), forKey: kWindowHeight)
        }
    }

    private init() {
        if let savedAppearance = defaults.string(forKey: kAppearanceMode),
           let mode = AppearanceMode(rawValue: savedAppearance) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }
        self.historyLimit = defaults.object(forKey: kHistoryLimit) != nil ? defaults.integer(forKey: kHistoryLimit) : 30
        self.autoPaste = defaults.object(forKey: kAutoPaste) != nil ? defaults.bool(forKey: kAutoPaste) : true
        self.playSounds = defaults.object(forKey: kPlaySounds) != nil ? defaults.bool(forKey: kPlaySounds) : false
        self.previewLines = defaults.object(forKey: kPreviewLines) != nil ? defaults.integer(forKey: kPreviewLines) : 2
        let savedWidth = defaults.double(forKey: kWindowWidth)
        self.windowWidth = savedWidth > 200 ? CGFloat(savedWidth) : 320
        let savedHeight = defaults.double(forKey: kWindowHeight)
        self.windowHeight = savedHeight > 200 ? CGFloat(savedHeight) : 400
    }

    public func resetToDefaults() {
        self.appearanceMode = .system
        self.historyLimit = 30
        self.autoPaste = true
        self.playSounds = false
        self.previewLines = 2
        self.windowWidth = 320
        self.windowHeight = 400
    }
}
