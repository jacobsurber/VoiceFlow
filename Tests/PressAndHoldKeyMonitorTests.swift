import AppKit
import XCTest

@testable import Whisp

final class PressAndHoldKeyMonitorTests: XCTestCase {
    private var addedEvents: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = []
    private var removedEvents: [Any] = []
    private var defaultsSuiteNames: [String] = []

    override func tearDown() {
        addedEvents.removeAll()
        removedEvents.removeAll()
        defaultsSuiteNames.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        defaultsSuiteNames.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeMonitor(
        configuration: PressAndHoldConfiguration,
        keyDownHandler: @escaping () -> Void = {},
        keyUpHandler: (() -> Void)? = nil
    ) -> PressAndHoldKeyMonitor {
        let addMonitor: PressAndHoldKeyMonitor.EventMonitorFactory = { [weak self] mask, handler in
            self?.addedEvents.append((mask, handler))
            return self?.addedEvents.count ?? 0
        }

        let removeMonitor: PressAndHoldKeyMonitor.EventMonitorRemoval = { [weak self] token in
            self?.removedEvents.append(token)
        }

        return PressAndHoldKeyMonitor(
            configuration: configuration,
            keyDownHandler: keyDownHandler,
            keyUpHandler: keyUpHandler,
            addGlobalMonitor: addMonitor,
            removeMonitor: removeMonitor,
            checkPermission: { true }
        )
    }

    private func makeDefaults(file: StaticString = #filePath, line: UInt = #line) -> UserDefaults {
        let suiteName = "PressAndHoldKeyMonitorTests.\(UUID().uuidString)"
        defaultsSuiteNames.append(suiteName)

        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite", file: file, line: line)
            return .standard
        }

        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - start()

    func testStartRegistersFlagMonitorForModifierKey() {
        let config = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        let monitor = makeMonitor(configuration: config)

        monitor.start()

        XCTAssertEqual(addedEvents.count, 1)
        XCTAssertEqual(addedEvents.first?.0, .flagsChanged)
    }

    func testConfigurationPreservesStoredGlobeSelection() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppDefaults.Keys.pressAndHoldEnabled)
        defaults.set(PressAndHoldKey.globe.rawValue, forKey: AppDefaults.Keys.pressAndHoldKeyIdentifier)
        defaults.set(PressAndHoldMode.hold.rawValue, forKey: AppDefaults.Keys.pressAndHoldMode)

        let configuration = PressAndHoldSettings.configuration(using: defaults)

        XCTAssertEqual(configuration.key, .globe)
    }

    func testConfigurationMapsLegacyFnSelectionToGlobe() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppDefaults.Keys.pressAndHoldEnabled)
        defaults.set("fn", forKey: AppDefaults.Keys.pressAndHoldKeyIdentifier)
        defaults.set(PressAndHoldMode.hold.rawValue, forKey: AppDefaults.Keys.pressAndHoldMode)

        let configuration = PressAndHoldSettings.configuration(using: defaults)

        XCTAssertEqual(configuration.key, .globe)
    }

    func testConfigurationAutoAcknowledgesExistingGlobeSelection() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppDefaults.Keys.pressAndHoldEnabled)
        defaults.set(PressAndHoldKey.globe.rawValue, forKey: AppDefaults.Keys.pressAndHoldKeyIdentifier)

        _ = PressAndHoldSettings.configuration(using: defaults)

        XCTAssertEqual(
            defaults.object(forKey: AppDefaults.Keys.pressAndHoldFnWarningAcknowledged) as? Bool, true)
    }

    func testUpdatePersistsGlobeSelection() {
        let defaults = makeDefaults()
        let configuration = PressAndHoldConfiguration(enabled: true, key: .globe, mode: .toggle)

        PressAndHoldSettings.update(configuration, using: defaults)

        XCTAssertEqual(
            defaults.string(forKey: AppDefaults.Keys.pressAndHoldKeyIdentifier),
            PressAndHoldKey.globe.rawValue
        )
        XCTAssertEqual(
            defaults.string(forKey: AppDefaults.Keys.pressAndHoldMode),
            PressAndHoldMode.toggle.rawValue
        )
    }

    func testStartReturnsFalseForGlobeKey() {
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .globe, mode: .hold)
        )

        XCTAssertFalse(monitor.start())
        XCTAssertTrue(addedEvents.isEmpty)
    }

    // MARK: - Transitions

    func testKeyDownInvokesHandlerOnlyOnceUntilReleased() {
        let expectationDown = expectation(description: "keyDown")
        expectationDown.expectedFulfillmentCount = 2

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {
                expectationDown.fulfill()
            }
        )

        monitor.processTransition(isKeyDownEvent: true)  // first press
        monitor.processTransition(isKeyDownEvent: true)  // repeat press ignored
        monitor.processTransition(isKeyDownEvent: false)  // release
        monitor.processTransition(isKeyDownEvent: true)  // second press

        wait(for: [expectationDown], timeout: 1.0)
    }

    func testKeyUpInvokesHandlerWhenConfigured() {
        let expectationUp = expectation(description: "keyUp")

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: {
                expectationUp.fulfill()
            }
        )

        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)

        wait(for: [expectationUp], timeout: 1.0)
    }

    func testKeyUpHandlerNotCalledWhenNeverPressed() {
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: {
                XCTFail("Key up should not fire without prior key down")
            }
        )

        monitor.processTransition(isKeyDownEvent: false)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    // MARK: - stop()

    func testStopRemovesRegisteredMonitors() {
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        )

        monitor.start()
        monitor.stop()

        XCTAssertEqual(removedEvents.count, 1)
    }
}
