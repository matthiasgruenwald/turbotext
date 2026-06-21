/// Decides what a menu bar icon click should do, given current presentation state.
/// Pure decision logic, kept separate from `AppDelegate` so "Menüleisten-Klick-Vorrang"
/// (see CONTEXT.md → App-Präsenz) is unit-testable without AppKit.
enum MenuBarClickAction: Equatable {
    case bringMainWindowToFront
    case openPopover
    case closePopover
}

@MainActor
enum MenuBarClickDispatch {
    static func decide(mainWindowIsOpen: Bool, popoverIsShown: Bool) -> MenuBarClickAction {
        if mainWindowIsOpen {
            return .bringMainWindowToFront
        }
        return popoverIsShown ? .closePopover : .openPopover
    }
}
