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
        // Diff before setting to avoid unnecessary AppKit invalidation passes
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
        if nsView.state != state { nsView.state = state }
        if nsView.isEmphasized != isEmphasized { nsView.isEmphasized = isEmphasized }
    }
}

// MARK: - Flat Minimalist Button Style (Reader pane toolbar buttons)
//
// Larger hit target, flat design, high-contrast foreground.
// Shows a crisp filled rounded-rect background on hover/press.
// Active state uses accent color fill.

struct FlatToolbarButtonStyle: ButtonStyle {
    var isActive: Bool = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(configuration: configuration))
            }
            .foregroundStyle(isActive ? Color.accentColor : (isHovered || configuration.isPressed ? Color.primary : Color.primary.opacity(0.65)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if isActive {
            return Color.accentColor.opacity(configuration.isPressed ? 0.25 : 0.15)
        }
        if configuration.isPressed {
            return Color.primary.opacity(0.14)
        }
        if isHovered {
            return Color.primary.opacity(0.08)
        }
        return Color.clear
    }
}

extension ButtonStyle where Self == FlatToolbarButtonStyle {
    static var flatToolbar: FlatToolbarButtonStyle { FlatToolbarButtonStyle() }
    static func flatToolbar(isActive: Bool) -> FlatToolbarButtonStyle {
        FlatToolbarButtonStyle(isActive: isActive)
    }
}

// MARK: - Glass Capsule Button Style
//
// 3D frosted-glass pill — full blur behind-window vibrancy,
// top specular, gradient border, drop shadow.

struct GlassCapsuleButtonStyle: ButtonStyle {
    var alwaysShowBackground: Bool = true
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(pillBackground(configuration: configuration))
            .overlay(pillBorder(configuration: configuration))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.05 : 0.20),
                    radius: configuration.isPressed ? 1 : 5,
                    x: 0, y: configuration.isPressed ? 0.5 : 2)
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func pillBackground(configuration: Configuration) -> some View {
        ZStack {
            if alwaysShowBackground || configuration.isPressed {
                VisualEffectBackground(
                    material: isActive ? .selection : .hudWindow,
                    blendingMode: .behindWindow,
                    isEmphasized: isActive
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                if isActive {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                }
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.primary.opacity(0.1))
                }
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.20), .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.55)
                        )
                    )
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func pillBorder(configuration: Configuration) -> some View {
        if alwaysShowBackground || configuration.isPressed {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
    }
}

extension ButtonStyle where Self == GlassCapsuleButtonStyle {
    static var glassCapsule: GlassCapsuleButtonStyle { GlassCapsuleButtonStyle() }
    static func glassCapsule(alwaysShow: Bool = true, isActive: Bool = false) -> GlassCapsuleButtonStyle {
        GlassCapsuleButtonStyle(alwaysShowBackground: alwaysShow, isActive: isActive)
    }
}

// MARK: - Glass Icon Button Style
// Compact square icon button — pill only on press, no persistent background.
// Useful for embedded inline buttons where persistent pill would be too noisy.

struct GlassIconButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background {
                ZStack {
                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.primary.opacity(0.12))
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    }
                }
            }
            .scaleEffect(configuration.isPressed ? 0.91 : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.72), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension ButtonStyle where Self == GlassIconButtonStyle {
    static var glassIcon: GlassIconButtonStyle { GlassIconButtonStyle() }
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

// MARK: - Panel Tab Button (legacy, kept for any remaining call sites)
//
// Liquid glass 3D floating pill for sidebar/inspector panel tab switching.
// Uses GlassCapsuleButtonStyle: NSVisualEffectView vibrancy + specular top highlight
// + gradient border + drop shadow + spring press scale animation.

struct PanelTabButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.70))
        }
        .buttonStyle(.glassCapsule(alwaysShow: true, isActive: isSelected))
        .animation(.spring(response: 0.18, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Glass Segmented Picker
//
// Wraps NSSegmentedControl with .rounded style — the exact control used by macOS
// Calendar (Day | Week | Month | Year). Gives the native dark pill container with
// a lighter rounded-rect selected indicator, no blue tint, no word-wrap.

struct GlassSegmentedPicker<T: Hashable & CaseIterable>: NSViewRepresentable
    where T.AllCases: RandomAccessCollection
{
    @Binding var selection: T
    let labelForCase: (T) -> String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentStyle = .rounded
        control.trackingMode = .selectOne
        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))

        let cases = Array(T.allCases)
        control.segmentCount = cases.count
        for (i, option) in cases.enumerated() {
            control.setLabel(labelForCase(option), forSegment: i)
            // Let each segment auto-size to its label — prevents word-wrap
            control.setWidth(0, forSegment: i)
        }

        // Set initial selection
        if let idx = cases.firstIndex(of: selection) {
            control.selectedSegment = idx
        }

        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        let cases = Array(T.allCases)

        // Sync labels in case language changed
        for (i, option) in cases.enumerated() {
            control.setLabel(labelForCase(option), forSegment: i)
        }

        // Sync selected segment
        if let idx = cases.firstIndex(of: selection),
           control.selectedSegment != idx {
            control.selectedSegment = idx
        }
    }

    @MainActor
    class Coordinator: NSObject {
        var parent: GlassSegmentedPicker

        init(_ parent: GlassSegmentedPicker) {
            self.parent = parent
        }

        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let cases = Array(T.allCases)
            let idx = sender.selectedSegment
            guard idx >= 0 && idx < cases.count else { return }
            parent.selection = cases[idx]
        }
    }
}
