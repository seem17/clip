import AppKit
import SwiftUI

public final class FloatingPanel: NSPanel {
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    public var onSelectionMove: ((Int) -> Void)?
    public var onConfirmSelection: (() -> Void)?
    public var onDismissRequested: (() -> Void)?

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.animationBehavior = .utilityWindow

        setupKeyboardMonitoring()
    }

    override public var canBecomeKey: Bool {
        return true
    }

    override public var canBecomeMain: Bool {
        return true
    }

    public func showPanel() {
        centerOnActiveScreen()
        self.alphaValue = 0
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }

        setupOutsideClickMonitor()
    }

    public func hidePanel(completion: (() -> Void)? = nil) {
        removeOutsideClickMonitor()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }

    public func centerOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let targetScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? screens.first

        if let screen = targetScreen {
            let visibleFrame = screen.visibleFrame
            let panelSize = self.frame.size
            let x = visibleFrame.origin.x + (visibleFrame.width - panelSize.width) / 2
            let y = visibleFrame.origin.y + (visibleFrame.height - panelSize.height) / 2 + 40
            self.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            self.center()
        }
    }

    private func setupKeyboardMonitoring() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }

            switch event.keyCode {
            case 126: // Up arrow
                self.onSelectionMove?(-1)
                return nil
            case 125: // Down arrow
                self.onSelectionMove?(1)
                return nil
            case 36, 76: // Return / Enter
                self.onConfirmSelection?()
                return nil
            case 53:  // Escape
                self.onDismissRequested?()
                return nil
            default:
                return event
            }
        }
    }

    private func setupOutsideClickMonitor() {
        removeOutsideClickMonitor()
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isVisible else { return }
            let clickLocation = NSEvent.mouseLocation
            if !NSPointInRect(clickLocation, self.frame) {
                self.onDismissRequested?()
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    deinit {
        if let local = localEventMonitor {
            NSEvent.removeMonitor(local)
        }
        removeOutsideClickMonitor()
    }
}
