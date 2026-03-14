import SwiftUI

/// Applies .glassEffect on macOS 26+, falls back to translucent material on older versions.
private struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

/// Floating glass bubble with color swatches for highlighting a verse.
/// Shows 5 highlight colors + a clear (X) button to remove highlights.
struct HighlightBubble: View {
    let isHighlighted: Bool
    let onColorSelected: (BookmarkColor) -> Void
    let onClear: () -> Void

    private let swatchSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BookmarkColor.allCases, id: \.self) { color in
                Button {
                    onColorSelected(color)
                } label: {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: swatchSize, height: swatchSize)
                }
                .buttonStyle(.plain)
            }

            // Clear / remove highlight button
            Button {
                onClear()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
                        .frame(width: swatchSize, height: swatchSize)
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .opacity(isHighlighted ? 1.0 : 0.4)
            .disabled(!isHighlighted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(GlassEffectModifier())
    }
}
