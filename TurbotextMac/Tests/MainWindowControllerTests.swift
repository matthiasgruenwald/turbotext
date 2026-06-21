import XCTest
@testable import Turbotext

@MainActor
private final class FakeMainWindow: MainWindowControlling {
    var isVisible = false
    var orderFrontCallCount = 0
    var makeKeyAndOrderFrontCallCount = 0

    func makeKeyAndOrderFront() {
        makeKeyAndOrderFrontCallCount += 1
        isVisible = true
    }

    func orderFront() {
        orderFrontCallCount += 1
        isVisible = true
    }
}

@MainActor
final class MainWindowControllerTests: XCTestCase {

    func testShowOrCreateCreatesWindowWhenNoneExists() {
        var createdWindows: [FakeMainWindow] = []
        let controller = MainWindowController(makeWindow: {
            let window = FakeMainWindow()
            createdWindows.append(window)
            return window
        })

        controller.showOrCreate()

        XCTAssertEqual(createdWindows.count, 1)
        XCTAssertTrue(createdWindows[0].isVisible)
    }

    func testShowOrCreateReusesExistingWindowInsteadOfCreatingSecond() {
        var createdWindows: [FakeMainWindow] = []
        let controller = MainWindowController(makeWindow: {
            let window = FakeMainWindow()
            createdWindows.append(window)
            return window
        })

        controller.showOrCreate()
        controller.showOrCreate()

        XCTAssertEqual(createdWindows.count, 1, "second dock click must not create a second window")
        XCTAssertEqual(createdWindows[0].makeKeyAndOrderFrontCallCount, 2)
    }

    func testIsOpenIsFalseBeforeFirstShow() {
        let controller = MainWindowController(makeWindow: { FakeMainWindow() })
        XCTAssertFalse(controller.isOpen)
    }

    func testIsOpenIsTrueAfterShowOrCreate() {
        let controller = MainWindowController(makeWindow: { FakeMainWindow() })
        controller.showOrCreate()
        XCTAssertTrue(controller.isOpen)
    }

    func testIsOpenIsFalseAfterWindowReportsClosed() {
        var window: FakeMainWindow!
        let controller = MainWindowController(makeWindow: {
            window = FakeMainWindow()
            return window
        })
        controller.showOrCreate()

        controller.windowWillClose()

        XCTAssertFalse(controller.isOpen)
        _ = window
    }

    func testBringToFrontOrdersFrontWithoutCreatingWhenAlreadyOpen() {
        var createdWindows: [FakeMainWindow] = []
        let controller = MainWindowController(makeWindow: {
            let window = FakeMainWindow()
            createdWindows.append(window)
            return window
        })
        controller.showOrCreate()

        controller.bringToFrontIfOpen()

        XCTAssertEqual(createdWindows.count, 1)
        XCTAssertEqual(createdWindows[0].orderFrontCallCount, 1)
    }

    func testBringToFrontDoesNothingWhenNoWindowOpen() {
        var createdWindows: [FakeMainWindow] = []
        let controller = MainWindowController(makeWindow: {
            let window = FakeMainWindow()
            createdWindows.append(window)
            return window
        })

        controller.bringToFrontIfOpen()

        XCTAssertEqual(createdWindows.count, 0)
    }
}
