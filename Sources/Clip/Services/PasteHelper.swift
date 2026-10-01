import Foundation
import AppKit
import CoreGraphics

public struct PasteHelper {
    public static func pasteItem(_ item: ClipItem, previouslyActiveApp: NSRunningApplication? = nil) {
        ClipboardManager.shared.copyToPasteboard(item: item)

        if ClipSettings.shared.playSounds {
            NSSound(named: "Tink")?.play()
        }

        // Give focus back to the target application
        if let app = previouslyActiveApp {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        // Simulate Cmd+V only if autoPaste is enabled
        guard ClipSettings.shared.autoPaste else { return }

        // Simulate Cmd+V after slight delay to allow focus transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            simulateCmdV()
        }
    }

    public static func simulateCmdV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // Key code 9 is 'v' / 'V'
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    public static var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
}
