# Chat Deletion and Polished iOS UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app feel like a polished iOS product and make conversation deletion reliable, including deleting the final conversation and returning to the empty chat home.

**Architecture:** Replace fragile SwiftUI `List` swipe deletion with a custom reusable swipe row that owns its drag state and delete button geometry. Then refresh the visual system around an iOS-native premium productivity direction: warmer surfaces, stronger hierarchy, consistent tab icons, polished cards/list rows, and calmer chat/input components.

**Tech Stack:** SwiftUI, SwiftData-backed repositories via `AppRuntime`, existing `DS` design tokens/components, `AIAgentHubCoreValidation`, Xcode 16.4 iOS simulator builds.

## Global Constraints

- Preserve Swift 6 strict-concurrency compatibility.
- Do not add third-party UI dependencies.
- Keep existing app language support (`AppLanguage.zh` / `.en`).
- Keep file sizes under the project rule target; prefer small focused helpers when adding reusable UI.
- Conversation deletion must work from the compact sheet, long-press context menu, and regular layout.
- Deleting the last visible conversation must set `selectedSessionId = nil` and dismiss the compact session sheet.
- Visual direction: iOS-native premium productivity app, not prototype/test UI.
- Verification required after each task: `swift run AIAgentHubCoreValidation` and `DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer xcodebuild -project AI-Agent-Hub.xcodeproj -scheme AIAgentHub -destination 'generic/platform=iOS Simulator' -configuration Debug build`.

---

## File Structure

- Modify `App/AIAgentHub/DesignSystem/DesignTokens.swift`
  - Refine palette and add reusable semantic colors for tab/surfaces/list destructive actions.
- Modify `App/AIAgentHub/DesignSystem/DSComponents.swift`
  - Add/reuse polished card/list primitives if needed.
- Modify `App/AIAgentHub/UI/ChatHomeView.swift`
  - Replace fragile session-list delete implementation with a custom swipe row.
  - Update compact top bar, session sheet, transcript bubble and input polish.
- Modify `App/AIAgentHub/UI/RootView.swift`
  - Improve compact tab presentation and regular sidebar polish.
- Modify `App/AIAgentHub/UI/ModelConfigListView.swift`
  - Convert model page from prototype card grid feel to app-like settings sections.
- Modify `App/AIAgentHub/UI/DeviceManagementView.swift`
  - Polish device page surfaces/actions.
- Modify `App/AIAgentHub/UI/PrivacyAndLogsView.swift`
  - Polish privacy settings list and destructive actions.
- Modify `Sources/AIAgentHubCoreValidation/main.swift`
  - Add repository/session-deletion behavioral validation where feasible.
- Create `App/AIAgentHub/UI/SwipeToDeleteRow.swift`
  - Generic reusable custom swipe-to-delete container for session rows.

---

### Task 1: Reliable custom swipe-to-delete row

**Files:**
- Create: `App/AIAgentHub/UI/SwipeToDeleteRow.swift`
- Modify: `AI-Agent-Hub.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `SwipeToDeleteRow<Content: View>: View`
  - `init(actionTitle: String, actionSystemImage: String = "trash", actionTint: Color = DS.Palette.danger, onDelete: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content)`
  - Supports left swipe revealing a full-height red delete action.
  - Supports full-swipe threshold to delete.
  - Supports tap outside / drag back to close.

- [ ] **Step 1: Create the reusable swipe row file**

Create `App/AIAgentHub/UI/SwipeToDeleteRow.swift` with:

```swift
import SwiftUI

/// A predictable WeChat / iOS Messages-style swipe-to-delete row.
///
/// SwiftUI `List.onDelete` and `.swipeActions` have been unreliable in this app's
/// custom sheet + row setup. This row owns the drag state directly, so the delete
/// button geometry and action dispatch are deterministic.
struct SwipeToDeleteRow<Content: View>: View {
    let actionTitle: String
    var actionSystemImage: String = "trash"
    var actionTint: Color = DS.Palette.danger
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var horizontalOffset: CGFloat = 0
    @State private var isOpen = false

    private let actionWidth: CGFloat = 92
    private let fullSwipeThreshold: CGFloat = 140

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                close()
                onDelete()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 14, weight: .semibold))
                    Text(actionTitle)
                        .font(DS.Typography.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(actionTint)
            }
            .buttonStyle(.plain)

            content()
                .background(DS.Palette.surfaceRaised)
                .offset(x: horizontalOffset)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .onChanged { value in
                            let proposed = (isOpen ? -actionWidth : 0) + value.translation.width
                            horizontalOffset = min(0, max(-actionWidth * 1.35, proposed))
                        }
                        .onEnded { value in
                            let projected = horizontalOffset + value.predictedEndTranslation.width * 0.18
                            if projected < -fullSwipeThreshold {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    horizontalOffset = -UIScreen.main.bounds.width
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                                    onDelete()
                                }
                            } else if projected < -actionWidth * 0.45 {
                                open()
                            } else {
                                close()
                            }
                        }
                )
                .onTapGesture {
                    if isOpen {
                        close()
                    }
                }
        }
        .clipped()
    }

    private func open() {
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
            horizontalOffset = -actionWidth
            isOpen = true
        }
    }

    private func close() {
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
            horizontalOffset = 0
            isOpen = false
        }
    }
}
```

- [ ] **Step 2: Register the file in Xcode project**

Patch `AI-Agent-Hub.xcodeproj/project.pbxproj` exactly like existing UI files:

```bash
python3 <<'PY'
from pathlib import Path
path = Path('AI-Agent-Hub.xcodeproj/project.pbxproj')
s = path.read_text()

build_after = '\t\tA10000000000000000000020 /* Tooling/DeviceCapabilityTools.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000018 /* Tooling/DeviceCapabilityTools.swift */; };\n'
build_new = build_after + '\t\tA10000000000000000000021 /* UI/SwipeToDeleteRow.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000019 /* UI/SwipeToDeleteRow.swift */; };\n'
assert build_after in s
s = s.replace(build_after, build_new)

file_after = '\t\tA20000000000000000000018 /* Tooling/DeviceCapabilityTools.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tooling/DeviceCapabilityTools.swift; sourceTree = "<group>"; };\n'
file_new = file_after + '\t\tA20000000000000000000019 /* UI/SwipeToDeleteRow.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UI/SwipeToDeleteRow.swift; sourceTree = "<group>"; };\n'
assert file_after in s
s = s.replace(file_after, file_new)

group_after = '\t\t\t\tA20000000000000000000018 /* Tooling/DeviceCapabilityTools.swift */,\n'
group_new = group_after + '\t\t\t\tA20000000000000000000019 /* UI/SwipeToDeleteRow.swift */,\n'
assert group_after in s
s = s.replace(group_after, group_new)

sources_after = '\t\t\t\tA10000000000000000000020 /* Tooling/DeviceCapabilityTools.swift in Sources */,\n'
sources_new = sources_after + '\t\t\t\tA10000000000000000000021 /* UI/SwipeToDeleteRow.swift in Sources */,\n'
assert sources_after in s
s = s.replace(sources_after, sources_new)

path.write_text(s)
PY
```

- [ ] **Step 3: Build to verify file registration**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer xcodebuild -project AI-Agent-Hub.xcodeproj -scheme AIAgentHub -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`.

---

### Task 2: Replace session-list deletion with custom row and final-delete routing

**Files:**
- Modify: `App/AIAgentHub/UI/ChatHomeView.swift`
- Test: `Sources/AIAgentHubCoreValidation/main.swift`

**Interfaces:**
- Consumes: `SwipeToDeleteRow` from Task 1.
- Produces: reliable deletion behavior in `ChatHomeView.deleteSession(_:)`.

- [ ] **Step 1: Add repository-level validation for last-session deletion semantics**

In `Sources/AIAgentHubCoreValidation/main.swift`, update `validateSessionMutationOperations()` by appending:

```swift
        // Deleting every visible session should leave the non-deleted session list empty.
        repo.softDeleteSession(chat1.id)
        let remainingVisible = repo.sessions(includeDeleted: false)
        try require(remainingVisible.isEmpty, "all soft-deleted sessions should be hidden from visible list")
        let deletedArchive = repo.sessions(includeDeleted: true)
        try require(deletedArchive.count == 2, "includeDeleted should still expose soft-deleted sessions for retention")
```

- [ ] **Step 2: Run validation to verify current behavior**

Run:

```bash
swift run AIAgentHubCoreValidation
```

Expected: PASS. This confirms the repository layer hides deleted sessions; UI is the broken layer.

- [ ] **Step 3: Replace the session-list `ForEach.onDelete` section with `SwipeToDeleteRow`**

In `App/AIAgentHub/UI/ChatHomeView.swift`, inside `sessionListPane(forSheet:)`, replace the inner `ForEach(group.sessions)` block with:

```swift
                            ForEach(group.sessions) { session in
                                SwipeToDeleteRow(
                                    actionTitle: language[.actionDelete],
                                    onDelete: { deleteSession(session.id) }
                                ) {
                                    SessionRow(
                                        session: session,
                                        isSelected: session.id == selectedSessionId,
                                        preview: previews[session.id] ?? language[.chatStartHint],
                                        language: language,
                                        onSelect: {
                                            withAnimation(DS.Motion.springSnappy) {
                                                selectedSessionId = session.id
                                                if forSheet {
                                                    isShowingSessionList = false
                                                }
                                            }
                                        },
                                        onPin: { runtime.togglePin(session.id) },
                                        onDelete: { deleteSession(session.id) }
                                    )
                                    .equatable()
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
```

Remove the `.onDelete` modifier from that `ForEach`.

- [ ] **Step 4: Make final deletion return home**

Ensure `deleteSession(_:)` in `ChatHomeView.swift` is exactly:

```swift
    private func deleteSession(_ id: UUID) {
        runtime.deleteSession(id)

        let remaining = runtime.sessions.filter { !$0.isArchived }
        if remaining.isEmpty {
            selectedSessionId = nil
            isShowingSessionList = false
            return
        }

        if selectedSessionId == id {
            selectedSessionId = remaining.first?.id
        }
    }
```

- [ ] **Step 5: Verify**

Run:

```bash
swift run AIAgentHubCoreValidation
DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer xcodebuild -project AI-Agent-Hub.xcodeproj -scheme AIAgentHub -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

Expected:
- Validation: `AIAgentHubCoreValidation: all checks passed`
- Xcode: `** BUILD SUCCEEDED **`

---

### Task 3: Refresh design tokens for a real app feel

**Files:**
- Modify: `App/AIAgentHub/DesignSystem/DesignTokens.swift`

**Interfaces:**
- Produces updated semantic palette used by all screens.

- [ ] **Step 1: Update palette values**

In `DesignTokens.swift`, update `DS.Palette` values while preserving property names. Use a warmer iOS productivity palette:

```swift
static let surface = Color(red: 0.975, green: 0.972, blue: 0.985)
static let surfaceRaised = Color(red: 0.955, green: 0.950, blue: 0.970)
static let surfaceElevated = Color(red: 1.000, green: 0.998, blue: 1.000)
static let textPrimary = Color(red: 0.070, green: 0.065, blue: 0.095)
static let textSecondary = Color(red: 0.360, green: 0.345, blue: 0.430)
static let textTertiary = Color(red: 0.575, green: 0.555, blue: 0.650)
static let accent = Color(red: 0.470, green: 0.285, blue: 0.930)
static let accentSoft = Color(red: 0.905, green: 0.875, blue: 1.000)
static let border = Color(red: 0.850, green: 0.835, blue: 0.900)
static let separator = Color(red: 0.885, green: 0.875, blue: 0.925)
static let danger = Color(red: 0.950, green: 0.230, blue: 0.260)
static let warning = Color(red: 0.865, green: 0.540, blue: 0.125)
static let positive = Color(red: 0.145, green: 0.635, blue: 0.390)
static let userBubble = Color(red: 0.500, green: 0.330, blue: 0.960)
static let userBubbleText = Color.white
static let assistantBubble = Color(red: 1.000, green: 0.998, blue: 1.000)
```

If names differ in the actual file, map these values to the existing equivalent properties instead of adding duplicate properties.

- [ ] **Step 2: Add semantic helpers if absent**

If `DS.Palette` does not already include these, add:

```swift
static let tabBarBackground = Color(red: 1.000, green: 0.998, blue: 1.000).opacity(0.96)
static let listRowHighlight = Color(red: 0.930, green: 0.905, blue: 1.000)
```

- [ ] **Step 3: Build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer xcodebuild -project AI-Agent-Hub.xcodeproj -scheme AIAgentHub -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`.

---

### Task 4: Polish compact root tab and navigation shell

**Files:**
- Modify: `App/AIAgentHub/UI/RootView.swift`

**Interfaces:**
- Consumes palette from Task 3.
- Produces cleaner compact tab shell.

- [ ] **Step 1: Update tab bar appearance in `CompactRootView`**

Add an `init` to `CompactRootView`:

```swift
    init(selectedRoute: Binding<AppRoute>, language: AppLanguage) {
        self._selectedRoute = selectedRoute
        self.language = language

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor(DS.Palette.tabBarBackground)
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(DS.Palette.textTertiary)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(DS.Palette.textTertiary)
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(DS.Palette.accent)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(DS.Palette.accent)
        ]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
```

Because this uses `UIKit`, add `#if canImport(UIKit) import UIKit #endif` near the top of `RootView.swift`, and wrap the `UITabBarAppearance` block in `#if canImport(UIKit)`.

- [ ] **Step 2: Keep tab icons unified**

Ensure `AppRoute.systemImage` remains:

```swift
case .chat: "message"
case .models: "sparkles.square"
case .devices: "macbook.and.iphone"
case .privacy: "shield"
```

- [ ] **Step 3: Build**

Run xcodebuild command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

---

### Task 5: Polish chat screen surfaces, session sheet, and input bar

**Files:**
- Modify: `App/AIAgentHub/UI/ChatHomeView.swift`

**Interfaces:**
- Consumes `SwipeToDeleteRow` and updated DS palette.
- Produces more product-grade chat and session list UI.

- [ ] **Step 1: Improve compact top bar**

Update `compactTopBar` so background uses a subtle material-like surface and the menu/new-chat buttons use matching circles:

```swift
.background(
    DS.Palette.surfaceElevated
        .opacity(0.96)
        .ignoresSafeArea(edges: .top)
)
```

Keep new-chat button as filled accent gradient with white icon.

- [ ] **Step 2: Improve session row visual hierarchy**

In `SessionRow.body`, set:

```swift
.padding(.horizontal, DS.Space.md)
.padding(.vertical, DS.Space.sm + 2)
.background(
    RoundedRectangle(cornerRadius: 0, style: .continuous)
        .fill(isSelected ? DS.Palette.listRowHighlight : DS.Palette.surfaceRaised)
)
```

This keeps rows flush for delete while still giving selected state.

- [ ] **Step 3: Hide raw `<think>` preview in session list**

Update `messagePreview(for:)` in `ChatHomeView.swift`:

```swift
    private func messagePreview(for session: ChatSessionRecord) -> String {
        let messages = runtime.chatRepository.messages(for: session.id)
        guard let content = messages.last?.content else { return language[.chatStartHint] }
        let stripped = content
            .replacingOccurrences(of: #"<think>[\s\S]*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? language[.chatStartHint] : stripped
    }
```

This fixes the screenshot issue where session preview shows `<think>用户想...`.

- [ ] **Step 4: Make input bar feel like a product component**

Keep current functionality, but update the input background to surface elevated, a stronger selected stroke, and keep send button gradient. Do not alter `send(in:)` logic.

- [ ] **Step 5: Verify**

Run validation and xcodebuild commands from Global Constraints.

---

### Task 6: Polish Models page into settings-style sections

**Files:**
- Modify: `App/AIAgentHub/UI/ModelConfigListView.swift`

**Interfaces:**
- Consumes updated DS palette.
- Produces a less prototype-like model management page.

- [ ] **Step 1: Replace oversized display header with app-like title block**

Change header title font from `DS.Typography.display` to `DS.Typography.title`, and reduce top padding to `DS.Space.md`.

- [ ] **Step 2: Convert provider add empty state into compact tiles**

Keep existing provider picker buttons, but ensure each tile has:

```swift
.background(
    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        .fill(DS.Palette.surfaceElevated)
)
.overlay(
    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        .stroke(DS.Palette.border.opacity(0.7), lineWidth: 0.5)
)
```

- [ ] **Step 3: Make `ModelCard` denser and app-like**

In `ModelCard`, reduce padding and use a simple list-style card:

```swift
.padding(DS.Space.md)
.background(
    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        .fill(DS.Palette.surfaceElevated)
)
.overlay(
    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        .stroke(DS.Palette.border.opacity(0.65), lineWidth: 0.5)
)
```

- [ ] **Step 4: Verify**

Run xcodebuild command from Global Constraints.

---

### Task 7: Polish Device and Privacy pages

**Files:**
- Modify: `App/AIAgentHub/UI/DeviceManagementView.swift`
- Modify: `App/AIAgentHub/UI/PrivacyAndLogsView.swift`

**Interfaces:**
- Consumes updated DS palette.
- Produces consistent settings/list visual language across non-chat pages.

- [ ] **Step 1: Device page header**

In `DeviceManagementView.swift`, reduce header title from `DS.Typography.display` to `DS.Typography.title`, and change background to `DS.Palette.surface`.

- [ ] **Step 2: Device cards**

Update `DeviceCard` to use `DS.Palette.surfaceElevated`, `DS.Palette.border.opacity(0.65)`, and consistent 44pt glyph containers.

- [ ] **Step 3: Privacy page header and rows**

In `PrivacyAndLogsView.swift`, reduce large prototype-style headings and make rows feel like iOS Settings:

```swift
.padding(DS.Space.md)
.background(
    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        .fill(DS.Palette.surfaceElevated)
)
.overlay(
    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        .stroke(DS.Palette.border.opacity(0.65), lineWidth: 0.5)
)
```

Apply to setting blocks and destructive action cards.

- [ ] **Step 4: Verify**

Run xcodebuild command from Global Constraints.

---

### Task 8: Final visual and behavior verification

**Files:**
- No code changes unless verification exposes a regression.

**Interfaces:**
- Verifies all prior tasks.

- [ ] **Step 1: Run full validation**

```bash
swift run AIAgentHubCoreValidation
```

Expected: `AIAgentHubCoreValidation: all checks passed`.

- [ ] **Step 2: Build iOS app**

```bash
DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer xcodebuild -project AI-Agent-Hub.xcodeproj -scheme AIAgentHub -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual simulator smoke test**

Install and launch:

```bash
DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
APP_PATH=/Users/bytedance/Library/Developer/Xcode/DerivedData/AI-Agent-Hub-ddfkjcqnzgueevfxioakvsvzuxea/Build/Products/Debug-iphonesimulator/AIAgentHub.app
DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer xcrun simctl install booted "$APP_PATH"
DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer xcrun simctl launch booted com.aibei.AIAgentHub
```

Manual expected behavior:
- Open compact session sheet.
- Create two sessions.
- Swipe one session left: red delete action appears on the same row height.
- Tap delete: row disappears.
- Delete final session: sheet closes and chat home shows empty state.
- Bottom tab icons are consistent.
- Chat/model/device/privacy pages share one visual system.

---

## Self-Review

**Spec coverage:**
- Reliable deletion: Task 1 + Task 2.
- Last delete returns home: Task 2 Step 4.
- Better overall UI: Tasks 3-7.
- Verification: Task 8.

**Placeholder scan:**
- No TBD/TODO placeholders remain.
- Each task names concrete files and commands.

**Type consistency:**
- `SwipeToDeleteRow` interface is defined in Task 1 and consumed in Task 2.
- `deleteSession(_:)` behavior matches current `ChatHomeView` state names.
- Palette property names match existing DS names or explicitly instruct mapping when names differ.
