import XCTest

@testable import VoiceFlow

final class FnGlobeMonitorTests: XCTestCase {
    private var defaultsSuiteNames: [String] = []

    override func tearDown() {
        defaultsSuiteNames.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        defaultsSuiteNames.removeAll()
        super.tearDown()
    }

    private func makeDefaults(file: StaticString = #filePath, line: UInt = #line) -> UserDefaults {
        let suiteName = "FnGlobeMonitorTests.\(UUID().uuidString)"
        defaultsSuiteNames.append(suiteName)

        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite", file: file, line: line)
            return .standard
        }

        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testSyncForConfigurationRequiresAcknowledgementBeforeAnythingElse() {
        let defaults = makeDefaults()
        let configuration = PressAndHoldConfiguration(enabled: true, key: .globe, mode: .hold)

        FnGlobeHotkeyPreferenceStore.syncForConfiguration(
            configuration,
            inputMonitoringGranted: true,
            using: defaults
        )

        XCTAssertEqual(FnGlobeHotkeyPreferenceStore.readiness(using: defaults), .requiresAcknowledgement)
    }

    func testSyncForConfigurationRequiresInputMonitoringAfterAcknowledgement() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppDefaults.Keys.pressAndHoldFnWarningAcknowledged)
        let configuration = PressAndHoldConfiguration(enabled: true, key: .globe, mode: .hold)

        FnGlobeHotkeyPreferenceStore.syncForConfiguration(
            configuration,
            inputMonitoringGranted: false,
            using: defaults
        )

        XCTAssertEqual(FnGlobeHotkeyPreferenceStore.readiness(using: defaults), .requiresInputMonitoring)
    }

    func testFunctionKeyHoldActivatesRecordingAndMarksReady() {
        let keyDownExpectation = expectation(description: "keyDown")
        var readinessChanges: [FnGlobeHotkeyReadiness] = []

        let monitor = FnGlobeMonitor(
            keyDownHandler: {
                keyDownExpectation.fulfill()
            },
            readinessHandler: { readiness, _ in
                readinessChanges.append(readiness)
            }
        )

        monitor.processSemanticEvent(.functionKeyChanged(isPressed: true))
        monitor.activateFnIfEligible()

        wait(for: [keyDownExpectation], timeout: 1.0)
        XCTAssertEqual(readinessChanges.last, .ready)
    }

    func testStandaloneFunctionKeyKeyDownDoesNotCancelPendingActivation() {
        let keyDownExpectation = expectation(description: "keyDown")

        let monitor = FnGlobeMonitor(
            keyDownHandler: {
                keyDownExpectation.fulfill()
            },
            readinessHandler: { _, _ in }
        )

        monitor.processSemanticEvent(.functionKeyChanged(isPressed: true))
        monitor.handleKeyDown(keyCode: Int64(PressAndHoldKey.globe.keyCode))
        monitor.activateFnIfEligible()

        wait(for: [keyDownExpectation], timeout: 1.0)
    }

    func testOtherKeyCancelsPendingActivation() {
        let keyDownExpectation = expectation(description: "keyDown")
        keyDownExpectation.isInverted = true

        let monitor = FnGlobeMonitor(
            keyDownHandler: {
                keyDownExpectation.fulfill()
            },
            readinessHandler: { _, _ in }
        )

        monitor.processSemanticEvent(.functionKeyChanged(isPressed: true))
        monitor.processSemanticEvent(.otherKeyPressed)
        monitor.activateFnIfEligible()

        wait(for: [keyDownExpectation], timeout: 0.2)
    }

    func testNonFunctionKeyDownCancelsPendingActivation() {
        let keyDownExpectation = expectation(description: "keyDown")
        keyDownExpectation.isInverted = true

        let monitor = FnGlobeMonitor(
            keyDownHandler: {
                keyDownExpectation.fulfill()
            },
            readinessHandler: { _, _ in }
        )

        monitor.processSemanticEvent(.functionKeyChanged(isPressed: true))
        monitor.handleKeyDown(keyCode: 12)
        monitor.activateFnIfEligible()

        wait(for: [keyDownExpectation], timeout: 0.2)
    }

    func testModifierCombinationCancelsPendingActivationWhenModifierComesAfterFn() {
        let keyDownExpectation = expectation(description: "keyDown")
        keyDownExpectation.isInverted = true

        let monitor = FnGlobeMonitor(
            keyDownHandler: {
                keyDownExpectation.fulfill()
            },
            readinessHandler: { _, _ in }
        )

        monitor.handleFlagsChanged(keyCode: Int64(PressAndHoldKey.globe.keyCode), flags: [.maskSecondaryFn])
        monitor.handleFlagsChanged(keyCode: 56, flags: [.maskSecondaryFn, .maskShift])
        monitor.activateFnIfEligible()

        wait(for: [keyDownExpectation], timeout: 0.2)
    }

    func testModifierCombinationCancelsPendingActivationWhenModifierWasAlreadyHeld() {
        let keyDownExpectation = expectation(description: "keyDown")
        keyDownExpectation.isInverted = true

        let monitor = FnGlobeMonitor(
            keyDownHandler: {
                keyDownExpectation.fulfill()
            },
            readinessHandler: { _, _ in }
        )

        monitor.handleFlagsChanged(
            keyCode: Int64(PressAndHoldKey.globe.keyCode), flags: [.maskSecondaryFn, .maskShift])
        monitor.activateFnIfEligible()

        wait(for: [keyDownExpectation], timeout: 0.2)
    }

    func testFunctionKeyReleaseStopsRecordingAfterActivation() {
        let keyDownExpectation = expectation(description: "keyDown")
        let keyUpExpectation = expectation(description: "keyUp")

        let monitor = FnGlobeMonitor(
            keyDownHandler: {
                keyDownExpectation.fulfill()
            },
            keyUpHandler: {
                keyUpExpectation.fulfill()
            },
            readinessHandler: { _, _ in }
        )

        monitor.processSemanticEvent(.functionKeyChanged(isPressed: true))
        monitor.activateFnIfEligible()
        monitor.processSemanticEvent(.functionKeyChanged(isPressed: false))

        wait(for: [keyDownExpectation, keyUpExpectation], timeout: 1.0)
    }

    func testTapDisabledReportsUnavailable() {
        var readinessChanges: [FnGlobeHotkeyReadiness] = []

        let monitor = FnGlobeMonitor(
            keyDownHandler: {},
            readinessHandler: { readiness, _ in
                readinessChanges.append(readiness)
            }
        )

        monitor.processSemanticEvent(.tapDisabled)

        XCTAssertEqual(readinessChanges.last, .unavailable)
    }

    func testInputMonitoringPermissionFallsBackToEventTapProbe() {
        let permissionManager = InputMonitoringPermissionManager(
            preflight: { false },
            requestAccess: { false },
            eventTapProbe: { true }
        )

        XCTAssertTrue(permissionManager.checkPermission())
    }

    func testInputMonitoringPermissionReportsDeniedWhenBothChecksFail() {
        let permissionManager = InputMonitoringPermissionManager(
            preflight: { false },
            requestAccess: { false },
            eventTapProbe: { false }
        )

        XCTAssertFalse(permissionManager.checkPermission())
    }
}
