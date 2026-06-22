# AI Agent Hub

AI Agent Hub is an iOS-first AI assistant MVP based on `AI Agent Hub——跨设备AI智能助手技术设计文档.md`.

## Current Scope

- SwiftPM core package with model configuration, chat orchestration, privacy redaction, SSE parsing, tool authorization, audit logging, and device connection interfaces.
- SwiftUI iOS app source skeleton under `App/AIAgentHub`.
- SwiftData model definitions for app persistence.
- Keychain adapter for API key storage.
- Mock cross-device service for the MVP; real Bonjour pairing and Mac companion execution are deferred to the next phase.

## Requirements

- Swift 6+
- iOS 18+ deployment target for the app
- macOS 15+ for local development
- Full Xcode 16+ is required to open/build the iOS app target. This machine currently reports Command Line Tools only, so SwiftPM validation is the available automated check.

## Validation

Run:

```sh
swift run AIAgentHubCoreValidation
```

This validates:

- Privacy redaction for local paths, emails, phone numbers, and device names
- Low-risk and high-risk tool authorization behavior
- Tool execution audit logging
- OpenAI-compatible and Claude SSE parsing
- Secret store behavior
- In-memory chat repository behavior
- Chat orchestration persistence and streamed response assembly

## Next Phase

- Create a full Xcode app target once Xcode is installed or selected with `xcode-select`.
- Replace demo `StubAIService` in `ChatHomeView` with configured provider service resolution.
- Implement SwiftData-backed repositories for runtime app state.
- Add real Bonjour discovery and Mac companion app.
- Add UI tests in Xcode after the app target is buildable.

