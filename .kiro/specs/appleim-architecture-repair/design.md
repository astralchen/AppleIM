# AppleIM 架构修复设计规格

## 总体设计

本轮采用“主链路一次性切换，底层实现分阶段内收”的方式：

```text
ViewController
  ↓
ViewModel
  ↓
Feature Service
  ↓
AccountChatStore / 窄 Store
  ↓
LocalChatRepository 内部实现 / DAO
  ↓
DatabaseActor / GRDB / SQLCipher
```

生产上层不再直接获取 `LocalChatRepository`，但 Store 内部可以临时复用它承载现有事务和事件副作用，避免在同一轮重写全部 SQL 和跨表事务。

## Store 设计

`ChatStoreProvider` 暴露两个层级：

- `accountStore()`：生产上层默认入口，返回 `AccountChatStore`。
- `internalRepositoryForStoreMaintenance()`：仅 Store 内部维护、演示数据 seed、修复服务使用，不向 feature/App 主链路扩散。

`AccountChatStore` 对上层暴露：

- `conversations`
- `messages`
- `contacts`
- `notificationSettings`
- `pendingJobs`
- `mediaIndex`
- `emojis`
- `sync`
- `simulatedIncomingPushRepository`
- `simulatedContactProfilePushRepository`
- `dataRepairRepository`

当前实现仍可委托底层 repository；后续再把这些能力迁移到具体 Store 实现文件。架构测试关注“上层调用边界”，不要求本轮删除底层实现文件。

## Chat 服务设计

`ChatViewModel.Dependencies` 是唯一生产入口。`StoreBackedChatServicesFactory` 负责为一个会话创建完整服务组：

```swift
nonisolated struct StoreBackedChatServicesFactory: Sendable {
    func makeDependencies() -> ChatViewModel.Dependencies
}
```

服务实现以 `StoreBackedChatServiceHub` 复用现有 `StoreBackedChatUseCase` 逻辑，但只通过窄服务协议暴露给 ViewModel。App 装配不再看见 `ChatUseCase`。

旧 `ChatUseCase` 相关类型若暂时保留，只能作为文件内部兼容实现，不能作为 ViewModel 或 App 主入口。下一轮可在 Store 具体实现完全拆开后删除。

## App 层设计

`AppDependencyContainer` 继续作为当前账号下的模块 factory，但：

- `makeChatViewController` 使用 `StoreBackedChatServicesFactory`。
- `prepareCurrentAccountStorage` 通过 `accountStore()` 触发 bootstrap，不直接请求 repository。
- 账号结束、删除本地数据和关闭连接继续由 `AccountLifecycleService` 编排。

`SceneDelegate` 只持有窗口、根控制器切换、语言上下文和 scene 生命周期转发。删除本地数据失败时仍保留当前登录态并展示用户文案。

## 测试稳定设计

测试 fixture 修复原则：

- JSON fixture 使用 `JSONSerialization` 或 `JSONEncoder` 生成，写入前执行解析校验。
- 异步观察测试等待具体目标状态，不只等待任意首帧。
- 搜索 repair 测试使用独立 root、独立账号、独立 `SearchIndexActor`，并等待 pending job 写入。
- 依赖 UIKit 全局状态的测试集中串行执行或显式重置全局状态。

## 架构测试设计

新增 `ArchitectureBoundaryTests`：

- 读取 `AppleIM/` 下 Swift 文件。
- 排除 Store 内部实现、测试配置和已批准的维护入口。
- 扫描违规片段并输出文件路径。
- 测试只表达边界，不要求理解 AST，避免引入额外工具。
