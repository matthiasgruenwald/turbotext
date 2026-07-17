import AppKit
import ApplicationServices

struct RecordingOverlayAnchor: Equatable {
    enum Source: Equatable {
        case screenBottomCenter
    }

    let point: CGPoint
    let source: Source
}

enum RecordingOverlayAnchorResolver {
    static func targetWindowBottomCenter(forProcessIdentifier pid: pid_t) -> CGPoint? {
        guard AXIsProcessTrusted(), let windowFrame = focusedWindowFrame(forProcessIdentifier: pid) else { return nil }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(windowFrame.origin) }) else { return nil }
        return bottomCenter(of: screen)
    }

    static func primaryScreenBottomCenter() -> CGPoint {
        bottomCenter(of: NSScreen.main ?? NSScreen.screens.first)
    }

    private static func focusedWindowFrame(forProcessIdentifier pid: pid_t) -> CGRect? {
        let application = AXUIElementCreateApplication(pid)
        var focusedWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success, let focusedWindow else { return nil }

        // swiftlint:disable:next force_cast
        return frame(of: focusedWindow as! AXUIElement)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }

        // swiftlint:disable:next force_cast
        var position = CGPoint.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else { return nil }
        // swiftlint:disable:next force_cast
        var size = CGSize.zero
        guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return convertAXRectToAppKitScreenSpace(CGRect(origin: position, size: size))
    }

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

    private static func bottomCenter(of screen: NSScreen?) -> CGPoint {
        guard let screen else { return .zero }
        return CGPoint(x: screen.frame.midX, y: screen.frame.minY + 40)
    }
}
