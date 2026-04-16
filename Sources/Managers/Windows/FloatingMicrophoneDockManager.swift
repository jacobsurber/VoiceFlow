import AppKit
import Combine
import SwiftUI

@MainActor
internal final class FloatingMicrophoneDockManager: NSObject {
    static let shared = FloatingMicrophoneDockManager()

    private let viewModel = FloatingMicrophoneDockViewModel()
    private var recorderCancellables = Set<AnyCancellable>()
    private var stateCancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []
    private var userDefaultsObserver: NSObjectProtocol?
    private weak var panel: FloatingMicrophoneDockPanel?
    private weak var passthroughContainer: DockPassthroughView?
    private var primaryAction: (() -> Void)?
    private var cancelAction: (() -> Void)?
    private var openSettingsAction: (() -> Void)?

    private override init() {
        super.init()

        viewModel.$visualStyle
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] style in
                self?.passthroughContainer?.activeContentSize = FloatingMicrophoneDockLayout.size(for: style)
            }
            .store(in: &stateCancellables)
    }

    func prepareForDockActivation() {
        viewModel.prepareForDockActivation()
    }

    func prepareForShortcutActivation(mode: PressAndHoldMode) {
        viewModel.prepareForShortcutActivation(mode: mode)
    }

    func handleRecordingStartFailed() {
        viewModel.handleRecordingStartFailed()
    }

    func resetInteractionState() {
        viewModel.resetInteractionState()
    }

    func configure(
        recorder: AudioRecorder,
        primaryAction: @escaping () -> Void,
        cancelAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) {
        guard !AppEnvironment.isRunningTests else { return }

        self.primaryAction = primaryAction
        self.cancelAction = cancelAction
        self.openSettingsAction = openSettingsAction

        bindRecorder(recorder)
        installNotificationObserversIfNeeded()
        installUserDefaultsObserverIfNeeded()
        updateVisibility()
    }

    func refreshPositionIfNeeded() {
        updatePanelPosition()
    }

    func stop() {
        recorderCancellables.removeAll()

        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()

        if let userDefaultsObserver {
            NotificationCenter.default.removeObserver(userDefaultsObserver)
            self.userDefaultsObserver = nil
        }

        panel?.close()
        panel = nil
        passthroughContainer = nil
    }

    private func bindRecorder(_ recorder: AudioRecorder) {
        recorderCancellables.removeAll()

        recorder.$isRecording
            .combineLatest(recorder.$audioLevel, recorder.$hasPermission)
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording, audioLevel, hasPermission in
                self?.viewModel.applyRecorderState(
                    isRecording: isRecording,
                    audioLevel: audioLevel,
                    hasPermission: hasPermission
                )
            }
            .store(in: &recorderCancellables)
    }

    private func installNotificationObserversIfNeeded() {
        guard notificationObservers.isEmpty else { return }

        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(
                forName: .transcriptionStarted,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.viewModel.handleTranscriptionStarted()
                }
            },
            center.addObserver(
                forName: .transcriptionCompleted,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.viewModel.handleTranscriptionCompleted()
                }
            },
        ]
    }

    private func installUserDefaultsObserverIfNeeded() {
        guard userDefaultsObserver == nil else { return }

        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateVisibility()
            }
        }
    }

    private func updateVisibility() {
        let shouldShow = UserDefaults.standard.bool(forKey: AppDefaults.Keys.floatingMicrophoneDockEnabled)

        guard shouldShow else {
            panel?.orderOut(nil)
            return
        }

        if let panel {
            panel.orderFrontRegardless()
            updatePanelPosition()
            return
        }

        showPanel()
    }

    private func showPanel() {
        let maxSize = LayoutMetrics.FloatingDock.expandedSize

        let dockView = FloatingMicrophoneDockView(
            viewModel: viewModel,
            onPrimaryAction: { [weak self] in
                self?.primaryAction?()
            },
            onCancelAction: { [weak self] in
                self?.cancelAction?()
            },
            onSettingsAction: { [weak self] in
                self?.openSettingsAction?()
            }
        )
        let hostingView = NSHostingView(rootView: dockView)
        hostingView.frame = NSRect(origin: .zero, size: maxSize)
        hostingView.autoresizingMask = [.width, .height]

        let container = DockPassthroughView(frame: NSRect(origin: .zero, size: maxSize))
        container.addSubview(hostingView)
        container.activeContentSize = FloatingMicrophoneDockLayout.size(for: viewModel.visualStyle)
        self.passthroughContainer = container

        let panel = FloatingMicrophoneDockPanel(
            contentRect: NSRect(origin: .zero, size: maxSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = container

        self.panel = panel
        updatePanelPosition()
        panel.orderFrontRegardless()
    }

    private func updatePanelPosition() {
        guard let panel else { return }

        let maxSize = LayoutMetrics.FloatingDock.expandedSize
        guard let screen = currentScreen() else { return }

        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - (maxSize.width / 2),
            y: visibleFrame.minY + LayoutMetrics.FloatingDock.bottomOffset
        )

        panel.setFrame(NSRect(origin: origin, size: maxSize), display: false, animate: false)
    }

    private func currentScreen() -> NSScreen? {
        if let mainScreen = NSScreen.main {
            return mainScreen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let matchingScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return matchingScreen
        }

        return NSScreen.screens.first
    }
}

private final class FloatingMicrophoneDockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DockPassthroughView: NSView {
    var activeContentSize: CGSize = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)

        let hitRect = NSRect(
            x: (bounds.width - activeContentSize.width) / 2,
            y: 0,
            width: activeContentSize.width,
            height: activeContentSize.height
        )

        guard hitRect.contains(localPoint) else { return nil }
        return super.hitTest(point)
    }
}
