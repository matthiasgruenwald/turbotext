import XCTest
@testable import Turbotext

final class KeychainServiceIsolationTests: XCTestCase {

    override func tearDown() {
        KeychainService.delete(key: .groqAPIKey)
        super.tearDown()
    }

    func testSaveLoadDeleteRoundTripsUnderTestService() throws {
        try KeychainService.save(key: .groqAPIKey, value: "gsk_isolation_test_key")
        XCTAssertEqual(KeychainService.load(key: .groqAPIKey), "gsk_isolation_test_key")
        KeychainService.delete(key: .groqAPIKey)
        XCTAssertNil(KeychainService.load(key: .groqAPIKey))
    }
}
