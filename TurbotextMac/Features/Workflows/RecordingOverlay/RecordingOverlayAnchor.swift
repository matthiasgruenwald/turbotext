import AppKit
import ApplicationServices

/// A single, frozen anchor point for the recording overlay, computed once at
/// workflow start. Either the target app's text caret, or the mouse pointer
/// as fallback when caret geometry is unavailable.
struct RecordingOverlayAnchor: Equatable {
    enum Source: Equatable {
        case textCursor
        case mousePointer
    }

    let point: CGPoint
    let source: Source
}

/// Resolves the anchor once per workflow start. Kept free of AppKit/AX calls
/// in its core logic so it can be unit-tested with injected providers, per
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

    /// Queries the system-wide focused UI element for a zero-length selection's
    /// bounds — the technical proxy for the insertion caret documented in the
    /// research note. Any AX error or missing trust falls through to `nil`.
    private static func systemCaretRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
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
