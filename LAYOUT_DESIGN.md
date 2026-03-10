# macOS BibleReaderMac — Layout & Navigation Design

## Design Philosophy
Mirror the Windows 3-column layout using native macOS patterns:
- `NavigationSplitView` sidebar (left) → matches Windows collapsible sidebar
- Main content area (center) → always the reader with split panes
- `.inspector()` modifier (right) → matches Windows collapsible right panels (Strong's/TSK)

The key change from current macOS: **the reader is ALWAYS visible** in the center.
Bookmarks, Notes, Search, History, etc. are accessed via sidebar tabs or overlays — they no longer replace the reader as a full detail view.

---

## Column Layout

```
┌──────────────┬──────────────────────────────┬──────────────────┐
│   SIDEBAR    │       MAIN CONTENT           │   INSPECTOR      │
│   250pt      │       (flexible)             │   280pt          │
│   collapsible│                              │   collapsible    │
│              │                              │                  │
│ [Tabs]       │  ┌─────────┬──────────┐      │  [Strong's]      │
│ 📑 Bookmarks │  │  Pane 1 │  Pane 2  │      │    or            │
│ 📝 Notes     │  │  KJV    │  RST     │      │  [Cross-Refs]    │
│ 📖 Modules   │  │         │          │      │    or            │
│              │  │         │          │      │  [Search Results] │
│ [Tab Content]│  │         │          │      │                  │
│ (contextual) │  │         │          │      │                  │
│              │  └─────────┴──────────┘      │                  │
└──────────────┴──────────────────────────────┴──────────────────┘
```

**Minimum window**: 900×600 (unchanged)
**Default window**: 1200×800 (unchanged)

---

## 1. LEFT SIDEBAR (NavigationSplitView sidebar)

### Sidebar Tabs (Segmented Control at top)
Three tabs matching Windows, using SF Symbols:

| Tab | Icon | Badge | Content |
|-----|------|-------|---------|
| Bookmarks | `bookmark.fill` | Count of bookmarks | Bookmark list (existing BookmarksView content) |
| Notes | `note.text` | Count of notes | Notes list with previews, tap to edit |
| Modules | `books.vertical` | Count of loaded translations | Translation list with management |

### Tab Content

**Bookmarks Tab:**
- Reuse existing BookmarksView content (search, filter, sort, group-by-book)
- Tap bookmark → navigate reader to that verse
- Swipe to delete (keep existing)
- Add label/note inline

**Notes Tab (NEW):**
- List of all notes, sorted newest-first
- Each row: verse reference, truncated preview (2 lines), timestamp
- Tap → open note editor sheet
- Swipe to delete
- "Export PDF" button at bottom

**Modules Tab:**
- List of loaded translations with drag-to-reorder (existing)
- Each row: abbreviation, name, verse count badge
- Context menu: Assign to Pane 1/2/3/4, Show Details, Remove
- "Import Module" button at bottom
- "Manage..." button → opens ManageTranslationsView sheet

### Sidebar Footer
- Settings gear button → opens Settings window
- History clock button → opens history popover/sheet

---

## 2. MAIN CONTENT AREA (Always the Reader)

The reader is **always visible** — never replaced by search/bookmarks/etc.

### Toolbar (above reader)

```
┌─────────────────────────────────────────────────────────────────┐
│ [🔍 Search Field]  │  [Sync] [+ Pane] [↕ Split] │ [📖] [✝]   │
│                     │                              │ Strong's/TSK│
└─────────────────────────────────────────────────────────────────┘
```

| Control | Placement | Behavior |
|---------|-----------|----------|
| Search field | `.principal` | macOS native `.searchable()` — results appear in inspector |
| Sync Scroll toggle | `.automatic` | Toggle linked/unlinked icon (keep existing) |
| Add Pane | `.automatic` | Add horizontal pane (up to 8) |
| Split Direction | `.automatic` | Menu: Split Right / Split Down (NEW) |
| Strong's toggle | `.automatic` | Toggle inspector → Strong's tab |
| Cross-Refs toggle | `.automatic` | Toggle inspector → Cross-Refs tab |
| Import | `.automatic` | Import module (Cmd+I) |

### Pane Layout

**Current:** HSplitView only (horizontal), max 4 panes
**New:** Support both horizontal and vertical splits, max 8 panes

Each pane keeps the existing header:
```
┌──────────────────────────────────────────────────────────────┐
│ [Translation▼] │ [Book▼] │ [◀ Ch ▼ ▶] │ [Sync🔗] │ [✕]    │
└──────────────────────────────────────────────────────────────┘
```

Changes to pane header:
- **Per-pane sync toggle** (replaces global toggle) — link/unlink icon per pane
- **Split Right / Split Down** context menu on each pane (not just toolbar)
- Close button only if >1 pane (keep existing)

### Verse Row (enhanced)

```
┌──────────────────────────────────────────────────────────────┐
│ [⭐][🎨][📝]  ¹ In the beginning God created the heaven...  │
│  action btns   verse#   verse text (clickable words)         │
└──────────────────────────────────────────────────────────────┘
```

**Left action column** (visible on hover, always visible if active):
| Button | Icon | Action |
|--------|------|--------|
| Bookmark | `bookmark` / `bookmark.fill` | Toggle bookmark |
| Highlight | `paintbrush` | Show 5-color picker popover |
| Note | `note.text` / `note.text.badge.plus` | Open note editor sheet |

**Verse text interactions:**
- Click word with Strong's data → populate inspector Strong's tab
- Hover word with Strong's → show tooltip with Strong's number
- Click verse number → populate inspector Cross-Refs tab
- Highlight colors rendered as background tint on verse row

**Highlight Color Picker (popover on highlight button):**
```
┌──────────────────────┐
│ 🟡 🟢 🔵 🟣 🔴  [✕] │
└──────────────────────┘
```
5 color circles + remove button. Tap to apply/change, ✕ to clear.

---

## 3. RIGHT INSPECTOR PANEL (.inspector modifier)

Uses SwiftUI `.inspector(isPresented:)` — native macOS inspector pattern.
Width: 280pt, collapsible via toolbar buttons or drag.

### Inspector Tabs (Segmented Control at top)

| Tab | Icon | Trigger |
|-----|------|---------|
| Strong's | `textformat.abc` | Word click in verse, or toolbar toggle |
| Cross-Refs | `link` | Verse number click, or toolbar toggle |
| Search | `magnifyingglass` | Search field entry, or Cmd+F |

### Strong's Tab Content
- Current verse word's Strong's entry (when triggered by word click)
- Number, lemma (RTL for Hebrew), transliteration, pronunciation
- Definition paragraph
- KJV usage with count badges (pills)
- "Verses Using This Word" — expandable list of clickable references (NEW)
- "Similar Matches" — collapsible section with related entries (NEW)
- "Open Full Browser" link → shows StrongsLookupView as sheet

### Cross-Refs Tab Content
- Current verse's TSK cross-references (forward + reverse, keep existing richness)
- Reference type badges (parallel/quotation/allusion/related)
- Each ref row: reference, preview text, "Go" button
- Navigation history back button (keep existing)
- Click ref → navigate active pane

### Search Results Tab Content
- Triggered when user types in toolbar search field
- Scope picker (Bible/OT/NT/Book/Chapter) — segmented control
- Module filter — checkboxes for loaded translations
- Result list:
  - Each result: reference, highlighted match, context verses (prev/next)
  - "Navigate" button → go to verse in active pane
  - "Sync All Panes" button → navigate all synced panes
  - "Open Parallel" button → open in new pane
- Result count display: "42 results" or "500+ results"

---

## 4. NAVIGATION FLOW

### How Features Are Accessed (old → new)

| Feature | Old (sidebar page) | New |
|---------|-------------------|-----|
| Reader | Sidebar → Reader | Always visible (center) |
| Search | Sidebar → SearchView | Toolbar search field → Inspector |
| Strong's Lookup | Sidebar → StrongsLookupView | Word click → Inspector; Full browser via sheet |
| Bookmarks | Sidebar → BookmarksView | Sidebar Bookmarks tab |
| History | Sidebar → HistoryView | Sidebar footer button → popover/sheet |
| Notes | Sidebar → placeholder | Sidebar Notes tab |
| Cross-Refs | Sidebar → CrossReferenceView | Verse# click → Inspector |
| Translations | Sidebar list | Sidebar Modules tab |
| Settings | Menu bar | Sidebar footer gear + menu bar |

### Keyboard Shortcuts (keep existing + add)

| Shortcut | Action |
|----------|--------|
| Cmd+F | Focus search field / toggle search inspector |
| Cmd+I | Import module |
| Cmd+D | Bookmark current verse |
| Cmd+\ | Add pane |
| Cmd+Shift+T | Manage translations |
| Cmd++/- | Font size |
| Cmd+←/→ | Prev/next chapter |
| Cmd+Shift+←/→ | Prev/next book |
| Cmd+1/2/3 | Switch sidebar tab (bookmarks/notes/modules) |
| Cmd+Opt+S | Toggle Strong's inspector |
| Cmd+Opt+R | Toggle Cross-Refs inspector |

---

## 5. NOTES SYSTEM (NEW)

### Data Model (already exists in BibleModels.swift)
```swift
struct Note: Identifiable, Codable {
    let id: UUID
    let verseReference: String
    var content: String
    let createdAt: Date
    var updatedAt: Date
}
```

### Note Editor (Sheet)
- Verse reference header (non-editable)
- TextEditor for note content
- Save / Delete buttons
- Saving empty content = delete note (Windows behavior)

### Notes List (Sidebar tab)
- Sorted by updatedAt descending
- Row: verse ref, 2-line preview, relative timestamp
- Tap → open editor sheet
- Swipe → delete

### PDF Export (Sheet)
- Checkbox list of notes to include
- Drag to reorder
- Translation picker for verse text
- "Export PDF" button → NSSavePanel

---

## 6. IMPLEMENTATION ORDER

Based on the structural changes needed:

1. **Restructure ContentView** — Remove detail router, make reader always-visible, add `.inspector()`
2. **Restructure SidebarView** — Replace navigation list with 3-tab segmented control
3. **Move search to inspector** — Adapt SearchView content for inspector panel
4. **Move Strong's to inspector** — Merge StrongsSidebarView into inspector tab
5. **Move cross-refs to inspector** — Adapt CrossReferenceView for inspector tab
6. **Add verse action buttons** — Bookmark/highlight/note buttons on VerseRow
7. **Implement highlight system** — Color picker popover, verse row background tints
8. **Implement notes system** — Editor sheet, sidebar tab, BibleStore methods
9. **Add vertical splits** — Extend pane layout to support split-down
10. **Per-pane sync toggle** — Move sync from global to per-pane
11. **Enhance search** — Context verses, sync-all, open-parallel, result count
12. **Strong's enhancements** — Word-level click, hover tooltips, similar matches, verse list

---

## 7. FILES TO MODIFY/CREATE

### Modify
- `ContentView.swift` — Remove detail router, add inspector, restructure layout
- `SidebarView.swift` — Replace nav list with tab system
- `ReaderView.swift` — Remove embedded Strong's sidebar, add verse action buttons
- `ReaderPaneView` (in ReaderView.swift) — Per-pane sync, vertical split support
- `WindowState.swift` — Add inspector state, active inspector tab, split direction
- `BibleStore.swift` — Add note CRUD methods, highlight methods
- `BibleModels.swift` — Add HighlightColor enum if not present

### Create
- `InspectorView.swift` — Right panel with 3 tabs (Strong's, Cross-Refs, Search)
- `NotesListView.swift` — Notes sidebar tab content
- `NoteEditorView.swift` — Note editing sheet
- `VerseActionButtons.swift` — Inline bookmark/highlight/note buttons
- `HighlightPickerView.swift` — 5-color popover picker
- `NotesExportView.swift` — PDF export sheet (lower priority)
