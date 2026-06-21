import AppKit

/// Abstraction over the AppKit window so `MainWindowController`'s lifecycle/reuse
/// logic can be unit-tested without a real `NSWindow`.
@MainActor
protocol MainWindowControlling: AnyObject {
    func makeKeyAndOrderFront()
    func orderFront()
}

extension NSWindow: MainWindowControlling {
    func makeKeyAndOrderFront() {
        makeKeyAndOrderFront(nil)
    }

    func orderFront() {
        orderFront(nil)
    }
}

/// Owns the lifecycle of the non-transient "Hauptfenster" shown in Dock-Modus.
/// Reuses the existing window instead of creating a second one when already open.
@MainActor
final class MainWindowController {
    private let makeWindow: () -> MainWindowControlling
    private var window: MainWindowControlling?

    init(makeWindow: @escaping () -> MainWindowControlling) {
        self.makeWindow = makeWindow
    }

    var isOpen: Bool {
        window != nil
    }

    func showOrCreate() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront()
    }

    func bringToFrontIfOpen() {
        window?.orderFront()
    }

    func windowWillClose() {
        window = nil
    }
}
