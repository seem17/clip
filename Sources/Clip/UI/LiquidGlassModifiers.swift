import SwiftUI
import AppKit

// MARK: - Visual Effect View Wrapper
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Liquid Glass Card Style
public struct LiquidGlassCardModifier: ViewModifier {
    var isSelected: Bool
    var isHovered: Bool
    var cornerRadius: CGFloat = 14

    @Environment(\.colorScheme) var colorScheme

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.16)
                            : (isHovered
                               ? Color.white.opacity(colorScheme == .dark ? 0.10 : 0.25)
                               : Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.8),
                                    Color.accentColor.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.35 : 0.18),
                                    Color.white.opacity(isHovered ? 0.12 : 0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .shadow(
                color: isSelected
                    ? Color.accentColor.opacity(0.25)
                    : (isHovered ? Color.black.opacity(0.12) : Color.clear),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 2 : 1
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Liquid Glass Container
public struct LiquidGlassContainerModifier: ViewModifier {
    var cornerRadius: CGFloat = 22
    @Environment(\.colorScheme) var colorScheme

    public func body(content: Content) -> some View {
        content
            .background {
                VisualEffectView(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    state: .active
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.32 : 0.55),
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.20),
                                Color.white.opacity(colorScheme == .dark ? 0.16 : 0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .shadow(color: Color.black.opacity(0.28), radius: 30, x: 0, y: 15)
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

extension View {
    public func liquidGlassCard(isSelected: Bool, isHovered: Bool, cornerRadius: CGFloat = 14) -> some View {
        self.modifier(LiquidGlassCardModifier(isSelected: isSelected, isHovered: isHovered, cornerRadius: cornerRadius))
    }

    public func liquidGlassContainer(cornerRadius: CGFloat = 22) -> some View {
        self.modifier(LiquidGlassContainerModifier(cornerRadius: cornerRadius))
    }
}
