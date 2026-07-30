import XCTest
@testable import Turbotext

final class SimulatedCredentialsStoreTests: XCTestCase {

    func testInactiveWithoutArgumentOrEnvironment() {
        XCTAssertFalse(SimulatedCredentialsStore.isActive(arguments: ["Turbotext"], environment: [:]))
    }

    func testActivatedByLaunchArgument() {
        XCTAssertTrue(
            SimulatedCredentialsStore.isActive(
                arguments: ["Turbotext", SimulatedCredentialsStore.activationArgument],
                environment: [:]
            )
        )
    }

    func testActivatedByEnvironmentVariable() {
        for value in ["1", "true", "YES", " true "] {
            XCTAssertTrue(
                SimulatedCredentialsStore.isActive(
                    arguments: ["Turbotext"],
                    environment: [SimulatedCredentialsStore.activationEnvironmentKey: value]
                ),
                "expected \(value) to activate simulated credentials"
            )
        }
    }

    func testNotActivatedByFalsyEnvironmentValue() {
        for value in ["0", "false", "no", ""] {
            XCTAssertFalse(
                SimulatedCredentialsStore.isActive(
                    arguments: ["Turbotext"],
                    environment: [SimulatedCredentialsStore.activationEnvironmentKey: value]
                ),
                "expected \(value) to leave simulated credentials off"
            )
        }
    }

    func testSeedsEveryKeyWithDefaultsWhenNoOverridesGiven() {
        let seeded = SimulatedCredentialsStore.seedValues(environment: [:])

        XCTAssertEqual(seeded.count, KeychainKey.allCases.count)
        for key in KeychainKey.allCases {
            XCTAssertEqual(seeded[key], SimulatedCredentialsStore.defaultValue(for: key))
        }
    }

    func testDefaultValuesMatchTheRealKeyPatterns() {
        XCTAssertEqual(
            CredentialsSettingsView.validatedKey(
                fromClipboardText: SimulatedCredentialsStore.defaultValue(for: .groqAPIKey),
                pattern: CredentialsSettingsView.groqAPIKeyPattern
            ),
            SimulatedCredentialsStore.defaultValue(for: .groqAPIKey)
        )
        XCTAssertEqual(
            CredentialsSettingsView.validatedKey(
                fromClipboardText: SimulatedCredentialsStore.defaultValue(for: .openAIAPIKey),
                pattern: CredentialsSettingsView.openAIAPIKeyPattern
            ),
            SimulatedCredentialsStore.defaultValue(for: .openAIAPIKey)
        )
    }

    func testEnvironmentOverrideReplacesDefault() {
        let seeded = SimulatedCredentialsStore.seedValues(
            environment: [SimulatedCredentialsStore.environmentKey(for: .groqAPIKey): "gsk_custom_value"]
        )

        XCTAssertEqual(seeded[.groqAPIKey], "gsk_custom_value")
        XCTAssertEqual(seeded[.openAIAPIKey], SimulatedCredentialsStore.defaultValue(for: .openAIAPIKey))
    }

    func testEmptyEnvironmentOverrideLeavesKeyUnconfigured() {
        let seeded = SimulatedCredentialsStore.seedValues(
            environment: [SimulatedCredentialsStore.environmentKey(for: .groqAPIKey): "  "]
        )

        XCTAssertNil(seeded[.groqAPIKey])
        XCTAssertEqual(seeded[.openAIAPIKey], SimulatedCredentialsStore.defaultValue(for: .openAIAPIKey))
    }

    func testStoreRoundTripsWithoutTouchingTheKeychain() {
        let store = SimulatedCredentialsStore(values: [.groqAPIKey: "gsk_seeded"])

        XCTAssertEqual(store.load(.groqAPIKey), "gsk_seeded")
        XCTAssertNil(store.load(.openAIAPIKey))

        store.save("sk-written", for: .openAIAPIKey)
        XCTAssertEqual(store.load(.openAIAPIKey), "sk-written")

        store.save("gsk_overwritten", for: .groqAPIKey)
        XCTAssertEqual(store.load(.groqAPIKey), "gsk_overwritten")

        store.delete(.groqAPIKey)
        XCTAssertNil(store.load(.groqAPIKey))
        XCTAssertEqual(store.load(.openAIAPIKey), "sk-written")
    }
}
