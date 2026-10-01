import Foundation
import ServiceManagement

public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    @Published public private(set) var isEnabled: Bool = false

    private let launchAgentIdentifier = "com.clip.app.launcher"
    private var launchAgentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(launchAgentIdentifier).plist")
    }

    private init() {
        self.isEnabled = checkLaunchAtLoginStatus()
    }

    public func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
                self.isEnabled = (SMAppService.mainApp.status == .enabled)
                if self.isEnabled == enabled {
                    return
                }
            } catch {
                print("SMAppService toggle failed: \(error). Falling back to LaunchAgent...")
            }
        }

        // Fallback: Manage user LaunchAgent plist
        toggleLaunchAgent(enabled: enabled)
        self.isEnabled = enabled
    }

    private func checkLaunchAtLoginStatus() -> Bool {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                return true
            }
        }
        return FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    private func toggleLaunchAgent(enabled: Bool) {
        let fileManager = FileManager.default
        if enabled {
            let appBundlePath = Bundle.main.bundlePath
            let executablePath = Bundle.main.executablePath ?? (appBundlePath + "/Contents/MacOS/Clip")

            let plistContent: [String: Any] = [
                "Label": launchAgentIdentifier,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive"
            ]

            let dir = launchAgentPlistURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

            if let data = try? PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0) {
                try? data.write(to: launchAgentPlistURL)
            }
        } else {
            try? fileManager.removeItem(at: launchAgentPlistURL)
        }
    }
}
