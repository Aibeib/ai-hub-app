# Implementation Notes

## Architecture

The repository is split into a SwiftPM core package and an iOS app source folder.

- `Sources/AIAgentHubCore`: platform-light business logic and provider abstractions.
- `Sources/AIAgentHubCoreValidation`: executable validation target for this environment.
- `App/AIAgentHub`: SwiftUI and SwiftData app source intended for a full Xcode target.

The core package avoids hard dependencies on SwiftUI and SwiftData so it can be tested without a simulator. App-specific persistence lives in the app folder.

## MVP Boundaries

The MVP implements safe local behavior first:

- Third-party model providers are represented through request builders and SSE parsers.
- Apple Foundation Models are hidden unless the OS is iOS 26/macOS 26 or newer.
- Tool calling supports a risk model, authorization gate, and audit log.
- High-risk tools are not implemented as real destructive actions.
- Cross-device control is represented by `DeviceConnectionService` and `MockDeviceConnectionService`.

## Security Defaults

- API keys belong in `KeychainSecretStore`.
- SwiftData model config rows only store non-secret metadata.
- User messages are redacted before provider submission in `ChatOrchestrator`.
- High-risk tool calls require explicit authorization and are audited even when cancelled.

## Environment Limitation

`xcodebuild -version` currently fails because the active developer directory is `/Library/Developer/CommandLineTools`, not full Xcode. Install/select Xcode before simulator builds:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

