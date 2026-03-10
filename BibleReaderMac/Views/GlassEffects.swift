import SwiftUI
import AppKit

// MARK: - NSVisualEffectView Representable

/// Wraps NSVisualEffectView for deep macOS vibrancy integration.
/// Provides liquid glass translucency that responds to window background content.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State
    let isEmphasized: Bool

    init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .followsWindowActiveState,
        isEmphasized: Bool = true
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.isEmphasized = isEmphasized
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
    }
}

// MARK: - View Modifiers

/// Applies a frosted glass panel background with rounded corners.
struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: NSVisualEffectView.Material
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                VisualEffectBackground(
                    material: material,
                    blendingMode: .withinWindow,
                    isEmphasized: true
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
    }
}

/// Applies a full-bleed vibrancy background (no rounding — for sidebars, headers, toolbars).
struct VibrancyBackgroundModifier: ViewModifier {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func body(content: Content) -> some View {
        content
            .background {
                VisualEffectBackground(
                    material: material,
                    blendingMode: blendingMode,
                    isEmphasized: true
                )
            }
    }
}

/// Adds a subtle inner glow/highlight at the top edge for depth.
struct GlassEdgeHighlightModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.white.opacity(0.12), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 1)
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Liquid glass panel — frosted translucent card with border highlight.
    func glassPanel(
        cornerRadius: CGFloat = 12,
        material: NSVisualEffectView.Material = .hudWindow,
        padding: CGFloat = 0
    ) -> some View {
        modifier(GlassPanelModifier(
            cornerRadius: cornerRadius,
            material: material,
            padding: padding
        ))
    }

    /// Full-bleed vibrancy background for sidebars, headers, toolbars.
    func vibrancyBackground(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) -> some View {
        modifier(VibrancyBackgroundModifier(
            material: material,
            blendingMode: blendingMode
        ))
    }

    /// Subtle top-edge highlight for glass depth.
    func glassEdgeHighlight() -> some View {
        modifier(GlassEdgeHighlightModifier())
    }

    /// Header bar style: within-window vibrancy + bottom separator highlight.
    func glassHeader() -> some View {
        self
            .vibrancyBackground(material: .headerView, blendingMode: .withinWindow)
            .glassEdgeHighlight()
    }

    /// Toolbar/bar area: behind-window sidebar material.
    func glassToolbar() -> some View {
        self.vibrancyBackground(material: .titlebar, blendingMode: .withinWindow)
    }

    /// Floating popover/sheet glass style.
    func glassSheet() -> some View {
        self.vibrancyBackground(material: .popover, blendingMode: .behindWindow)
    }
}
