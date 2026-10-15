import Cocoa
import SwiftUI
import Combine

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private var previouslyActiveApp: NSRunningApplication?
    private let clipboardManager = ClipboardManager.shared
    private let hotkeyManager = HotkeyManager.shared
    private let launchAtLoginManager = LaunchAtLoginManager.shared
    private var cancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        setupHotkey()
    }

    // MARK: - Menubar Status Item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Use SF Symbol "paperclip"
        let icon = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clip")
        icon?.isTemplate = true
        button.image = icon
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let currentEvent = NSApp.currentEvent
        if currentEvent?.type == .rightMouseUp || currentEvent?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Clip", action: #selector(togglePanel), keyEquivalent: "v")
        showItem.keyEquivalentModifierMask = [.command, .shift]
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at login item
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        loginItem.state = launchAtLoginManager.isEnabled ? .on : .off
        loginItem.target = self
        menu.addItem(loginItem)

        // Clear history item
        let clearItem = NSMenuItem(
            title: "Clear History (\(clipboardManager.items.count) items)",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(NSMenuItem.separator())

        // Settings item (without system icon)
        let settingsItem = NSMenuItem(
            title: "\u{200B}Settings...",
            action: #selector(showSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Clip", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Reset so normal clicks work again
    }

    @objc private func showSettingsWindow() {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newState = !launchAtLoginManager.isEnabled
        launchAtLoginManager.setLaunchAtLogin(enabled: newState)
        sender.state = newState ? .on : .off
    }

    @objc private func clearHistory() {
        clipboardManager.clearAll()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Floating Panel Setup
    private func setupPanel() {
        let settings = ClipSettings.shared
        let panelRect = NSRect(x: 0, y: 0, width: settings.windowWidth, height: settings.windowHeight)
        let floatingPanel = FloatingPanel(contentRect: panelRect)

        let contentView = ClipboardListView(
            onDismiss: { [weak self] in
                self?.hidePanel()
            },
            onPasteItem: { [weak self] item in
                self?.pasteAndDismiss(item: item)
            }
        )

        floatingPanel.contentView = NSHostingView(rootView: contentView)

        floatingPanel.onSelectionMove = { [weak self] delta in
            guard let self = self else { return }
            let items = self.clipboardManager.items
            guard !items.isEmpty else { return }

            let currentIndex = items.firstIndex { $0.id == self.clipboardManager.selectedItemID } ?? 0
            let newIndex = max(0, min(items.count - 1, currentIndex + delta))
            self.clipboardManager.selectedItemID = items[newIndex].id
            if newIndex <= 1 {
                self.resetScrollToTop()
            }
        }

        floatingPanel.onConfirmSelection = { [weak self] in
            guard let self = self else { return }
            if let selectedID = self.clipboardManager.selectedItemID,
               let item = self.clipboardManager.items.first(where: { $0.id == selectedID }) {
                self.pasteAndDismiss(item: item)
            } else if let first = self.clipboardManager.items.first {
                self.pasteAndDismiss(item: first)
            }
        }

        floatingPanel.onDismissRequested = { [weak self] in
            self?.hidePanel()
        }

        floatingPanel.onDeleteSelection = { [weak self] in
            guard let self = self else { return }
            if let selectedID = self.clipboardManager.selectedItemID {
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.clipboardManager.deleteItem(withID: selectedID)
                }
            }
        }

        floatingPanel.updateAppearance(mode: settings.appearanceMode)

        settings.$appearanceMode
            .receive(on: DispatchQueue.main)
            .sink { [weak floatingPanel] mode in
                floatingPanel?.updateAppearance(mode: mode)
            }
            .store(in: &cancellables)

        settings.$windowWidth.combineLatest(settings.$windowHeight)
            .receive(on: DispatchQueue.main)
            .sink { [weak floatingPanel] width, height in
                floatingPanel?.setContentSize(NSSize(width: width, height: height))
                floatingPanel?.invalidateShadow()
            }
            .store(in: &cancellables)

        self.panel = floatingPanel
    }

    // MARK: - Hotkey Setup
    private func setupHotkey() {
        hotkeyManager.onTrigger = { [weak self] in
            self?.togglePanel()
        }
        hotkeyManager.registerDefaultHotkey()
    }

    // MARK: - Show / Hide / Paste Logic
    @objc public func togglePanel() {
        guard let panel = panel else { return }

        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    public func showPanel() {
        // Record frontmost application before showing
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previouslyActiveApp = frontmost
        }

        // Always reset selection to second item and scroll to top on open
        clipboardManager.resetSelectionForOpen()
        resetScrollToTop()

        panel?.showPanel()
    }

    public func hidePanel() {
        panel?.hidePanel()
    }

    private func resetScrollToTop() {
        guard let panel = panel, let contentView = panel.contentView else { return }
        if let scrollView = findScrollView(in: contentView) {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let sv = view as? NSScrollView { return sv }
        for subview in view.subviews {
            if let sv = findScrollView(in: subview) { return sv }
        }
        return nil
    }

    private func pasteAndDismiss(item: ClipItem) {
        let targetApp = self.previouslyActiveApp
        panel?.hidePanel {
            PasteHelper.pasteItem(item, previouslyActiveApp: targetApp)
        }
    }
}
