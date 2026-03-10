# Windows vs macOS BibleReader — Feature Comparison

## Legend
- ✅ = Fully implemented in macOS
- ⚠️ = Partially implemented / different behavior
- ❌ = Missing from macOS

---

## 1. LAYOUT & STRUCTURE

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| 3-column layout (sidebar + content + right panels) | Flex layout: sidebar 256px + content + right panels | NavigationSplitView: sidebar + detail only | ⚠️ No dedicated right panel columns |
| Collapsible left sidebar | Toggle 64px↔256px with chevron | NavigationSplitView built-in collapse | ✅ |
| Strong's panel (right side, collapsible) | Dedicated right column, 36px↔256px | Sheet/sidebar within reader, toggle button | ⚠️ Different UX — not a persistent right column |
| TSK panel (right side, collapsible) | Dedicated right column, 36px↔256px | CrossReferenceView as separate sidebar page | ⚠️ Not a collapsible right panel |

## 2. SIDEBAR TABS & CONTENT

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Sidebar tab system (Bookmarks/Notes/Translations) | 3 icon tabs with badge counts | 7 navigation items (Reader, Search, Strong's, Bookmarks, History, Notes, Cross Refs) | ⚠️ Different organization — macOS has more items but different grouping |
| Bookmark panel in sidebar | Tab with inline list, click-to-nav, hover-delete | Dedicated BookmarksView page with search/filter/sort/group | ⚠️ macOS is more feature-rich but not inline in sidebar |
| Notes panel in sidebar | Tab with truncated previews, export PDF button | Placeholder only ("Coming soon") | ❌ Notes panel not implemented |
| Notes PDF export | Full export modal: select, reorder, choose versions, jsPDF output | Not implemented | ❌ |
| Manage Translations panel in sidebar | Tab with list, delete with confirmation | Separate ManageTranslationsView sheet | ✅ Different but equivalent |
| Settings button in sidebar | Gear icon in sidebar header | macOS native Settings window | ✅ |

## 3. SEARCH

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Search bar (collapsible) | Inline collapsible bar in main content area | Dedicated SearchView sidebar page | ⚠️ Different placement |
| Scope selector (Bible/OT/NT/Book/Chapter) | 5 pill buttons with book/chapter dropdowns | Segmented picker (same 5 scopes) | ✅ |
| Module filter | Searches active pane translation only | Popover with checkboxes to select multiple translations | ✅ macOS is better |
| Search results floating panel | Resizable floating panel between header and panes | Inline list in SearchView | ⚠️ Different presentation |
| Result: highlighted match text | Yellow highlight on search term | Orange background + bold white | ✅ |
| Result: context verses (prev/next) | Shows previous and next verse context | Not shown | ❌ |
| Result: "Sync All Panes" button | Per-result action (if 2+ panes) | Not implemented | ❌ |
| Result: "Open Parallel" button | Per-result hover action, adds new pane | Not implemented | ❌ |
| Result count cap display | Shows count or "500+" | Not shown | ❌ |
| Ctrl+F / Cmd+F shortcut | Opens inline search | Navigates to search view | ✅ |

## 4. READING AREA / VERSE DISPLAY

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Multi-pane layout (splits) | Recursive tree, horizontal/vertical splits, max 8 panes | HSplitView, horizontal only, max 4 panes | ⚠️ No vertical splits, fewer panes |
| Resizable split panes | Drag handles with min 10% constraint | macOS native HSplitView dividers | ✅ |
| Pane header: Book dropdown | Dropdown selector | Picker | ✅ |
| Pane header: Chapter dropdown | Dropdown selector | Chapter nav buttons + picker | ✅ |
| Pane header: Translation dropdown | Dropdown with built-in/imported optgroups | Picker | ✅ |
| Split Right button | PanelRightOpen icon per pane | Add Pane button in toolbar | ⚠️ Toolbar-level, not per-pane |
| Split Down button | PanelBottomOpen icon per pane | Not implemented | ❌ Vertical splits missing |
| Pop-out window button | Opens pane in standalone Tauri window | Not implemented | ❌ |
| Close pane button | Per-pane X button (if multi-pane) | Per-pane close button | ✅ |
| Sync toggle per pane | Link/Unlink icon per pane header | Global sync scroll toggle in toolbar | ⚠️ Global vs per-pane |
| Verse action column (left of verse) | Bookmark + Highlight + Note buttons per verse | Bookmark toggle only, via context menu | ⚠️ Missing highlight picker and note button inline |
| Verse number click → TSK | Click verse number opens TSK panel | Context menu → cross-ref option | ⚠️ Different interaction |
| Word click → Strong's | Click word with Strong's → opens Strong's panel | Tap verse → loads all Strong's for verse in sidebar | ⚠️ Different granularity (word vs verse) |
| Strong's number tooltip on word hover | Title attribute shows Strong's number | Not implemented | ❌ |
| Verse highlight colors (5 colors) | Inline color picker per verse | Data model exists, UI not rendered | ❌ |
| Highlight color picker | 5 color pills + remove button | Not implemented | ❌ |
| Scroll sync across panes | Synced panes propagate navigation | ScrollSyncCoordinator with visible verse tracking | ✅ |

## 5. STRONG'S CONCORDANCE

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Right-side collapsible panel | Dedicated right column 36px↔256px | StrongsSidebarView as overlay within reader | ⚠️ Different container |
| Full-page Strong's browser | Not separate — integrated in right panel | StrongsLookupView as sidebar page | ✅ macOS has dedicated page |
| Search by Strong's number or word | Via word click in verse only | Text input search (H1234, G3056, or word) | ✅ macOS is better |
| Exact match card (blue highlight) | Large detailed card with "BEST MATCH" label | Detail pane in HSplitView | ⚠️ Different presentation |
| Similar matches section | Amber-highlighted collapsible cards | Not implemented | ❌ |
| Lemma display (RTL for Hebrew) | Large serif text, RTL for Hebrew | Shown in detail, RTL not confirmed | ⚠️ |
| Transliteration + pronunciation | Italic + parentheses | Shown in detail | ✅ |
| Definition section | Paragraph format | Shown in detail | ✅ |
| KJV usage with word×count pills | Parsed word list with count badges | Shown as text | ⚠️ No pill badges |
| "Verses Using This Word" list | Collapsible, up to 300 refs, clickable | Not implemented | ❌ |
| Testament filter | Not available | Segmented picker (All/Hebrew OT/Greek NT) | ✅ macOS is better |

## 6. CROSS-REFERENCES (TSK)

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Right-side collapsible panel | Dedicated right column | CrossReferenceView as sidebar page | ⚠️ Different container |
| Click verse number to load | Direct verse number click | Context menu or manual input | ⚠️ |
| Reference list with context | Blue link buttons with short context | Rows with type badge, preview text, colors | ✅ macOS is richer |
| Click ref → navigate active pane | Direct navigation | "Open in Reader" button | ✅ |
| Forward + reverse references | Forward only (TSK data) | Forward AND reverse references | ✅ macOS is better |
| Navigation history stack | Not implemented | Back button with history stack | ✅ macOS is better |
| Reference type badges | Not shown | Colored badges (parallel/quotation/allusion/related) | ✅ macOS is better |

## 7. NOTES

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Note editor modal | Portal modal with textarea, delete, save | Not implemented (placeholder) | ❌ |
| Note button per verse | NotebookPen icon, filled/hollow state | Not implemented | ❌ |
| Notes list panel | Sidebar tab with previews | Placeholder sidebar item | ❌ |
| Export notes to PDF | Full modal: select, reorder, version pick, jsPDF | Not implemented | ❌ |
| Save with empty = delete | Auto-delete behavior | Not implemented | ❌ |

## 8. BOOKMARKS

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Bookmark button per verse | Inline icon, filled/hollow | Context menu toggle | ⚠️ Discoverable but less convenient |
| Bookmark list | Sidebar tab, sorted newest-first | Full page with search/filter/sort/group | ✅ macOS is better |
| Bookmark labels | Via inline display | Supported with edit | ✅ |
| Bookmark notes | Not in Windows bookmark panel | Supported with BookmarkNoteEditor | ✅ macOS is better |
| Swipe to delete | N/A (web) | Supported | ✅ |
| Group by book | Not implemented | Toggle available | ✅ macOS is better |

## 9. READING HISTORY

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Reading history | Not implemented | Full HistoryView with day grouping, relative timestamps | ✅ macOS only |

## 10. SETTINGS & PREFERENCES

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Profile system | Multiple profiles, create/delete/switch | Not implemented | ❌ |
| Theme picker | 4 themes (Light Cool, Light Warm, Dark Blue, Dark OLED) | 4 themes (System, Light, Dark, Sepia) | ⚠️ Different theme set |
| Language toggle (EN/RU) | 2-button picker | Not implemented | ❌ |
| Font size control | Slider 13-26px | Slider 10-36pt + Cmd+/- shortcuts | ✅ macOS has wider range |
| Font family picker | 3 options (Sans/Serif/Mono) | 7 specific fonts | ✅ macOS is richer |
| Line spacing | Not available | Slider 1.0-2.5× | ✅ macOS only |
| Word spacing | Not available | Slider -2.0 to +8.0 | ✅ macOS only |
| Verse number style | Not configurable | 3 options (superscript/inline/margin) | ✅ macOS only |
| Paragraph mode | Not available | Toggle available | ✅ macOS only |
| Custom text/background colors | Not available | ColorPicker toggles | ✅ macOS only |
| Accent color | Not configurable | 6 color options | ✅ macOS only |
| Verse highlight opacity | Not configurable | Slider available | ✅ macOS only |
| Chapter titles toggle | Not available | Toggle available | ✅ macOS only |

## 11. IMPORT & TRANSLATION MANAGEMENT

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Import local file (.brbmod/.json) | File chooser with validation, metadata form | Drag-drop + file browser | ✅ |
| API Bible import | Full tab with API key, preview, progress log | Not implemented | ❌ |
| Large file warning | AlertTriangle for >5MB | Not implemented | ❌ |
| Validation status cards | Green (valid) / Red (invalid with error list) | Module validation with result display | ⚠️ |
| Translation detail view | Not available | Full metadata grid (language, versification, counts, file size, Strong's, cross-refs, copyright) | ✅ macOS is better |
| Translation reordering | Not available | Drag-and-drop reorder | ✅ macOS only |
| Pane assignment from translation list | Not available | Context menu: assign to new/specific pane | ✅ macOS only |

## 12. UI COMPONENTS & POLISH

| Feature | Windows | macOS | Status |
|---------|---------|-------|--------|
| Tooltips | Portal-based hover tooltips with auto-position | macOS native tooltips (.help modifier) | ✅ |
| Error boundary | React ErrorBoundary with retry | Not implemented | ❌ |
| Cross-reference popover | Portal popover near anchor, 320px, verse preview | Not implemented (uses full-page CrossReferenceView) | ❌ |
| Glass morphism effects | Not available | NSVisualEffectView vibrancy throughout | ✅ macOS only |
| Drag-and-drop import overlay | Not available | Full overlay with visual feedback | ✅ macOS only |
| Toast notifications | Not available | Import success/error toasts | ✅ macOS only |

---

## PRIORITY IMPLEMENTATION LIST (Windows features missing in macOS)

### HIGH PRIORITY (Core reading experience)
1. **Verse highlights** — 5-color system with inline picker (model exists, needs UI)
2. **Notes system** — Per-verse notes with editor modal (model exists, needs full UI)
3. **Inline verse actions** — Bookmark/highlight/note buttons visible per verse row (not buried in context menu)
4. **Word-level Strong's click** — Click individual word → show that word's Strong's (currently verse-level)
5. **Strong's hover tooltip** — Show Strong's number on word hover
6. **Vertical pane splits** — Support split-down in addition to split-right

### MEDIUM PRIORITY (Navigation & search enhancements)
7. **Search context verses** — Show prev/next verse around each result
8. **Search "Sync All Panes" action** — Navigate all panes from search result
9. **Search "Open Parallel" action** — Open result in new pane
10. **Search result count display** — Show total count or "500+" cap
11. **Similar Strong's matches** — Show related entries in Strong's lookup
12. **"Verses Using This Word" list** — Clickable verse refs in Strong's detail
13. **Per-pane sync toggle** — Individual pane sync control vs global toggle
14. **Max 8 panes** — Increase from 4 to 8

### LOWER PRIORITY (Advanced features)
15. **Profile system** — Multiple reading profiles with separate state
16. **Language toggle (EN/RU)** — Localization support
17. **Pop-out pane windows** — Open pane as standalone window
18. **API Bible import** — Remote translation import via api.bible
19. **Notes PDF export** — Select, reorder, multi-version export
20. **Cross-reference popover** — Inline verse preview on ref click (vs full-page navigation)
21. **Error boundary** — Graceful error recovery UI
