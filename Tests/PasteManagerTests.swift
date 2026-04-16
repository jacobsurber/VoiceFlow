import AppKit
import XCTest

@testable import VoiceFlow

@MainActor
final class PasteManagerTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "enableSmartPaste")
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeManager(permissionGranted: Bool) -> PasteManager {
        PasteManager(
            accessibilityManager: AccessibilityPermissionManager(permissionCheck: { permissionGranted })
        )
    }

    // MARK: - Tests

    func testSmartPasteDisabledCopiesTextButSkipsActivation() {
        UserDefaults.standard.set(false, forKey: "enableSmartPaste")

        let mockApp = MockRunningApplication()
        let manager = makeManager(permissionGranted: true)

        manager.smartPaste(into: mockApp, text: "hello world")

        XCTAssertEqual(mockApp.mockActivationCount, 0)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello world")
    }

    func testSmartPasteFailsWhenPermissionDenied() {
        UserDefaults.standard.set(true, forKey: "enableSmartPaste")

        let mockApp = MockRunningApplication()
        let manager = makeManager(permissionGranted: false)

        manager.smartPaste(into: mockApp, text: "needs permission")

        // Text should still be on clipboard as fallback
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "needs permission")
        XCTAssertEqual(mockApp.mockActivationCount, 0)
    }

    func testSmartPasteFailsForNilTargetApplication() {
        UserDefaults.standard.set(true, forKey: "enableSmartPaste")

        let manager = makeManager(permissionGranted: true)

        manager.smartPaste(into: nil, text: "no target app")

        // Text should still be on clipboard as fallback
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "no target app")
    }

    func testSmartPasteAttemptsActivation() {
        UserDefaults.standard.set(true, forKey: "enableSmartPaste")

        let mockApp = MockRunningApplication()
        let manager = makeManager(permissionGranted: true)

        manager.smartPaste(into: mockApp, text: "attempt paste")

        XCTAssertEqual(mockApp.mockActivationCount, 1)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "attempt paste")
    }

    func testPasteToActiveAppReturnsFalseWhenDisabled() {
        UserDefaults.standard.set(false, forKey: "enableSmartPaste")

        let manager = makeManager(permissionGranted: true)
        let result = manager.pasteToActiveApp()

        XCTAssertFalse(result)
    }

    // MARK: - Direct Typing (typeToActiveApp)

    func testTypeToActiveAppReturnsFalseWhenDisabled() {
        UserDefaults.standard.set(false, forKey: "enableSmartPaste")

        let manager = makeManager(permissionGranted: true)
        let result = manager.typeToActiveApp(text: "should not type")

        XCTAssertFalse(result)
    }

    func testTypeToActiveAppReturnsFalseInTestEnvironment() {
        UserDefaults.standard.set(true, forKey: "enableSmartPaste")

        let manager = makeManager(permissionGranted: true)
        // In test environment, CGEvent operations are blocked — should return false
        let result = manager.typeToActiveApp(text: "test env")

        XCTAssertFalse(result)
    }

    func testTypeToActiveAppDoesNotTouchClipboard() {
        UserDefaults.standard.set(true, forKey: "enableSmartPaste")

        // Put known content on clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("original clipboard", forType: .string)

        let manager = makeManager(permissionGranted: true)
        _ = manager.typeToActiveApp(text: "new text")

        // Clipboard must remain untouched
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "original clipboard")
    }
}
