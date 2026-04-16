- [x] Confirm the current Apple toolchain and reproduce the macro-plugin failure mode.
- [x] Add a preflight check for missing Apple macro plugins in the shared build helper.
- [x] Verify `make install` fails early with an actionable Xcode requirement message.
- [x] Record the lesson if the new failure mode check proves useful.

## Hotkey investigation

- [x] Normalize unsupported Globe/Fn press-and-hold selections to a working key.
- [x] Update the recording settings UI so Globe/Fn is not offered as a supported global trigger.
- [x] Add regression coverage for press-and-hold settings normalization.
- [x] Run focused hotkey tests.

## Fn / Globe support

- [x] Restore Fn / Globe as a selectable press-and-hold trigger.
- [x] Add a dedicated Fn / Globe monitor backed by a lower-level event tap.
- [x] Add explicit Fn setup guidance and Input Monitoring actions in settings.
- [x] Preserve legacy Globe/Fn selections instead of normalizing them away.
- [x] Add regression coverage for Fn activation, combination cancellation, and migration.
- [x] Run the full VoiceFlow test suite.

## Fn / Globe simplification

- [x] Review the new standalone Fn / Globe path for duplicated state and branching.
- [x] Simplify the target manager, app, helper, and dashboard files without changing behavior.
- [x] Keep scope off unrelated model-cache changes already present in the worktree.
- [x] Run focused Fn / Globe tests and record the simplification result.

Result: centralized Fn / Globe readiness/config helpers, reduced duplicate monitor setup paths, and kept model-cache changes untouched while focused hotkey tests stayed green.

## Local Whisper persistence

- [x] Trace the `Installed` -> `Get` regression to the WhisperKit storage probe used by refresh and recorder readiness.
- [x] Align WhisperKit downloads and storage checks to the real Hugging Face base directory, while preserving a legacy fallback path.
- [x] Verify the download on disk before reporting the model as installed.
- [x] Add regression coverage for WhisperKit storage resolution and bundle completeness.

## Local Whisper download retry

- [x] Inspect the real Hugging Face tree created by WhisperKit during a local model install.
- [x] Fix the WhisperKit download base so new installs land under `~/Documents/huggingface/models/...` instead of `.../models/models/...`.
- [x] Keep compatibility with installs already created in the accidental double-`models` path.
- [x] Run focused Whisper storage/model-manager tests and the full suite.

Result: the `Get` action now points WhisperKit at the correct Hub base, completed installs are detected immediately, and previously downloaded models in the accidental `models/models` tree still resolve for refresh and delete.

## Fn / Globe reliability hardening

- [x] Research public Wispr Flow behavior and compare it against VoiceFlow's current Fn / Globe architecture.
- [x] Audit the dedicated Fn / Globe monitor from first principles for standalone key classification and tap recovery.
- [x] Fix the press-and-hold startup race so releasing the key during async recorder startup cancels cleanly.
- [x] Add regression coverage for standalone Fn keyDown handling and the new trigger state machine.
- [x] Re-run focused hotkey suites and the full VoiceFlow test suite.

Result: VoiceFlow now keeps the dedicated global Fn / Globe event-tap path, ignores standalone Fn keyDown echoes instead of treating them as combinations, recovers the tap after interruptions, and no longer loses a key release while audio recording startup is still in flight.

## Floating microphone dock

- [x] Add a floating, non-activating dock that stays visible across apps and Spaces.
- [x] Reuse real recorder and transcription state so the dock reflects listening, processing, success, and permission states.
- [x] Add a General preference to show or hide the dock.
- [x] Add focused regression coverage for the dock state model.
- [x] Verify with `swift build`, focused dock/hotkey tests, the full suite, and `make build`.

Result: VoiceFlow now launches an always-available floating microphone dock by default, keeps it synchronized with live recorder/transcription state, lets users disable it from General settings, and builds cleanly in both debug and packaged app flows.

## Permission and first-use UX cleanup

- [x] Remove automatic microphone, Accessibility, and Input Monitoring prompts from app launch.
- [x] Request microphone access only when the user actually starts dictation, and continue straight into recording if they grant it.
- [x] Keep Smart Paste and hotkey permissions explicit and clearly labeled as optional in Settings and the floating dock copy.
- [x] Add regression coverage for microphone-on-first-use and the updated press-and-hold start path.
- [x] Verify with focused recorder/hotkey tests, the full suite, and `make build`.

Result: VoiceFlow no longer greets users with a chain of system permission dialogs on startup. Basic dictation now works from the floating dock with microphone permission only, while Smart Paste and background hotkeys remain opt-in advanced features with clearer guidance.

## Gemma fast local ASR planning

- [x] Research current Gemma audio-capable local models and compare them against VoiceFlow's existing WhisperKit and Parakeet stack.
- [x] Write a reviewed implementation plan in `tasks/gemma-fast-local-asr-plan.md`.
- [x] Write a benchmark artifact for go/no-go evaluation under `~/.gstack/projects/amirsalaar-VoiceFlow/`.

Result: recommend `mlx-community/gemma-3n-E2B-it-4bit` as the first Gemma transcription target, but only behind a benchmark-first gate and with hybrid fast-ASR-plus-Gemma routing evaluated before any default or prominent UI rollout.

## Gemma Phase 0 benchmark harness

- [x] Add a repo-native benchmark harness in the test module so it can call internal WhisperKit and Parakeet services without a package refactor.
- [x] Add a checked-in fixture manifest template plus ignored local fixture and result directories under `Benchmarks/`.
- [x] Add repeatable wrapper scripts under `tasks/test-commands/` for smoke fixture preparation and benchmark execution.
- [x] Validate the focused harness tests and an end-to-end smoke run that writes JSON and Markdown output.

Result: Phase 0 benchmark runs are now reproducible via `tasks/test-commands/run-gemma-phase0-benchmark.sh`, with machine-readable output, a readable Markdown summary, and explicit `unimplemented` records for Gemma and hybrid strategies until their runtime paths land.

## Floating dock visual redesign

- [x] Replace the original cream card dock with a darker capsule-style HUD closer to the Wispr reference.
- [x] Center the dock horizontally above the macOS Dock instead of pinning it to the right edge.
- [x] Add a compact recording state with explicit cancel and stop controls.
- [x] Verify with `swift build`, focused dock tests, and the full VoiceFlow test suite.

Result: the floating dock now opens as a centered bottom HUD, uses a darker capsule treatment in the idle state, and collapses into a compact recording control with separate cancel and stop actions while the full suite stays green.

## Floating dock interaction states

- [x] Collapse the idle dock to a minimal handle until the user hovers it.
- [x] Expand the idle dock on hover to show the dictation prompt and settings dots.
- [x] Show a bars-only animated capture pill for hold-shortcut recording.
- [x] Show the full cancel-plus-stop recording controls for interactive or toggle recording.
- [x] Verify with `swift build`, focused dock tests, and the full VoiceFlow test suite.

Result: the dock now matches the requested four-state behavior more closely, with a hover-reveal idle prompt, a distinct shortcut-only capture HUD, and a separate full-control recording pill for persistent recording flows.

## Stable local signing for privacy permissions

- [x] Trace the repeated microphone prompt and broken global Fn trigger to macOS privacy permission persistence rather than the recorder or dock logic.
- [x] Add a reusable signing helper plus a local identity bootstrap script for development builds.
- [x] Update build, install, and permission reset flows to distinguish stable signing from ad-hoc fallback.
- [x] Create a stable local VoiceFlow signing identity, reinstall the app, and reset VoiceFlow privacy permissions once.

Result: VoiceFlow is now installed with a stable local signature, so Microphone, Accessibility, and Input Monitoring permissions can persist across rebuilds instead of being reset by ad-hoc installs. The remaining user action is a one-time re-grant of the relevant permissions after the reset.

## Floating dock hover crash

- [x] Inspect the new macOS crash reports triggered by hovering the floating dock.
- [x] Trace the failure to SwiftUI auto-updating the hosting window's size constraints while the dock manager also resized the `NSPanel` manually.
- [x] Replace the floating dock's `NSHostingController` embedding with a plain `NSHostingView` so the dock manager owns panel sizing end to end.
- [x] Verify with `swift build` and a scripted hover against the debug app while the process stays alive.

Result: hovering the floating dock no longer exits VoiceFlow. The dock manager now owns panel sizing exclusively, and the panel no longer goes through SwiftUI's controller-managed window-size path that was triggering the AppKit constraints exception.
