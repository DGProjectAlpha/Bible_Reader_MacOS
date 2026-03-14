import SwiftUI
import AppKit

/// Custom attribute key to store Strong's number on individual words.
extension NSAttributedString.Key {
    static let strongsNumber = NSAttributedString.Key("com.biblereader.strongsNumber")
}

/// NSViewRepresentable wrapping NSTextView to detect text selection in a verse.
/// Reports selection state changes via `onSelectionChange` callback.
struct SelectableVerseText: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let attributedText: NSAttributedString?
    let onSelectionChange: (_ hasSelection: Bool, _ selectionRect: CGRect) -> Void
    var onWordTap: ((_ strongsNumber: String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange, onWordTap: onWordTap)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Build an explicit TextKit 1 stack so character-level hit testing
        // (layoutManager.characterIndex(for:in:…)) works on macOS 14+
        // where NSTextView defaults to TextKit 2 (layoutManager == nil).
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = VerseNSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true          // preserve custom attrs (.strongsNumber)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        context.coordinator.textView = textView

        let scrollView = IntrinsicScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Disable scroll view's own scrolling — parent SwiftUI ScrollView handles it
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none

        updateTextContent(textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? VerseNSTextView else { return }
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onWordTap = onWordTap
        updateTextContent(textView)
    }

    private func updateTextContent(_ textView: NSTextView) {
        if let attributed = attributedText {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: text, attributes: attrs)
            )
        }
        // setAttributedString doesn't trigger didChangeText, so manually invalidate sizes
        textView.invalidateIntrinsicContentSize()
        textView.enclosingScrollView?.invalidateIntrinsicContentSize()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectionChange: (_ hasSelection: Bool, _ selectionRect: CGRect) -> Void
        var onWordTap: ((_ strongsNumber: String) -> Void)?
        weak var textView: NSTextView?

        init(onSelectionChange: @escaping (_ hasSelection: Bool, _ selectionRect: CGRect) -> Void,
             onWordTap: ((_ strongsNumber: String) -> Void)?) {
            self.onSelectionChange = onSelectionChange
            self.onWordTap = onWordTap
            super.init()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let hasSelection = range.length > 0

            var selectionRect: CGRect = .zero
            if hasSelection {
                selectionRect = boundingRect(for: range, in: textView)
            }

            // Defer to avoid "Modifying state during view update" when called
            // from makeNSView → setAttributedString → delegate callback chain.
            let callback = onSelectionChange
            DispatchQueue.main.async {
                callback(hasSelection, selectionRect)
            }
        }

        /// Computes bounding rect for a character range using TextKit1.
        @MainActor
        private func boundingRect(for range: NSRange, in textView: NSTextView) -> CGRect {
            if let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                return textView.convert(rect, to: nil)
            }
            return .zero
        }
    }
}

// MARK: - Custom NSScrollView that forwards intrinsic size from its document view

/// NSScrollView subclass that reports its document view's intrinsic content size
/// so SwiftUI can size the view correctly (otherwise NSScrollView returns zero height).
final class IntrinsicScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        guard let docView = documentView else { return super.intrinsicContentSize }
        let size = docView.intrinsicContentSize
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: size.height > 0 ? size.height : super.intrinsicContentSize.height
        )
    }
}

// MARK: - Custom NSTextView subclass for intrinsic sizing + word tap

/// Custom NSTextView that reports its intrinsic content size so it integrates
/// correctly with SwiftUI layout (no fixed height needed).
/// Also detects single clicks on words with Strong's numbers (vs drag-to-select).
final class VerseNSTextView: NSTextView {
    weak var coordinator: SelectableVerseText.Coordinator?
    /// Maximum distance (pts) between mouseDown and mouseUp to count as a click.
    private let clickThreshold: CGFloat = 3.0

    override var intrinsicContentSize: NSSize {
        // TextKit2 path
        if let textLayoutManager = textLayoutManager {
            textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
            let rect = textLayoutManager.usageBoundsForTextContainer
            return NSSize(width: NSView.noIntrinsicMetric, height: rect.height)
        }
        // TextKit1 fallback
        if let layoutManager = layoutManager, let textContainer = textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            return NSSize(width: NSView.noIntrinsicMetric, height: usedRect.height)
        }
        return super.intrinsicContentSize
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
        enclosingScrollView?.invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
        enclosingScrollView?.invalidateIntrinsicContentSize()
    }

    override func mouseDown(with event: NSEvent) {
        let downLocation = convert(event.locationInWindow, from: nil)
        // super.mouseDown runs an internal tracking loop that consumes the
        // mouseUp event, so our mouseUp override would never fire.  Instead,
        // detect clicks here after super returns (tracking loop complete).
        super.mouseDown(with: event)

        // After the tracking loop, check if it was a simple click (no drag).
        guard selectedRange().length == 0 else { return }
        let upLocation: NSPoint
        if let current = NSApp.currentEvent, current.type == .leftMouseUp {
            upLocation = convert(current.locationInWindow, from: nil)
        } else {
            upLocation = downLocation
        }
        let dx = upLocation.x - downLocation.x
        let dy = upLocation.y - downLocation.y
        let distance = sqrt(dx * dx + dy * dy)
        if distance <= clickThreshold {
            handleWordClick(at: upLocation)
        }
    }

    private func handleWordClick(at point: NSPoint) {
        guard let textStorage = textStorage else { return }

        let charIndex = characterIndex(at: point)
        guard charIndex != NSNotFound, charIndex < textStorage.length else { return }

        // First try: check for explicit Strong's attribute on the word
        let attrs = textStorage.attributes(at: charIndex, effectiveRange: nil)
        if let strongsNumber = attrs[.strongsNumber] as? String, !strongsNumber.isEmpty {
            coordinator?.onWordTap?(strongsNumber)
            return
        }

        // Fallback: extract the clicked word and pass it prefixed with "word:"
        // so the receiver can distinguish it from a Strong's number
        let fullText = textStorage.string as NSString
        let wordRange = fullText.rangeOfWord(at: charIndex)
        if wordRange.location != NSNotFound, wordRange.length > 0 {
            let word = fullText.substring(with: wordRange)
            let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
            if !trimmed.isEmpty {
                coordinator?.onWordTap?("word:\(trimmed)")
            }
        }
    }

    /// Resolves a point to a character index using TextKit1.
    private func characterIndex(at point: NSPoint) -> Int {
        let textContainerOrigin = self.textContainerOrigin
        let adjusted = NSPoint(x: point.x - textContainerOrigin.x,
                               y: point.y - textContainerOrigin.y)

        if let layoutManager = layoutManager, let textContainer = textContainer {
            return layoutManager.characterIndex(
                for: adjusted,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
        }

        return NSNotFound
    }

    // Show pointing hand cursor when hovering over clickable words.
    // If onWordTap is set, ALL words are clickable (Strong's lookup on demand).
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if coordinator?.onWordTap != nil, let textStorage = textStorage {
            let charIndex = characterIndex(at: point)
            if charIndex < textStorage.length, charIndex != NSNotFound {
                // Check if hovering over a word (not whitespace)
                let ch = (textStorage.string as NSString).character(at: charIndex)
                if let scalar = Unicode.Scalar(ch),
                   !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    NSCursor.pointingHand.set()
                    return
                }
            }
        }
        super.mouseMoved(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
}

// MARK: - NSString Word Extraction Helper

private extension NSString {
    /// Returns the range of the word surrounding the given character index.
    func rangeOfWord(at index: Int) -> NSRange {
        guard index < length else { return NSRange(location: NSNotFound, length: 0) }

        let letters = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "''-"))
        var start = index
        var end = index

        // Walk backwards to find word start
        while start > 0 {
            let ch = character(at: start - 1)
            guard let scalar = Unicode.Scalar(ch), letters.contains(scalar) else { break }
            start -= 1
        }

        // Walk forwards to find word end
        while end < length {
            let ch = character(at: end)
            guard let scalar = Unicode.Scalar(ch), letters.contains(scalar) else { break }
            end += 1
        }

        guard end > start else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: start, length: end - start)
    }
}
