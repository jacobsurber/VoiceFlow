# Whisp

macOS menu bar app for voice-to-text transcription. Swift 5.9+, macOS 14+.

## Commands

```bash
# Dev workflow (day-to-day)
swift build
swift run                              # Run without app bundle/signing
swift test
swift test --filter AudioRecorderTests # Run single test suite

# Release workflow
make install          # Build, sign, install to /Applications/
make build            # Universal binary app bundle
make build-notarize   # Signed + notarized (requires env vars below)
make test             # Run tests via scripts/run-tests.sh
make dmg              # Create DMG for distribution
make clean            # Remove .build/, Whisp.app, zips, dmgs
make reset-permissions   # Reset accessibility permissions (fixes Smart Paste after rebuild)
make setup-local-signing # Create persistent signing identity so permissions survive rebuilds
make release            # Create new GitHub release (requires clean working tree)
```

### Notarization Env Vars

```bash
export WHISP_APPLE_ID='your-apple-id@example.com'
export WHISP_APPLE_PASSWORD='app-specific-password'
export WHISP_TEAM_ID='your-team-id'
```

## Architecture

```
Sources/
├── App/              # Entry point (AudioWhisperApp.swift), AppDelegate + extensions,
│                     #   AppDefaults, AppStatus, AppEnvironment, AppSetupHelper,
│                     #   PressAndHoldTriggerState
├── Services/
│   ├── Audio/        # AudioRecorder, AudioProcessor, AudioValidator, SoundManager
│   ├── TranscriptionCoordinator.swift  # Core orchestrator: routes to correct engine
│   ├── SpeechToTextService.swift       # Cloud transcription (OpenAI, Gemini)
│   ├── LocalWhisperService.swift       # WhisperKit (CoreML) transcription
│   ├── ParakeetService.swift           # Parakeet-MLX transcription (via Python daemon)
│   ├── GemmaService.swift              # Gemma model transcription
│   ├── WhisperMLXService.swift         # Whisper via MLX transcription
│   ├── SemanticCorrectionService.swift # Post-processing correction router
│   ├── MLXCorrectionService.swift      # Local MLX-based correction
│   ├── ModelManager.swift              # WhisperKit model downloads
│   ├── MLXModelManager.swift           # MLX model management
│   ├── HuggingFaceCache.swift          # HuggingFace model cache management
│   ├── KeychainService.swift           # API key storage (macOS Keychain)
│   ├── UvBootstrap.swift               # Bootstraps Python uv for ML daemon
│   ├── PythonDetector.swift            # Finds Python installation
│   └── WhisperKitStorage.swift         # WhisperKit model storage paths
├── Managers/
│   ├── Windows/      # DashboardWindowManager, FloatingMicrophoneDockManager
│   ├── PressAndHoldKeyMonitor, FnGlobeMonitor, PasteManager, PermissionManager,
│   └── AccessibilityPermissionManager, MLDaemonManager, AppCategoryManager,
│       MicrophoneVolumeManager
├── Stores/           # DataManager (SwiftData), UsageMetricsStore, CategoryStore,
│                     #   SourceUsageStore — all persistence
├── Models/           # TranscriptionTypes, TranscriptionRecord, TranscriptionError,
│                     #   ModelEntry, CategoryDefinition, SemanticCorrectionTypes
├── Views/
│   ├── Dashboard/    # Main settings UI (DashboardView + provider/recording/prefs views)
│   └── Components/   # RecordingButton, PermissionModals, InkRippleView,
│                     #   FloatingMicrophoneDockView, UnifiedModelRow
├── Utilities/        # Logger, ResourceLocator, VersionInfo, LayoutMetrics, ErrorPresenter,
│                     #   Color+Hex, Arch, LocalizedStrings, NotificationNames
├── Extensions/       # NSImage+Tinting
├── Helpers/          # PermissionChecker
├── ml/               # Python ML daemon package (Parakeet, MLX correction)
└── Resources/        # pyproject.toml, uv.lock, bundled uv binary
```

### Key Patterns

- **AppDelegate extensions**: `AppDelegate.swift` is split into `+Hotkeys`, `+Lifecycle`, `+Menu`, `+Notifications` extensions.
- **TranscriptionCoordinator**: Central orchestrator that routes recording to the active engine and handles correction.
- **Python ML subsystem**: `UvBootstrap.swift` installs `uv`, `MLDaemonManager` manages the Python daemon process, `PythonDetector` locates Python. Parakeet and MLX correction run via this daemon.
- **VersionInfo.swift**: Generated from `VersionInfo.swift.template` at build time. `VERSION` file at repo root tracks the current version (currently 2.1.0).

## Libraries

- **SwiftUI** + **AppKit** — UI and menu bar
- **AVFoundation** — Audio recording
- **Alamofire** — HTTP requests and model downloads
- **WhisperKit** — Local CoreML transcription
- **Combine** / Swift Concurrency — Async logic
- **macOS Keychain** (via `KeychainService.swift`) — API key storage

Prefer existing dependencies over introducing new ones.

## Code Style

- Avoid force unwrapping (`!`); prefer `guard let` and optional chaining.
- Value types (`struct`/`enum`) by default; `class` only for reference semantics.
- `[weak self]` in closures to prevent retain cycles.
- `@MainActor` on UI components; dispatch UI updates on main.
- Functions ≤ 40 lines, single-purpose.
- Follow existing naming conventions and file grouping.

## Testing

- **XCTest** for all new/modified logic. Mocks live in `Tests/Mocks/`.
- `swift test --parallel --enable-code-coverage` must pass.
- Keep tests deterministic; isolate external dependencies with mocks.
- Run a single suite: `swift test --filter <TestClassName>`

## Environment

- **Data directory**: `~/Library/Application Support/Whisp/`
- **Custom correction prompts**: `~/Library/Application Support/Whisp/prompts/*_prompt.txt`
- **VERSION file**: Repo root, read by release scripts.
- **VersionInfo.swift.template**: `Sources/` — build scripts generate `VersionInfo.swift` with git hash.

## Gotchas

- **Accessibility permission invalidated on every rebuild** (ad-hoc signing). After `make install`: System Settings > Accessibility > remove Whisp > re-add `/Applications/Whisp.app` > toggle ON. SmartPaste silently fails without this.
- **"Build succeeded" then "Build failed"**: Swift build works but post-build steps fail. Check if `.build/arm64-apple-macosx/release/Whisp` exists; run `scripts/install-whisp.sh` manually.
- **Safe-to-ignore warnings**: `AddInstanceForFactory: No factory registered...` and `LoudnessManager.mm: unknown value` are Apple framework noise.
- **Entry point is `AudioWhisperApp.swift`**, not `WhispApp.swift` (legacy naming from the AudioWhisper fork).
