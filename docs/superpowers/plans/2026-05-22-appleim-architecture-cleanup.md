# AppleIM Architecture Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 全量修复剩余 `@unchecked Sendable` 审计、性能诊断抽象、文件系统访问集中、测试结构整理和 UIKit 复杂视图组件化问题。

**Architecture:** 按“并发可信度 -> 诊断基础设施 -> 文件边界 -> 测试可维护性 -> UI 组件化”的顺序推进。每批保持现有用户行为不变，优先引入小接口和适配器，再迁移调用方，避免一次性重写聊天或会话模块。

**Tech Stack:** iOS UIKit，Swift 6 严格并发，Swift Testing，XCTest UI Tests，GRDB + SQLCipher，本地 `xcodebuild` 验证。

---

## Files And Responsibilities

- Create: `AppleIM/Core/Concurrency/SendableSafetyNotes.swift`
  - 统一记录无法完全移除的 Foundation/UIKit/Objective-C token 类 Sendable 依据，避免散落解释。
- Modify: `AppleIM/Database/DatabaseActor.swift`
  - 移除或集中解释数据库观察取消盒的 `@unchecked Sendable`，保证取消路径线程安全。
- Modify: `AppleIM/Media/TemporaryMediaFileManager.swift`
  - 将临时媒体文件管理的线程安全依据补完整；如同步协议无法改 async，本轮保留最窄 `@unchecked Sendable`。
- Modify: `AppleIM/Network/ChatBridgeHTTPClient.swift`
  - 消除共享 `JSONEncoder` / `JSONDecoder` 造成的并发疑点，优先改为方法内局部实例。
- Modify: `AppleIM/Notification/LocalNotificationManager.swift`
  - 保留通知中心 manager 的 `@unchecked Sendable`，补充 delegate 生命周期和系统线程安全依据。
- Modify: `AppleIM/Account/AccountSessionStore.swift`
  - 收窄 UserDefaults session store 的并发说明，避免把复杂对象访问泛化成线程安全。
- Modify: `AppleIM/UI/AvatarImageLoader.swift`
  - 补充 `Task` 取消 wrapper 的线程安全依据，或改为值类型 token。
- Modify: `AppleIM/Core/Localization/AppLanguage.swift`
  - 保留主 actor 内 token wrapper，并把说明指向统一审计备注。
- Create: `AppleIM/Core/Diagnostics/PerformanceMeasuring.swift`
  - 提供 `PerformanceMeasuring`、`SystemPerformanceMeasurer`、`PerformanceSpan`，集中 `systemUptime` 和 elapsed 文案。
- Create: `AppleIMTests/Core/PerformanceMeasuringTests.swift`
  - 覆盖固定时钟下 elapsed 计算和日志标签生成。
- Modify: `AppleIM/Core/AppLogger.swift`
  - 保留兼容 API，同时委托新的 `PerformanceMeasuring`。
- Modify: `AppleIM/Store/ChatStoreProvider.swift`
  - 将启动、seed、key、storage 准备计时代码改为 `PerformanceMeasuring`。
- Modify: `AppleIM/Features/ConversationList/ConversationListUseCase.swift`
  - 将会话加载计时代码迁移到诊断接口。
- Modify: `AppleIM/Features/ConversationList/ConversationListViewModel.swift`
  - 将状态发布和加载耗时迁移到诊断接口。
- Modify: `AppleIM/Features/ConversationList/ConversationListViewController.swift`
  - 将渲染和 snapshot 计时代码迁移到诊断接口。
- Modify: `AppleIM/Features/Chat/ChatViewModel.swift`
  - 替换直接 `ProcessInfo.processInfo.systemUptime`，保留录音/播放业务时钟独立注入。
- Modify: `AppleIM/Features/Chat/ChatUseCase.swift`
  - 替换 peer push 相关计时。
- Modify: `AppleIM/Features/Chat/ChatUseCaseCollaborators.swift`
  - 替换发送链路计时。
- Modify: `AppleIM/Features/Chat/ChatViewController.swift`
  - 替换 render/snapshot 计时。
- Modify: `AppleIM/Sync/SimulatedIncomingPushService.swift`
  - 替换模拟推送诊断计时。
- Modify: `AppleIM/Database/DatabaseActor.swift`
  - 替换 pool open/close 计时。
- Create: `AppleIM/Media/MediaPathResolving.swift`
  - 提供 `MediaPathResolving`，统一历史媒体路径修复和存在性判断。
- Modify: `AppleIM/Store/MessageDAO.swift`
  - 移除 Store 层直接 `FileManager.default` 路径判断，改依赖 `MediaPathResolving`。
- Modify: `AppleIM/Store/LocalChatRepository.swift`
  - 继续通过 `MediaFileMetadataProviding` 聚合文件存在性和大小读取，不再新增 Store 直连文件系统。
- Modify: `AppleIMTests/Store/StoreMediaAndRepairTests.swift`
  - 补路径解析、文件缺失、历史媒体路径恢复测试。
- Split: `AppleIMTests/TestSupport/TestSupport.swift`
  - 拆为 `AppleIMTests/TestSupport/ChatUseCaseSpies.swift`
  - 拆为 `AppleIMTests/TestSupport/StoreSpies.swift`
  - 拆为 `AppleIMTests/TestSupport/AccountSpies.swift`
  - 拆为 `AppleIMTests/TestSupport/DiagnosticsSpies.swift`
  - 保留 `AppleIMTests/TestSupport/TestSupport.swift` 作为共享模型和工厂入口。
- Split: `AppleIMTests/Chat/ChatViewControllerLayoutTests.swift`
  - 拆出聊天锚点、键盘、附件、snapshot 类测试文件。
- Split: `AppleIMTests/Chat/ChatUseCaseAndRecoveryTests.swift`
  - 拆出发送、媒体、恢复、交互类测试文件。
- Split: `AppleIMTests/UIComponents/UIComponentTests.swift`
  - 拆为输入栏、表情、相册、账号 cell 类测试文件。
- Modify: `AppleIM/Features/Chat/ChatInputBarView.swift`
  - 拆出输入区域 renderer、面板 host、语音预览子视图，宿主保留状态组合和 action 转发。
- Modify: `AppleIM/Features/Chat/ChatMessageCell.swift`
  - 拆出内容配置 renderer、附件视图工厂、状态/气泡样式 renderer。
- Modify: `AppleIM/Features/Chat/ChatPhotoLibraryInputView.swift`
  - 拆出数据源 coordinator 和 selection presenter，保留 UICollectionView 宿主职责。
- Modify: `AppleIM/Features/ConversationList/ConversationListViewController.swift`
  - 拆出 snapshot planner 和 cell provider helper，ViewController 保留生命周期与导航。

---

## Task 0: Baseline And Guardrails

**Files:**
- Read: `AGENTS.md`
- Read: `AppleIM.xcodeproj`
- No source modifications.

- [ ] **Step 1: Check current worktree**

Run:

```bash
git status --short
git branch --show-current
```

Expected: current branch is `codex/architecture-remediation`; existing unstaged remediation changes are preserved.

- [ ] **Step 2: Run build baseline**

Run:

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: `TEST BUILD SUCCEEDED`.

- [ ] **Step 3: Capture current issue counts**

Run:

```bash
rg -n "@unchecked Sendable|unchecked Sendable" AppleIM AppleIMTests
rg -n "ProcessInfo\\.processInfo\\.systemUptime" AppleIM
rg -n "FileManager\\.default|attributesOfItem|fileExists\\(" AppleIM/Store AppleIM/Features AppleIM/Media
find AppleIMTests -name '*.swift' -print0 | xargs -0 wc -l | sort -nr | head -12
```

Expected: output matches the known open areas and gives before/after comparison data.

---

## Task 1: Production `@unchecked Sendable` Audit

**Files:**
- Create: `AppleIM/Core/Concurrency/SendableSafetyNotes.swift`
- Modify: `AppleIM/Database/DatabaseActor.swift`
- Modify: `AppleIM/Media/TemporaryMediaFileManager.swift`
- Modify: `AppleIM/Network/ChatBridgeHTTPClient.swift`
- Modify: `AppleIM/Notification/LocalNotificationManager.swift`
- Modify: `AppleIM/Account/AccountSessionStore.swift`
- Modify: `AppleIM/UI/AvatarImageLoader.swift`
- Modify: `AppleIM/Core/Localization/AppLanguage.swift`

- [ ] **Step 1: Write audit documentation source**

Add `SendableSafetyNotes.swift`:

```swift
//
//  SendableSafetyNotes.swift
//  AppleIM
//
//  并发安全审计说明
//

import Foundation

/// 记录 Foundation、UIKit 或 Objective-C 回调 token 未标注 Sendable 时的本地约束。
///
/// 新增 `@unchecked Sendable` 前必须满足：
/// 1. 类型不暴露可变业务状态，或可变状态由 actor / lock / 系统线程安全对象保护。
/// 2. 跨并发边界只执行取消、读取不可变配置或系统线程安全 API。
/// 3. 代码附近写明具体依据，不能只写“为了通过 Swift 6”。
enum SendableSafetyNotes {
    static let requiresLocalJustification = true
}
```

- [ ] **Step 2: Remove HTTP client encoder/decoder shared mutable state**

In `ChatBridgeHTTPClient`, delete stored `encoder` and `decoder`, then create them inside `postJSON`:

```swift
let encoder = JSONEncoder()
request.httpBody = try encoder.encode(body)

let (data, response) = try await session.data(for: request)
let decoder = JSONDecoder()
return try decoder.decode(Response.self, from: data)
```

Expected: HTTP client `@unchecked Sendable` rationale only depends on immutable configuration and `URLSession`.

- [ ] **Step 3: Convert trivial cancellation wrappers where possible**

For `AvatarImageTask`, first try a value wrapper:

```swift
nonisolated private struct AvatarImageTask: AvatarImageLoadTask, Sendable {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}
```

If protocol conformance requires class identity, keep final class and add a specific comment that the only operation is `Task.cancel()`, which is safe to call from any task.

- [ ] **Step 4: Document remaining production unchecked conformances**

Each remaining production `@unchecked Sendable` must have a comment block with this shape:

```swift
/// ## Sendable 审计
///
/// 保留 `@unchecked Sendable` 的原因：
/// - [具体系统类型] 未声明 Sendable。
/// - 本类型只保存不可变引用，不保存可变业务状态。
/// - 暴露方法只调用 [具体线程安全/幂等 API]。
/// - 生命周期由 [actor / main actor / owning type] 管理。
```

Apply it to:
- `DefaultTemporaryMediaFileManager`
- `DatabaseObservationCancellableBox`
- `UserNotificationCenterNotificationManager`
- `UserDefaultsAccountSessionStore`
- `NotificationObservationToken`

- [ ] **Step 5: Verify no unexplained production unchecked remains**

Run:

```bash
rg -n "@unchecked Sendable" AppleIM
```

Expected: every production hit is either removed or has adjacent `Sendable 审计` text within the same declaration comment.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: `TEST BUILD SUCCEEDED`.

---

## Task 2: Performance Diagnostics Abstraction

**Files:**
- Create: `AppleIM/Core/Diagnostics/PerformanceMeasuring.swift`
- Create: `AppleIMTests/Core/PerformanceMeasuringTests.swift`
- Modify: `AppleIM/Core/AppLogger.swift`
- Modify all production files currently using `ProcessInfo.processInfo.systemUptime` for diagnostics.

- [ ] **Step 1: Add failing tests for fixed-clock measurement**

Create `AppleIMTests/Core/PerformanceMeasuringTests.swift`:

```swift
import Testing
@testable import AppleIM

struct PerformanceMeasuringTests {
    @Test
    func fixedPerformanceMeasurerFormatsElapsedMilliseconds() {
        let measurer = FixedPerformanceMeasurer(nowValues: [10, 10.125])
        let span = measurer.start("chat.render")

        #expect(measurer.elapsedMilliseconds(since: span) == "125.0ms")
    }
}

private struct FixedPerformanceMeasurer: PerformanceMeasuring {
    let nowValues: [TimeInterval]
    private let index = ManagedAtomicCounter()

    func start(_ name: String) -> PerformanceSpan {
        PerformanceSpan(name: name, startUptime: nowValues[0])
    }

    func elapsedMilliseconds(since span: PerformanceSpan) -> String {
        let next = nowValues[min(index.increment(), nowValues.count - 1)]
        return PerformanceFormatting.elapsedMilliseconds(from: span.startUptime, to: next)
    }
}

private final class ManagedAtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }
}
```

Run:

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected before implementation: compile failure because `PerformanceMeasuring` does not exist.

- [ ] **Step 2: Implement production abstraction**

Add `PerformanceMeasuring.swift`:

```swift
import Foundation

nonisolated struct PerformanceSpan: Sendable {
    let name: String
    let startUptime: TimeInterval
}

nonisolated protocol PerformanceMeasuring: Sendable {
    func start(_ name: String) -> PerformanceSpan
    func elapsedMilliseconds(since span: PerformanceSpan) -> String
}

nonisolated struct SystemPerformanceMeasurer: PerformanceMeasuring {
    static let shared = SystemPerformanceMeasurer()

    func start(_ name: String) -> PerformanceSpan {
        PerformanceSpan(name: name, startUptime: ProcessInfo.processInfo.systemUptime)
    }

    func elapsedMilliseconds(since span: PerformanceSpan) -> String {
        PerformanceFormatting.elapsedMilliseconds(
            from: span.startUptime,
            to: ProcessInfo.processInfo.systemUptime
        )
    }
}

nonisolated enum PerformanceFormatting {
    static func elapsedMilliseconds(from startUptime: TimeInterval, to endUptime: TimeInterval) -> String {
        let milliseconds = (endUptime - startUptime) * 1_000
        return String(format: "%.1fms", milliseconds)
    }
}
```

- [ ] **Step 3: Keep AppLogger compatibility**

Change `AppLogger.elapsedMilliseconds(since:)`:

```swift
static func elapsedMilliseconds(since startUptime: TimeInterval) -> String {
    PerformanceFormatting.elapsedMilliseconds(
        from: startUptime,
        to: ProcessInfo.processInfo.systemUptime
    )
}
```

- [ ] **Step 4: Migrate diagnostics callers**

Replace diagnostic code from:

```swift
let startUptime = ProcessInfo.processInfo.systemUptime
logger.info("... elapsed=\(AppLogger.elapsedMilliseconds(since: startUptime))")
```

to:

```swift
let span = performanceMeasurer.start("chat.render")
logger.info("... elapsed=\(performanceMeasurer.elapsedMilliseconds(since: span))")
```

Use default constructor injection:

```swift
private let performanceMeasurer: any PerformanceMeasuring

init(
    ...,
    performanceMeasurer: any PerformanceMeasuring = SystemPerformanceMeasurer.shared
) {
    self.performanceMeasurer = performanceMeasurer
}
```

Apply to Store, ConversationList, Chat, Sync and Database diagnostic-only uptime usage. Keep `currentUptime` in `ChatViewModel` for voice/playback business timing until that state machine is separately refactored.

- [ ] **Step 5: Verify direct diagnostic uptime is gone**

Run:

```bash
rg -n "ProcessInfo\\.processInfo\\.systemUptime" AppleIM
```

Expected: no production hits except allowed business-time injection default in `ChatViewModel` and compatibility implementation in `AppLogger` / `PerformanceMeasuring`.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: `TEST BUILD SUCCEEDED`.

---

## Task 3: File-System Boundary Consolidation

**Files:**
- Create: `AppleIM/Media/MediaPathResolving.swift`
- Modify: `AppleIM/Store/MessageDAO.swift`
- Modify: `AppleIM/Store/LocalChatRepository.swift`
- Modify: `AppleIMTests/Store/StoreMediaAndRepairTests.swift`

- [ ] **Step 1: Add path resolver tests**

Add tests to `StoreMediaAndRepairTests`:

```swift
@Test
func mediaPathResolverKeepsExistingStoredPath() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let stored = root.appendingPathComponent("media/image/a.jpg")
    try FileManager.default.createDirectory(at: stored.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: stored.path, contents: Data())

    let resolver = DefaultMediaPathResolver(metadataProvider: DefaultMediaFileMetadataProvider())
    let resolved = resolver.resolvedMediaPath(stored.path, mediaDirectory: root.appendingPathComponent("media"))

    #expect(resolved == stored.path)
}

@Test
func mediaPathResolverMapsLegacyMediaPathWhenCurrentFileExists() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mediaDirectory = root.appendingPathComponent("media")
    let current = mediaDirectory.appendingPathComponent("image/a.jpg")
    try FileManager.default.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: current.path, contents: Data())

    let legacy = "/old/account/media/image/a.jpg"
    let resolver = DefaultMediaPathResolver(metadataProvider: DefaultMediaFileMetadataProvider())

    #expect(resolver.resolvedMediaPath(legacy, mediaDirectory: mediaDirectory) == current.path)
}
```

- [ ] **Step 2: Implement resolver**

Add `MediaPathResolving.swift`:

```swift
import Foundation

nonisolated protocol MediaPathResolving: Sendable {
    func resolvedMediaPath(_ storedPath: String, mediaDirectory: URL) -> String
}

nonisolated struct DefaultMediaPathResolver: MediaPathResolving {
    private let metadataProvider: any MediaFileMetadataProviding

    init(metadataProvider: any MediaFileMetadataProviding = DefaultMediaFileMetadataProvider()) {
        self.metadataProvider = metadataProvider
    }

    func resolvedMediaPath(_ storedPath: String, mediaDirectory: URL) -> String {
        guard !metadataProvider.fileExists(atPath: storedPath) else {
            return storedPath
        }

        let standardizedPath = URL(fileURLWithPath: storedPath).standardizedFileURL.path
        guard let mediaRange = standardizedPath.range(of: "/media/") else {
            return storedPath
        }

        let relativeMediaPath = String(standardizedPath[mediaRange.upperBound...])
        let currentPath = mediaDirectory.appendingPathComponent(relativeMediaPath).path
        guard metadataProvider.fileExists(atPath: currentPath) else {
            return storedPath
        }
        return currentPath
    }
}
```

- [ ] **Step 3: Inject resolver into DAO path mapping**

Change `MessageDAO` media path mapping helper from static `FileManager.default` to injected resolver. If `MessageDAO` currently has no initializer dependency, add:

```swift
private let mediaPathResolver: any MediaPathResolving

init(mediaPathResolver: any MediaPathResolving = DefaultMediaPathResolver()) {
    self.mediaPathResolver = mediaPathResolver
}
```

Then replace:

```swift
emoji.localPath.map { resolvedMediaPath($0, in: paths) }
```

with:

```swift
emoji.localPath.map { mediaPathResolver.resolvedMediaPath($0, mediaDirectory: paths.mediaDirectory) }
```

- [ ] **Step 4: Verify Store and Feature direct file access**

Run:

```bash
rg -n "FileManager\\.default|attributesOfItem|fileExists\\(" AppleIM/Store AppleIM/Features
```

Expected: no Store/Feature file-system hits except protocol method names such as `fileExists(at:)` in Feature helpers that call injected abstractions.

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: `TEST BUILD SUCCEEDED`.

---

## Task 4: Test Support Split And Test `@unchecked Sendable` Cleanup

**Files:**
- Split: `AppleIMTests/TestSupport/TestSupport.swift`
- Create: `AppleIMTests/TestSupport/ChatUseCaseSpies.swift`
- Create: `AppleIMTests/TestSupport/StoreSpies.swift`
- Create: `AppleIMTests/TestSupport/AccountSpies.swift`
- Create: `AppleIMTests/TestSupport/DiagnosticsSpies.swift`
- Split long Chat and UI component test files.

- [ ] **Step 1: Move diagnostics spy**

Move `ConversationListLoadingDiagnosticsSpy` into `DiagnosticsSpies.swift`. Replace `@unchecked Sendable` with an actor-backed recorder:

```swift
final class ConversationListLoadingDiagnosticsSpy: ConversationListLoadingDiagnostics, Sendable {
    private let recorder = DiagnosticsSpyRecorder()

    func record(_ event: ConversationListLoadingDiagnosticEvent) {
        Task { await recorder.append(event) }
    }

    func events() async -> [ConversationListLoadingDiagnosticEvent] {
        await recorder.events
    }
}

private actor DiagnosticsSpyRecorder {
    private(set) var events: [ConversationListLoadingDiagnosticEvent] = []

    func append(_ event: ConversationListLoadingDiagnosticEvent) {
        events.append(event)
    }
}
```

- [ ] **Step 2: Move ChatUseCase stubs**

Move all `*StubChatUseCase` and `*StubChatUseCase` classes from `TestSupport.swift` to `ChatUseCaseSpies.swift`. For each mutable stub, choose one of:
- Mark the class `@MainActor` if all tests already use it from main actor.
- Move mutable arrays/counters into a private actor recorder if tests await cross-task state.

Use this actor recorder pattern:

```swift
private actor ChatUseCaseCallRecorder<Value: Sendable> {
    private var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }

    func allValues() -> [Value] {
        values
    }
}
```

- [ ] **Step 3: Move Account and Store fakes**

Move `InMemoryAccountSessionStore` to `AccountSpies.swift`. If `AccountSessionStore` remains synchronous, keep `NSLock` protected state and document the single test-only `@unchecked Sendable`; otherwise convert protocol to async in a separate task.

Use this shape if keeping sync:

```swift
final class InMemoryAccountSessionStore: AccountSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSession: AccountSession?

    nonisolated func loadSession() -> AccountSession? {
        lock.lock()
        defer { lock.unlock() }
        return storedSession
    }
}
```

- [ ] **Step 4: Split oversized test files by behavior**

Move tests without changing assertions:
- `ChatViewControllerLayoutTests.swift` -> anchor, keyboard, attachment, snapshot files.
- `ChatUseCaseAndRecoveryTests.swift` -> sending, media, recovery, interaction files.
- `UIComponentTests.swift` -> input bar, emoji, photo library, account cell files.

Each new file imports:

```swift
import Testing
@testable import AppleIM
```

- [ ] **Step 5: Verify file sizes and unchecked count**

Run:

```bash
find AppleIMTests -name '*.swift' -print0 | xargs -0 wc -l | sort -nr | head -12
rg -n "@unchecked Sendable" AppleIMTests
```

Expected:
- `AppleIMTests/TestSupport/TestSupport.swift` under 900 lines.
- No single test file above 1500 lines unless it is pure static fixture data.
- Remaining test `@unchecked Sendable` hits are lock-protected and documented.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: `TEST BUILD SUCCEEDED`.

---

## Task 5: UIKit Complex View Componentization

**Files:**
- Modify: `AppleIM/Features/Chat/ChatInputBarView.swift`
- Create: `AppleIM/Features/Chat/ChatInputBarAttachmentPreviewTrackView.swift`
- Create: `AppleIM/Features/Chat/ChatInputBarPanelHostView.swift`
- Create: `AppleIM/Features/Chat/ChatMessageContentRenderer.swift`
- Create: `AppleIM/Features/Chat/ChatMessageBubbleStyleRenderer.swift`
- Modify: `AppleIM/Features/Chat/ChatMessageCell.swift`
- Create: `AppleIM/Features/Chat/ChatPhotoLibrarySelectionCoordinator.swift`
- Modify: `AppleIM/Features/Chat/ChatPhotoLibraryInputView.swift`
- Create: `AppleIM/Features/ConversationList/ConversationListSnapshotPlanner.swift`
- Modify: `AppleIM/Features/ConversationList/ConversationListViewController.swift`
- Modify: existing layout/UI component tests.

- [ ] **Step 1: Extract input bar attachment preview track**

Move preview collection and selection display logic from `ChatInputBarView` into:

```swift
@MainActor
final class ChatInputBarAttachmentPreviewTrackView: UIView {
    var onRemove: ((UUID) -> Void)?

    func render(_ previews: [ChatPendingAttachmentPreviewState]) {
        isHidden = previews.isEmpty
        // existing preview subview update logic moves here unchanged
    }
}
```

Expected: `ChatInputBarView` keeps only `attachmentPreviewTrack.render(state.pendingAttachments)`.

- [ ] **Step 2: Extract input panel host**

Move emoji/photo/custom keyboard panel container logic into:

```swift
@MainActor
final class ChatInputBarPanelHostView: UIView {
    func show(_ panel: UIView?) {
        subviews.forEach { $0.removeFromSuperview() }
        guard let panel else {
            isHidden = true
            return
        }
        isHidden = false
        addSubview(panel)
        panel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
```

- [ ] **Step 3: Extract message cell renderers**

Create renderer types that are UIKit-only and main-actor isolated:

```swift
@MainActor
struct ChatMessageContentRenderer {
    func configure(contentView: UIView, row: ChatMessageRowState) {
        // existing content branch logic moves here unchanged
    }
}

@MainActor
struct ChatMessageBubbleStyleRenderer {
    func apply(to bubbleView: UIView, row: ChatMessageRowState) {
        // existing bubble style logic moves here unchanged
    }
}
```

Expected: `ChatMessageCell` remains responsible for cell lifecycle, reuse, accessibility identifiers and delegating actions.

- [ ] **Step 4: Extract photo library selection coordinator**

Move pending asset selection and prepared media mapping into:

```swift
@MainActor
final class ChatPhotoLibrarySelectionCoordinator {
    private(set) var selectedIdentifiers: Set<String> = []

    func toggle(identifier: String) {
        if selectedIdentifiers.contains(identifier) {
            selectedIdentifiers.remove(identifier)
        } else {
            selectedIdentifiers.insert(identifier)
        }
    }
}
```

Expected: `ChatPhotoLibraryInputView` owns collection view and delegates selection state to coordinator.

- [ ] **Step 5: Extract conversation list snapshot planner**

Create:

```swift
@MainActor
struct ConversationListSnapshotPlanner {
    func makePlan(previousIDs: [ConversationID], rows: [ConversationRowState]) -> ConversationListSnapshotPlan {
        // existing diff / append / reconfigure decision logic moves here unchanged
    }
}
```

Expected: `ConversationListViewController` render method becomes orchestration only.

- [ ] **Step 6: Run focused layout/component tests where simulator works**

Run build-safe verification first:

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

If CoreSimulator is healthy, run:

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests/chatInputBar
```

Expected: build passes; runtime tests pass when simulator service is available.

---

## Task 6: Final Regression And Documentation

**Files:**
- Modify: `ChatBridge_Development_Task_Schedule.md`
- Modify: `ChatBridge_Technical_Development_Requirements.md`

- [ ] **Step 1: Update architecture remediation notes**

Add a concise progress update with:
- Production unchecked Sendable audit result.
- Performance diagnostics abstraction result.
- File-system boundary result.
- Test split result.
- UIKit componentization result.

- [ ] **Step 2: Run final static scans**

Run:

```bash
rg -n "@unchecked Sendable" AppleIM AppleIMTests
rg -n "ProcessInfo\\.processInfo\\.systemUptime" AppleIM
rg -n "FileManager\\.default|attributesOfItem|fileExists\\(" AppleIM/Store AppleIM/Features
find AppleIMTests -name '*.swift' -print0 | xargs -0 wc -l | sort -nr | head -12
git diff --check
```

Expected:
- Production `@unchecked Sendable` is removed or locally justified.
- Diagnostic `systemUptime` is centralized.
- Store/Feature file-system access is through abstractions.
- Test files are split to sustainable sizes.
- No whitespace errors.

- [ ] **Step 3: Run final build**

Run:

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: `TEST BUILD SUCCEEDED`.

- [ ] **Step 4: Attempt runtime tests if CoreSimulator is available**

Run:

```bash
xcrun simctl list devices available
```

If this succeeds, run focused tests:

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests
```

If CoreSimulator reports `Connection refused` or `CoreSimulatorService connection became invalid`, record the blocker and do not claim runtime tests passed.

---

## Self-Review

- Spec coverage: all five requested areas are covered by Tasks 1-5, with final verification in Task 6.
- Placeholder scan: no `TBD` or open-ended implementation placeholders are used; each task names files, code shape and verification commands.
- Type consistency: `PerformanceMeasuring`, `PerformanceSpan`, `MediaPathResolving`, `DefaultMediaPathResolver` and renderer/coordinator names are introduced before later tasks reference them.
- Risk: Task 5 is the largest UI movement and should be run after Tasks 1-4 are green. If scope pressure appears, split Task 5 into three commits: input bar, message cell, conversation list.

