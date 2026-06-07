import AppKit
import Observation

// MARK: - Shortcut

struct Shortcut {
    let modifiers: NSEvent.ModifierFlags
    let keyCode: UInt16?

    func matches(flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == nil && flags.intersection(.deviceIndependentFlagsMask) == modifiers
    }

    func matches(keyCode code: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        self.keyCode == code && flags.intersection(.deviceIndependentFlagsMask) == modifiers
    }
}

extension Shortcut: Equatable {
    static func == (lhs: Shortcut, rhs: Shortcut) -> Bool {
        lhs.modifiers == rhs.modifiers && lhs.keyCode == rhs.keyCode
    }
}

extension Shortcut: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(modifiers.rawValue)
        hasher.combine(keyCode)
    }
}

extension Shortcut: Codable {
    private enum CodingKeys: String, CodingKey {
        case modifiersRawValue
        case keyCode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modifiers = NSEvent.ModifierFlags(rawValue: try c.decode(UInt.self, forKey: .modifiersRawValue))
        keyCode = try c.decodeIfPresent(UInt16.self, forKey: .keyCode)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modifiers.rawValue, forKey: .modifiersRawValue)
        try c.encodeIfPresent(keyCode, forKey: .keyCode)
    }
}

extension Shortcut {
    var displayText: String {
        var parts: [String] = []
        if modifiers.contains(.function)  { parts.append("fn") }
        if modifiers.contains(.control)   { parts.append("⌃") }
        if modifiers.contains(.option)    { parts.append("⌥") }
        if modifiers.contains(.shift)     { parts.append("⇧") }
        if modifiers.contains(.command)   { parts.append("⌘") }
        if let keyCode { parts.append(Self.keyCodeLabel(keyCode)) }
        return parts.joined(separator: " ")
    }

    private static func keyCodeLabel(_ code: UInt16) -> String {
        let fKeys: [UInt16: String] = [
            122: "F1", 120: "F2",  99: "F3", 118: "F4",
             96: "F5",  97: "F6",  98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        return fKeys[code] ?? "key\(code)"
    }
}

// MARK: - ShortcutStore

@Observable
final class ShortcutStore {
    private let userDefaultsKey: String
    private(set) var shortcuts: [WorkflowType: [Shortcut]]

    init(userDefaultsKey: String = "blitztext.shortcutStore") {
        self.userDefaultsKey = userDefaultsKey
        self.shortcuts = Self.load(key: userDefaultsKey) ?? Self.makeDefaults()
    }

    func shortcuts(for type: WorkflowType) -> [Shortcut] {
        shortcuts[type] ?? []
    }

    func add(_ shortcut: Shortcut, for type: WorkflowType) {
        var updated = shortcuts
        updated[type] = (updated[type] ?? []) + [shortcut]
        shortcuts = updated
        persist()
    }

    func remove(_ shortcut: Shortcut, from type: WorkflowType) {
        var updated = shortcuts
        updated[type] = (updated[type] ?? []).filter { $0 != shortcut }
        shortcuts = updated
        persist()
    }

    func workflow(matching flags: NSEvent.ModifierFlags) -> WorkflowType? {
        WorkflowType.allCases.first { type in
            shortcuts(for: type).contains { $0.matches(flags: flags) }
        }
    }

    func workflow(matching keyCode: UInt16, flags: NSEvent.ModifierFlags) -> WorkflowType? {
        WorkflowType.allCases.first { type in
            shortcuts(for: type).contains { $0.matches(keyCode: keyCode, flags: flags) }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private static func load(key: String) -> [WorkflowType: [Shortcut]]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([WorkflowType: [Shortcut]].self, from: data)
    }

    private static func makeDefaults() -> [WorkflowType: [Shortcut]] {
        [
            .transcription:      [Shortcut(modifiers: [.function, .shift], keyCode: nil)],
            .localTranscription: [Shortcut(modifiers: [.function, .shift, .control], keyCode: nil)],
            .textImprover:       [Shortcut(modifiers: [.function, .control], keyCode: nil)],
            .dampfAblassen:      [Shortcut(modifiers: [.function, .option], keyCode: nil)],
            .emojiText:          [Shortcut(modifiers: [.function, .command], keyCode: nil)],
        ]
    }
}
