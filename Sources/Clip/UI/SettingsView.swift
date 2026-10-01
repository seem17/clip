import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var settings = ClipSettings.shared
    @ObservedObject var launchAtLogin = LaunchAtLoginManager.shared
    @ObservedObject var clipboardManager = ClipboardManager.shared

    @State private var showingClearConfirmation = false
    @State private var isAccessibilityGranted: Bool = PasteHelper.isAccessibilityGranted
    @Environment(\.colorScheme) var colorScheme

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clip Settings")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Customize clipboard behavior, shortcuts, and appearance")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            // Settings Content
            ScrollView {
                VStack(spacing: 18) {
                    // Section: General Behavior
                    settingsSection(title: "Behavior") {
                        // Launch at Login
                        settingRow(
                            title: "Launch at Login",
                            subtitle: "Automatically start Clip when Mac turns on"
                        ) {
                            Toggle("", isOn: Binding(
                                get: { launchAtLogin.isEnabled },
                                set: { launchAtLogin.setLaunchAtLogin(enabled: $0) }
                            ))
                            .toggleStyle(.switch)
                        }

                        Divider()

                        // Auto-paste
                        settingRow(
                            title: "Direct Auto-Paste",
                            subtitle: "Paste directly into active app on selection"
                        ) {
                            Toggle("", isOn: $settings.autoPaste)
                                .toggleStyle(.switch)
                        }

                        if settings.autoPaste {
                            if isAccessibilityGranted {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 12))
                                    Text("Accessibility permission granted • Auto-paste active")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                    Spacer()
                                }
                                .padding(.top, 2)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 12))
                                    Text("Permission needed: toggle Clip in System Settings")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Grant Access") {
                                        PasteHelper.promptForAccessibility()
                                    }
                                    .font(.system(size: 11))
                                }
                                .padding(.top, 2)
                            }
                        }

                        Divider()

                        // Sound Effects
                        settingRow(
                            title: "Sound Effect",
                            subtitle: "Play subtle sound when an item is pasted"
                        ) {
                            Toggle("", isOn: $settings.playSounds)
                                .toggleStyle(.switch)
                        }
                    }

                    // Section: Capacity & Storage
                    settingsSection(title: "History Capacity") {
                        settingRow(
                            title: "History Limit",
                            subtitle: "Number of copied items to retain (FIFO)"
                        ) {
                            HStack(spacing: 8) {
                                Stepper(value: $settings.historyLimit, in: 10...100, step: 5) {
                                    Text("\(settings.historyLimit) items")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .frame(width: 75, alignment: .trailing)
                                }
                            }
                        }

                        Divider()

                        // Stored Items & Clear
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current Items")
                                    .font(.system(size: 13, weight: .medium))
                                Text("\(clipboardManager.items.count) of \(settings.historyLimit) items saved")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive, action: { showingClearConfirmation = true }) {
                                Text("Clear History")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Section: Appearance
                    settingsSection(title: "Appearance") {
                        // Window Width
                        settingRow(
                            title: "Palette Width",
                            subtitle: "Width of the floating list palette"
                        ) {
                            Picker("", selection: $settings.windowWidth) {
                                Text("Compact (300 px)").tag(CGFloat(300))
                                Text("Standard (340 px)").tag(CGFloat(340))
                                Text("Wide (400 px)").tag(CGFloat(400))
                            }
                            .pickerStyle(.menu)
                            .frame(width: 160)
                        }

                        Divider()

                        // Window Height
                        settingRow(
                            title: "Palette Height",
                            subtitle: "Height of the floating list palette"
                        ) {
                            Picker("", selection: $settings.windowHeight) {
                                Text("Small (360 px)").tag(CGFloat(360))
                                Text("Medium (420 px)").tag(CGFloat(420))
                                Text("Large (500 px)").tag(CGFloat(500))
                            }
                            .pickerStyle(.menu)
                            .frame(width: 160)
                        }

                        Divider()

                        // Text Preview Lines
                        settingRow(
                            title: "Text Preview Lines",
                            subtitle: "Maximum lines shown per text item"
                        ) {
                            Picker("", selection: $settings.previewLines) {
                                Text("1 line").tag(1)
                                Text("2 lines").tag(2)
                                Text("3 lines").tag(3)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 160)
                        }
                    }

                    // Section: Shortcut Reference
                    settingsSection(title: "Shortcut") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Global Hotkey")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Press anywhere on macOS to open the list")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text("⇧ ⌘ V")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    // Creator Credit
                    HStack {
                        Spacer()
                        Text("Created by SEEM")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.6))
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)

                Spacer()

                Text("SEEM")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.15))
                    .clipShape(Capsule())

                Spacer()

                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05))
        }
        .frame(width: 520, height: 540)
        .onAppear {
            isAccessibilityGranted = PasteHelper.isAccessibilityGranted
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            isAccessibilityGranted = PasteHelper.isAccessibilityGranted
        }
        .confirmationDialog(
            "Clear all clipboard history?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                clipboardManager.clearAll(includePinned: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all copied items and cached images.")
        }
    }

    // MARK: - Helper Builders
    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .background(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.2))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.2), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func settingRow<Control: View>(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .layoutPriority(1)

            Spacer(minLength: 16)

            control()
        }
    }
}
