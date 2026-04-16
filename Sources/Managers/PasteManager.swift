import AppKit
import ApplicationServices
import Carbon
import Foundation
import Observation
import os.log

// Cancellation token to prevent race condition in async callbacks
private final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    var isCancelled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isCancelled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isCancelled = newValue
        }
    }
}

// Helper class to safely capture observer in closure
// Uses a lock to ensure thread-safe access to the mutable observer property
// @unchecked is required because we have mutable state but we ensure thread safety via NSLock
private final class ObserverBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _observer: NSObjectProtocol?

    var observer: NSObjectProtocol? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _observer
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _observer = newValue
        }
    }
}

/// Errors that can occur during paste operations
internal enum PasteError: LocalizedError {
    case accessibilityPermissionDenied
    case eventSourceCreationFailed
    case keyboardEventCreationFailed
    case targetAppNotAvailable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return
                "Accessibility permission is required for SmartPaste. Please enable it in System Settings > Privacy & Security > Accessibility."
        case .eventSourceCreationFailed:
            return "Could not create event source for paste operation."
        case .keyboardEventCreationFailed:
            return "Could not create keyboard events for paste operation."
        case .targetAppNotAvailable:
            return "Target application is not available for pasting."
        }
    }
}

@Observable
@MainActor
internal class PasteManager {

    private let accessibilityManager: AccessibilityPermissionManager

    init(accessibilityManager: AccessibilityPermissionManager = AccessibilityPermissionManager()) {
        self.accessibilityManager = accessibilityManager
    }

    /// Types text directly into the focused application via CGEvent keyboard events.
    /// Does NOT touch the clipboard. Returns `true` on success.
    @discardableResult
    func typeToActiveApp(text: String) -> Bool {
        let enableSmartPaste = UserDefaults.standard.bool(forKey: AppDefaults.Keys.enableSmartPaste)

        guard enableSmartPaste else {
            Logger.app.debug("SmartPaste: disabled in settings, skipping type")
            return false
        }

        // CRITICAL: Prevent any CGEvent operations during tests
        if NSClassFromString("XCTestCase") != nil {
            Logger.app.debug("SmartPaste: test environment, skipping type")
            return false
        }

        guard accessibilityManager.checkPermission() else {
            Logger.app.debug("SmartPaste: accessibility permission denied")
            return false
        }

        Logger.app.debug("SmartPaste: typing \(text.count) characters directly via CGEvent")
        do {
            try typeTextViaCGEvent(text)
            Logger.app.debug("SmartPaste: direct type succeeded")
            return true
        } catch {
            Logger.app.error("SmartPaste: direct type failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Attempts to paste text to the currently active application via clipboard + ⌘V.
    /// Returns `true` if paste succeeded, `false` if it failed (accessibility denied, etc.).
    @discardableResult
    func pasteToActiveApp() -> Bool {
        let enableSmartPaste = UserDefaults.standard.bool(forKey: AppDefaults.Keys.enableSmartPaste)

        guard enableSmartPaste else {
            Logger.app.debug("SmartPaste: disabled in settings, skipping paste")
            return false
        }

        Logger.app.debug("SmartPaste: enabled, attempting CGEvent paste")
        let result = performCGEventPaste()
        Logger.app.debug("SmartPaste: CGEvent paste result=\(result)")
        return result
    }

    /// SmartPaste function that attempts to paste text into a specific application
    /// This is the function mentioned in the test requirements
    func smartPaste(into targetApp: NSRunningApplication?, text: String) {
        // First copy text to clipboard as fallback - this ensures users always have access to the text
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let enableSmartPaste = UserDefaults.standard.bool(forKey: AppDefaults.Keys.enableSmartPaste)

        guard enableSmartPaste else {
            // SmartPaste is disabled in settings - fail with appropriate error
            handlePasteResult(.failure(PasteError.targetAppNotAvailable))
            return
        }

        // CRITICAL: Check accessibility permission without prompting - never bypass this check
        // If this fails, we must NOT attempt to proceed with CGEvent operations
        guard accessibilityManager.checkPermission() else {
            // Permission is definitively denied - show proper error and stop processing
            // Do NOT attempt any paste operations without permission
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            return
        }

        // Validate target application
        guard let targetApp = targetApp, !targetApp.isTerminated else {
            handlePasteResult(.failure(PasteError.targetAppNotAvailable))
            return
        }

        // Attempt to activate target application
        let activationSuccess = targetApp.activate(options: [])
        if !activationSuccess {
            // App activation failed - this could indicate the app is not responsive
            handlePasteResult(.failure(PasteError.targetAppNotAvailable))
            return
        }

        // Wait for app to become active before pasting
        waitForApplicationActivation(targetApp) { [weak self] in
            guard let self = self else { return }

            // Double-check permission before performing paste (belt and suspenders approach)
            guard self.accessibilityManager.checkPermission() else {
                // Permission was revoked between initial check and paste attempt
                self.handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
                return
            }

            self.performCGEventPaste()
        }
    }

    /// Performs paste with completion handler for proper coordination
    @MainActor
    func pasteWithCompletionHandler() async {
        await withCheckedContinuation { continuation in
            pasteWithUserInteraction { _ in
                continuation.resume()
            }
        }
    }

    /// Performs paste with immediate user interaction context
    /// This should work better than automatic pasting
    func pasteWithUserInteraction(completion: ((Result<Void, PasteError>) -> Void)? = nil) {
        // Check permission first - if denied, show proper explanation and request
        guard accessibilityManager.checkPermission() else {
            // Show permission request with explanation - this includes user education
            accessibilityManager.requestPermissionWithExplanation { [weak self] granted in
                guard let self = self else { return }

                if granted {
                    // Permission was granted - attempt paste operation
                    self.performCGEventPaste(completion: completion)
                } else {
                    // User declined permission - show appropriate message and fail gracefully
                    self.accessibilityManager.showPermissionDeniedMessage()
                    self.handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
                    completion?(.failure(PasteError.accessibilityPermissionDenied))
                }
            }
            return
        }

        // Permission is available - proceed with paste
        performCGEventPaste(completion: completion)
    }

    // MARK: - CGEvent Paste

    @discardableResult
    private func performCGEventPaste(completion: ((Result<Void, PasteError>) -> Void)? = nil) -> Bool {
        // CRITICAL: Prevent any paste operations during tests
        if NSClassFromString("XCTestCase") != nil {
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            completion?(.failure(PasteError.accessibilityPermissionDenied))
            return false
        }

        // CRITICAL SECURITY CHECK: Always verify accessibility permission before any CGEvent operations
        // This method should NEVER execute without proper permission - no exceptions
        guard accessibilityManager.checkPermission() else {
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            completion?(.failure(PasteError.accessibilityPermissionDenied))
            return false
        }

        // Permission is verified - proceed with paste operation
        do {
            try simulateCmdVPaste()
            handlePasteResult(.success(()))
            completion?(.success(()))
            return true
        } catch let error as PasteError {
            handlePasteResult(.failure(error))
            completion?(.failure(error))
            return false
        } catch {
            handlePasteResult(.failure(PasteError.keyboardEventCreationFailed))
            completion?(.failure(PasteError.keyboardEventCreationFailed))
            return false
        }
    }

    // Removed - using AccessibilityPermissionManager instead

    private func simulateCmdVPaste() throws {
        // CRITICAL: Prevent any paste operations during tests
        if NSClassFromString("XCTestCase") != nil {
            throw PasteError.accessibilityPermissionDenied
        }

        // Final permission check before creating any CGEvents
        // This is our last line of defense against unauthorized paste operations
        guard accessibilityManager.checkPermission() else {
            throw PasteError.accessibilityPermissionDenied
        }

        // Create event source with proper session state
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceCreationFailed
        }

        // Configure event source to suppress local events during paste operation
        // This prevents interference from local keyboard input
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        // Create ⌘V key events for paste operation
        let cmdFlag = CGEventFlags([.maskCommand])
        let vKeyCode = CGKeyCode(kVK_ANSI_V)  // V key code

        // Create both key down and key up events for complete key press simulation
        guard let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            throw PasteError.keyboardEventCreationFailed
        }

        // Apply Command modifier flag to both events
        keyVDown.flags = cmdFlag
        keyVUp.flags = cmdFlag

        // Post the key events to the system
        // This simulates pressing and releasing ⌘V
        keyVDown.post(tap: .cgSessionEventTap)
        keyVUp.post(tap: .cgSessionEventTap)
    }

    /// Types text directly into the focused app using CGEvent keyboard events with Unicode strings.
    /// Does NOT use the clipboard. Each event carries a chunk of UTF-16 characters.
    private func typeTextViaCGEvent(_ text: String) throws {
        guard accessibilityManager.checkPermission() else {
            throw PasteError.accessibilityPermissionDenied
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceCreationFailed
        }

        let utf16 = Array(text.utf16)
        // CGEventKeyboardSetUnicodeString supports up to 20 UTF-16 code units per event
        let chunkSize = 20

        for offset in stride(from: 0, to: utf16.count, by: chunkSize) {
            let end = min(offset + chunkSize, utf16.count)
            var chunk = Array(utf16[offset..<end])

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw PasteError.keyboardEventCreationFailed
            }

            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: 0, unicodeString: &chunk)

            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        }
    }

    private func handlePasteResult(_ result: Result<Void, PasteError>) {
        // Result tracking only — no observers registered
    }

    // MARK: - App Activation Handling

    private func waitForApplicationActivation(
        _ target: NSRunningApplication, completion: @escaping () -> Void
    ) {
        // If already active, execute completion immediately
        if target.isActive {
            completion()
            return
        }

        // Use class-based cancellation token to avoid race condition
        let cancellationToken = CancellationToken()
        let observerBox = ObserverBox()

        // Set up timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak observerBox, weak cancellationToken] in
            guard let token = cancellationToken, !token.isCancelled else { return }
            token.isCancelled = true

            if let observer = observerBox?.observer {
                NotificationCenter.default.removeObserver(observer)
            }
            // Execute completion even on timeout to avoid hanging
            completion()
        }

        // Observe app activation
        observerBox.observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak observerBox, weak cancellationToken] notification in
            if let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                activatedApp.processIdentifier == target.processIdentifier
            {

                guard let token = cancellationToken, !token.isCancelled else { return }
                token.isCancelled = true

                if let observer = observerBox?.observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                completion()
            }
        }
    }

}
