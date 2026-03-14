import SwiftUI

/// Applies .glassEffect on macOS 26+, falls back to ultraThinMaterial on older versions.
/// Uses a fully rounded shape so the sidebar looks like a floating glass panel.
private struct SidebarGlassModifier: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(Color.accentColor.opacity(0.08)), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

struct ContentView: View {
    @Environment(BibleStore.self) private var bibleStore
    @Environment(UserDataStore.self) private var userDataStore
    @Environment(UIStateStore.self) private var uiStateStore

    private let sidebarWidth: CGFloat = 260
    private let sidebarInset: CGFloat = 8

    var body: some View {
        ZStack(alignment: .leading) {
            // Bottom layer: ReaderArea always occupies full width, respects safe areas
            ReaderArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(0)

            // Dismiss overlay: closes sidebar when tapping outside
            if uiStateStore.sidebarVisible {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        uiStateStore.sidebarVisible = false
                    }
                    .ignoresSafeArea()
                    .zIndex(1)
            }

            // Top layer: Floating glass sidebar — extends behind title bar
            GeometryReader { geometry in
                SidebarView(sidebarHeight: geometry.size.height - sidebarInset * 2)
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .modifier(SidebarGlassModifier())
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 2, y: 0)
                    .padding(sidebarInset)
            }
            .frame(width: sidebarWidth + sidebarInset * 2)
            .ignoresSafeArea(edges: .top)
            .offset(x: uiStateStore.sidebarVisible ? 0 : -(sidebarWidth + sidebarInset * 2))
            .allowsHitTesting(uiStateStore.sidebarVisible)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: uiStateStore.sidebarVisible)
            .zIndex(2)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    uiStateStore.sidebarVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help(String(localized: "toolbar.toggleSidebar"))
            }

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    if uiStateStore.fontSize > 10 {
                        uiStateStore.fontSize -= 1
                    }
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .help(String(localized: "toolbar.decreaseFontSize"))

                Button {
                    if uiStateStore.fontSize < 40 {
                        uiStateStore.fontSize += 1
                    }
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help(String(localized: "toolbar.increaseFontSize"))
            }

ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help(String(localized: "toolbar.settings"))
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

}
