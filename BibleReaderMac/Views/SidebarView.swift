import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: BibleStore
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Navigation") {
                Label("Reader", systemImage: "book")
                    .tag(SidebarItem.reader)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
                Label("Strong's Concordance", systemImage: "character.book.closed")
                    .tag(SidebarItem.strongs)
                Label("Bookmarks", systemImage: "bookmark")
                    .tag(SidebarItem.bookmarks)
                Label("Notes", systemImage: "note.text")
                    .tag(SidebarItem.notes)
                Label("Cross References", systemImage: "arrow.triangle.branch")
                    .tag(SidebarItem.crossRefs)
            }

            Section("Translations (\(store.loadedTranslations.count))") {
                ForEach(store.loadedTranslations) { translation in
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(translation.abbreviation)
                                    .font(.callout.weight(.medium))
                                Text(translation.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "book.closed")
                        }
                    }
                    .contextMenu {
                        Button("Remove Translation") {
                            store.removeTranslation(translation.id)
                        }
                    }
                }
                if store.loadedTranslations.isEmpty {
                    Text("No translations loaded")
                        .foregroundStyle(.secondary)
                        .italic()
                }
                Button(action: {
                    NotificationCenter.default.post(name: .importModule, object: nil)
                }) {
                    Label("Import Module...", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.accentColor)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("BibleReader")
    }
}

enum SidebarItem: Hashable {
    case reader
    case search
    case strongs
    case bookmarks
    case notes
    case crossRefs
}
