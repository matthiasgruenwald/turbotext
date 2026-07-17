import AppKit
import ApplicationServices

/// A single anchor point for the recording overlay: the target app's text caret, the
/// active screen's bottom center, or the mouse pointer as fallback when caret geometry is
/// unavailable. In `.textCursor` mode this moves throughout `.recording`/`.processing` as
/// `RecordingOverlayController` re-resolves it (see `repositionIfNeeded()`); it isn't
/// computed once and frozen.
struct RecordingOverlayAnchor: Equatable {
    enum Source: Equatable {
        case textCursor
        case mousePointer
        case screenBottomCenter
    }

    let point: CGPoint
    let source: Source
}

/// Resolves one anchor value at a time. Kept free of AppKit/AX calls in its core logic so
/// it can be unit-tested with injected providers, per
/// docs/research/2026-07-15-cursornahe-live-wellenform-verankerung.md.
enum RecordingOverlayAnchorResolver {
    /// Returns the caret rect in AppKit screen coordinates, or `nil` when no
    /// usable caret geometry is available (missing permission, unsupported
    /// attribute, zero-length selection with no bounds, etc.).
    typealias CaretRectProvider = () -> CGRect?
    typealias MouseLocationProvider = () -> CGPoint

    static func resolve(
        caretRectProvider: CaretRectProvider,
        mouseLocationProvider: MouseLocationProvider
    ) -> RecordingOverlayAnchor {
        if let rect = caretRectProvider() {
            return RecordingOverlayAnchor(point: CGPoint(x: rect.minX, y: rect.minY), source: .textCursor)
        }
        return RecordingOverlayAnchor(point: mouseLocationProvider(), source: .mousePointer)
    }

    static func resolveWithSystemProviders() -> RecordingOverlayAnchor {
        resolve(caretRectProvider: systemCaretRect, mouseLocationProvider: systemMouseLocation)
    }

    /// Caret rect for one specific app, queried directly by process id rather than via
    /// the system-wide focused element. This keeps the overlay bound to the app captured
    /// as the workflow's target at start: if focus moves to a different app or window,
    /// re-querying by pid still reports that target app's own last-known focused element
    /// instead of silently following the newly focused app. Any AX error, missing trust,
    /// or a target app that no longer exposes a caret falls through to `nil`, same as the
    /// system-wide path.
    static func caretRect(forProcessIdentifier pid: pid_t) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        return caretRect(fromFocusRoot: AXUIElementCreateApplication(pid))
    }

    /// Bottom-center point of the active screen, for `.screenBottomCenter` positioning.
    /// Uses the screen under the mouse pointer rather than `NSScreen.main`: Turbotext is an
    /// LSUIElement app whose signal-pill panel never becomes key, so `NSScreen.main` (which
    /// resolves via this app's own key window) doesn't reliably track the screen the user is
    /// actually working on in a multi-monitor setup. Falls back to the mouse's raw location
    /// if no screen reports containing it (practically only possible with zero screens).
    static func activeScreenBottomCenter(margin: CGFloat = 40) -> CGPoint {
        let mouseLocation = systemMouseLocation()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.screens.first
        else { return mouseLocation }
        return CGPoint(x: screen.frame.midX, y: screen.frame.minY + margin)
    }

    /// Queries the system-wide focused UI element for a zero-length selection's
    /// bounds — the technical proxy for the insertion caret documented in the
    /// research note. Any AX error or missing trust falls through to `nil`.
    private static func systemCaretRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        return caretRect(fromFocusRoot: AXUIElementCreateSystemWide())
    }

    /// Shared caret-rect lookup from any AX focus root (system-wide or one app element):
    /// reads its focused UI element, then that element's zero-length selection bounds.
    private static func caretRect(fromFocusRoot root: AXUIElement) -> CGRect? {
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success, let focusedElement else { return nil }
        // swiftlint:disable:next force_cast
        let element = focusedElement as! AXUIElement

        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        ) == .success, let selectedRange else { return nil }

        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange,
            &boundsValue
        ) == .success, let boundsValue else { return nil }

        // swiftlint:disable:next force_cast
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }

        return convertAXRectToAppKitScreenSpace(rect)
    }

    /// AX bounds use top-left-origin global screen coordinates; AppKit uses
    /// bottom-left-origin per-screen coordinates. AX's global origin is the
    /// top-left of the screen that also anchors AppKit's coordinate space —
    /// that's the screen with `frame.origin == .zero`, not necessarily
    /// `NSScreen.screens.first` (order isn't guaranteed on multi-monitor setups).
    private static func convertAXRectToAppKitScreenSpace(_ axRect: CGRect) -> CGRect? {
        let primaryScreen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        guard let primaryScreenHeight = primaryScreen?.frame.height else { return nil }
        return CGRect(
            x: axRect.origin.x,
            y: primaryScreenHeight - axRect.origin.y - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }

    private static func systemMouseLocation() -> CGPoint {
        NSEvent.mouseLocation
    }
}
