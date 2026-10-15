import SwiftUI
import AppKit

// MARK: - Visual Effect View Wrapper
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .popover,
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
    var cornerRadius: CGFloat = 10

    @Environment(\.colorScheme) var colorScheme

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(colorScheme == .dark ? 0.30 : 0.22)
                            : (isHovered
                               ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                               : (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.85),
                                    Color.accentColor.opacity(0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : (isHovered
                               ? LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white.opacity(0.24), Color.white.opacity(0.10)]
                                        : [Color.black.opacity(0.16), Color.black.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                 )
                               : LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white.opacity(0.12), Color.white.opacity(0.04)]
                                        : [Color.black.opacity(0.10), Color.black.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                 )),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .animation(.easeInOut(duration: 0.12), value: isSelected)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Liquid Glass Container
public struct LiquidGlassContainerModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) var colorScheme

    public func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    VisualEffectView(
                        material: .popover,
                        blendingMode: .behindWindow,
                        state: .active
                    )

                    // Protective tint: ensures rich depth and high contrast over white/light backgrounds
                    // while maintaining native frosted glass translucency and blur.
                    if colorScheme == .dark {
                        Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.55)
                    } else {
                        Color.white.opacity(0.60)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [
                                    Color.white.opacity(0.20),
                                    Color.white.opacity(0.06),
                                    Color.white.opacity(0.10)
                                ]
                                : [
                                    Color.black.opacity(0.12),
                                    Color.black.opacity(0.04),
                                    Color.black.opacity(0.08)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    public func liquidGlassCard(isSelected: Bool, isHovered: Bool, cornerRadius: CGFloat = 10) -> some View {
        self.modifier(LiquidGlassCardModifier(isSelected: isSelected, isHovered: isHovered, cornerRadius: cornerRadius))
    }

    public func liquidGlassContainer(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(LiquidGlassContainerModifier(cornerRadius: cornerRadius))
    }
}
