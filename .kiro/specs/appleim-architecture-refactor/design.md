# AppleIM 架构优化设计规格

## 总体架构

目标分层保持：

```text
View / ViewController
  ↓
ViewModel
  ↓
Feature Service
  ↓
AccountChatStore / Module Store
  ↓
DAO / DatabaseActor / File Actor
  ↓
GRDB / SQLCipher / FileManager / Keychain
```

本轮不改变用户可见 UI 行为。架构优化以内部 API、依赖边界和测试可维护性为核心。

## Store 设计

新增账号 Store 门面：

```swift
nonisolated struct AccountChatStore: Sendable {
    let conversations: ConversationStore
    let messages: MessageStore
    let contacts: ContactStore
    let emojis: EmojiStore
    let notifications: NotificationSettingsStore
    let pendingJobs: PendingJobStore
    let mediaIndex: MediaIndexStore
    let sync: SyncStoreAdapter
}
```

设计原则：

- `AccountChatStore` 是账号维度能力入口，不直接暴露数据库连接。
- Module Store 按业务能力命名，内部复用 DAO 和 `DatabaseActor`。
- 原 `LocalChatRepository` 的跨表事务拆到对应 Store 的事务方法中。
- 事件副作用继续通过 `ChatStoreEventDispatching` 收敛，避免 Store 直接散落通知、搜索索引、角标更新。
- `ChatStoreProvider` 缓存 `AccountChatStore`，并逐步保留兼容读取入口直到调用方迁移完成。

核心事务边界：

- 发出消息：内容表、message 主表、可选 media_resource、conversation 摘要同事务写入。
- 标记会话已读：conversation 未读数、incoming unread message read_status、@ 提示清理同事务更新。
- 接收同步批次：去重、消息插入、会话摘要、未读数、checkpoint 同事务更新，事务后分发通知和索引事件。
- 媒体上传状态：媒体内容表、message send_status、pending job 同事务更新。
- 删除/撤回：message 状态、revoke 记录、搜索移除或更新、会话变更事件保持一致。

## Chat 服务设计

`ChatViewModel` 使用组合依赖：

```swift
@MainActor
final class ChatViewModel {
    struct Dependencies: Sendable {
        let identity: ChatConversationIdentity
        let timeline: any ChatTimelineServicing
        let draft: any ChatDraftServicing
        let sender: any ChatMessageSendingServicing
        let actions: any ChatMessageActionServicing
        let group: any ChatGroupServicing
        let emojis: any ChatEmojiPanelServicing
        let simulation: any ChatSimulationServicing
    }
}
```

服务职责：

- `ChatTimelineServicing`：首屏、历史分页、最新消息观察。
- `ChatDraftServicing`：读取、保存、清空草稿。
- `ChatMessageSendingServicing`：文本、媒体、表情发送，返回消息状态流。
- `ChatMessageActionServicing`：重发、删除、撤回、标记语音已播放。
- `ChatGroupServicing`：群成员、当前角色、公告读取和更新。
- `ChatEmojiPanelServicing`：表情面板状态、收藏、最近使用。
- `ChatSimulationServicing`：调试和 UI 测试用模拟 incoming push。

`ChatMessageRowMapper` 保持独立值类型，所有服务复用同一映射逻辑，避免 `LocalChatUseCase` 内部重复 row 构造。

## 其他模块服务设计

- `ConversationListServicing` 替代 `ConversationListUseCase` 命名，负责分页、观察、置顶、免打扰、模拟收消息。
- `ContactListServicing` 替代 `ContactListUseCase` 命名，负责联系人分组、打开会话、模拟联系人资料变更。
- `SearchServicing` 替代 `SearchUseCase` 命名，负责搜索和索引重建。
- `LoginSessionServicing` 负责认证和会话保存，`LoginViewModel` 不再同时持有认证服务和 session store。

命名迁移采用“一次性生产类型替换，测试替身同步改名”的方式，避免长期保留 UseCase 兼容壳。

## App 层设计

App 层新增服务：

- `AppSessionCoordinator`：登录态读取、登录成功、退出、切换账号、删除当前账号本地数据。
- `AppDependencyFactory`：根据账号会话、UI 测试配置和服务端环境创建 `AppDependencyContainer`。
- `ServerMessageSendConfigurationFactory`：从环境变量和 token actor 创建真实发送配置。

`SceneDelegate` 保留：

- 创建 window。
- 根据会话状态展示登录或主界面。
- 转发场景前台/活跃事件。
- 应用语言上下文到 window。

## 测试设计

- Store 重组先用现有 Store/Database 测试保护事务语义。
- Chat 拆分先添加 `ChatViewModel.Dependencies` 测试辅助，验证测试替身不必实现无关能力。
- 命名迁移后跑会话列表、通讯录、搜索、登录单元测试。
- App 装配收敛后补充或更新 App 生命周期服务测试。
- 最后跑全量单元和关键 UI 回归。
