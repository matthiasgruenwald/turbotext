import XCTest
import AppKit
@testable import Blitztext

// MARK: - Shortcut Matching

final class ShortcutMatchingTests: XCTestCase {

    func testModifierOnlyMatchesExactFlags() {
        let s = Shortcut(modifiers: [.function, .shift], keyCode: nil)
        XCTAssertTrue(s.matches(flags: [.function, .shift]))
    }

    func testModifierOnlyRejectsSubset() {
        let s = Shortcut(modifiers: [.function, .shift], keyCode: nil)
        XCTAssertFalse(s.matches(flags: [.function]))
    }

    func testModifierOnlyRejectsSuperset() {
        let s = Shortcut(modifiers: [.function, .shift], keyCode: nil)
        XCTAssertFalse(s.matches(flags: [.function, .shift, .control]))
    }

    func testKeyCodeMatchesCorrectCombo() {
        let s = Shortcut(modifiers: [], keyCode: 122)
        XCTAssertTrue(s.matches(keyCode: 122, flags: []))
    }

    func testKeyCodeRejectsWrongKeyCode() {
        let s = Shortcut(modifiers: [], keyCode: 122)
        XCTAssertFalse(s.matches(keyCode: 120, flags: []))
    }

    func testKeyCodeWithModifierMatchesFullCombo() {
        let s = Shortcut(modifiers: [.command], keyCode: 122)
        XCTAssertTrue(s.matches(keyCode: 122, flags: [.command]))
        XCTAssertFalse(s.matches(keyCode: 122, flags: []))
        XCTAssertFalse(s.matches(keyCode: 122, flags: [.shift]))
    }

    func testModifierOnlyDoesNotMatchKeyCode() {
        let s = Shortcut(modifiers: [.function, .shift], keyCode: nil)
        XCTAssertFalse(s.matches(keyCode: 122, flags: [.function, .shift]))
    }

    func testCodableRoundTripWithKeyCode() throws {
        let original = Shortcut(modifiers: [.function, .shift], keyCode: 122)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodableRoundTripWithoutKeyCode() throws {
        let original = Shortcut(modifiers: [.function, .option], keyCode: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}

// MARK: - ShortcutStore

final class ShortcutStoreTests: XCTestCase {

    private func makeStore() -> ShortcutStore {
        ShortcutStore(userDefaultsKey: "test_\(UUID().uuidString)")
    }

    func testDefaultsPopulateAllWorkflows() {
        let store = makeStore()
        for type in WorkflowType.allCases {
            XCTAssertFalse(store.shortcuts(for: type).isEmpty, "\(type.rawValue) has no defaults")
        }
    }

    func testDefaultTranscriptionIsFnShift() {
        let store = makeStore()
        let expected = Shortcut(modifiers: [.function, .shift], keyCode: nil)
        XCTAssertTrue(store.shortcuts(for: .transcription).contains(expected))
    }

    func testDefaultLocalTranscriptionIsFnShiftControl() {
        let store = makeStore()
        let expected = Shortcut(modifiers: [.function, .shift, .control], keyCode: nil)
        XCTAssertTrue(store.shortcuts(for: .localTranscription).contains(expected))
    }

    func testAddAppends() {
        let store = makeStore()
        let before = store.shortcuts(for: .transcription).count
        let newShortcut = Shortcut(modifiers: [.control, .shift], keyCode: nil)
        store.add(newShortcut, for: .transcription)
        let after = store.shortcuts(for: .transcription)
        XCTAssertEqual(after.count, before + 1)
        XCTAssertTrue(after.contains(newShortcut))
    }

    func testRemoveDropsShortcut() {
        let store = makeStore()
        guard let toRemove = store.shortcuts(for: .transcription).first else {
            return XCTFail("No defaults for transcription")
        }
        store.remove(toRemove, from: .transcription)
        XCTAssertFalse(store.shortcuts(for: .transcription).contains(toRemove))
    }

    func testRemoveUnknownIsNoop() {
        let store = makeStore()
        let count = store.shortcuts(for: .transcription).count
        let missing = Shortcut(modifiers: [.capsLock], keyCode: nil)
        store.remove(missing, from: .transcription)
        XCTAssertEqual(store.shortcuts(for: .transcription).count, count)
    }

    func testWorkflowLookupByFlagsFindsTranscription() {
        let store = makeStore()
        XCTAssertEqual(store.workflow(matching: [.function, .shift]), .transcription)
    }

    func testWorkflowLookupByFlagsFindsLocalTranscription() {
        let store = makeStore()
        XCTAssertEqual(store.workflow(matching: [.function, .shift, .control]), .localTranscription)
    }

    func testWorkflowLookupReturnsNilForUnknownFlags() {
        let store = makeStore()
        XCTAssertNil(store.workflow(matching: [.capsLock]))
    }

    func testWorkflowLookupByKeyCode() {
        let store = makeStore()
        let fiveShortcut = Shortcut(modifiers: [], keyCode: 96)
        store.add(fiveShortcut, for: .transcription)
        XCTAssertEqual(store.workflow(matching: 96, flags: []), .transcription)
    }

    func testWorkflowLookupByKeyCodeReturnsNilForUnknown() {
        let store = makeStore()
        XCTAssertNil(store.workflow(matching: 99, flags: []))
    }
}
