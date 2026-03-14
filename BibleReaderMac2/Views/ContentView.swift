import SwiftUI

/// Applies .glassEffect on macOS 26+, falls back to ultraThinMaterial on older versions.
private struct SidebarGlassModifier: ViewModifier {
    private let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 16, topTrailingRadius: 16)

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(Glass(tint: Color.accentColor.opacity(0.08)), in: shape)
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

    var body: some View {
        GeometryReader { geometry in
        ZStack(alignment: .leading) {
            // Bottom layer: ReaderArea always occupies full width
            ReaderArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top layer: Sidebar overlay with glass effect
            SidebarView(sidebarHeight: geometry.size.height)
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .modifier(SidebarGlassModifier())
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 16, topTrailingRadius: 16))
                .offset(x: uiStateStore.sidebarVisible ? 0 : -sidebarWidth)
                .allowsHitTesting(uiStateStore.sidebarVisible)
                .animation(.spring(duration: 0.35, bounce: 0.2), value: uiStateStore.sidebarVisible)
        }
        } // GeometryReader
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
