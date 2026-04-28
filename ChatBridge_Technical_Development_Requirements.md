# ChatBridge 技术开发要求

> 来源：`ChatBridge_Apple_IM_Requirements.md`、`mobile_wechat_database_design_field_comments.md` 与当前 `AppleIM.xcodeproj` 工程文件。  
> 目标：将产品和数据库设计整理为可执行的 Apple 平台技术要求，并要求代码满足 Swift 6.2+ 工具链下的并发安全。

---

## 1. 工程基线

### 1.1 当前工程状态

- 当前仓库为 iOS UIKit 工程，工程名为 `AppleIM`，产品方向为 `ChatBridge`。
- 主 App、单元测试、UI 测试 Target 已存在。
- 主 App Target 当前启用了：
  - `SWIFT_APPROACHABLE_CONCURRENCY = YES`
  - `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  - `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`
- 主 App、单元测试、UI 测试 Target 当前 `SWIFT_VERSION = 6.0`。
- 主 App、单元测试、UI 测试 Target 当前已启用 `SWIFT_STRICT_CONCURRENCY = complete`。
- 当前 Project、主 App、单元测试、UI 测试 Target 的 `IPHONEOS_DEPLOYMENT_TARGET` 已统一为 `15.0`，要求适配 iOS 15+。

### 1.2 工具链要求

- 使用 Xcode 26.4.1 或更新版本。
- 使用 Swift 6.2 或更新编译器。
- Swift 语言模式使用 Swift 6。
- 所有新代码必须通过 Swift 6 完整并发检查，不允许遗留并发警告。
- Debug 与 Release 配置均应开启严格并发检查。

建议构建配置：

```text
SWIFT_VERSION = 6.0
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
```

### 1.3 平台与 UI 技术栈

- 第一阶段以 iOS 为主，保留 iPadOS 扩展能力。
- 最低系统版本为 iOS 15.0；新增 API 必须确认 iOS 15 可用性。
- 使用 iOS 16+、iOS 17+、iOS 18+、iOS 26+ API 时必须添加 `#available` 降级路径。
- 当前工程可继续使用 UIKit；新增复杂页面可按模块逐步引入 SwiftUI，但不得造成 UIKit、SwiftUI 状态双写。
- UI 层必须运行在 `MainActor`。
- 网络、数据库、媒体处理、同步、搜索索引、任务队列不得在主线程执行。

---

## 2. 架构分层要求

### 2.1 开发模式

项目统一采用 MVVM 开发模式。

要求：

- UIKit 页面使用 `ViewController + ViewModel + ViewState`。
- SwiftUI 页面使用 `View + ViewModel + ViewState`。
- View / ViewController 只负责渲染、布局、用户事件转发和导航触发。
- ViewModel 负责 UI 状态组装、输入事件处理、调用 UseCase/Service、暴露 Combine Publisher。
- ViewModel 不直接访问数据库、文件系统、Keychain 或底层网络 Client。
- 业务流程放在 UseCase / Service。
- 数据聚合与持久化访问放在 Repository。
- 单表读写和 SQL 细节放在 DAO / Store。
- 导航逻辑由 Coordinator 或 Router 管理，避免散落在 ViewModel 内。

推荐页面结构：

```text
ConversationListViewController
ConversationListViewModel
ConversationListViewState
ConversationListRowState
ConversationListCoordinator
```

或 SwiftUI：

```text
ConversationListView
ConversationListViewModel
ConversationListViewState
ConversationListRowState
```

### 2.2 推荐模块

第一阶段建议按 Swift Package 或目录模块拆分：

```text
ChatBridgeCore
ChatBridgeStore
ChatBridgeSync
ChatBridgeMedia
ChatBridgeSearch
ChatBridgeNotification
ChatBridgeSecurity
ChatBridgeUI
ChatBridgeKit
```

App Target 只负责：

- 应用启动
- 场景生命周期
- 依赖装配
- 根导航
- 推送入口
- App 级权限入口

业务能力下沉到 Core、Store、Sync、Media 等模块。

### 2.3 分层边界

```text
View / ViewController / SwiftUI View
  ↓
ViewModel
  ↓
UseCase / Service
  ↓
Repository
  ↓
DAO / Database Actor / File Actor
  ↓
SQLite / WCDB / GRDB / FileManager / Keychain
```

要求：

- UI 层不得直接访问数据库。
- ViewModel 只暴露 UI 状态、用户动作和只读 Publisher。
- ViewModel 不持有 UIKit 控件、`UIViewController`、`UIView`、`UICollectionView`、`UITableView`。
- ViewModel 不直接拼接 SQL，不直接管理数据库事务。
- ViewModel 不直接读写媒体文件，不直接访问 Keychain。
- Service 负责业务流程编排。
- Repository 负责聚合数据库、网络、缓存和任务队列。
- DAO 只处理单表或少量强相关表的读写。
- 数据库事务必须在 Store 层统一管理。

### 2.4 MVVM 输入输出规范

ViewModel 对外建议采用 Input / Output 或明确的方法与状态发布器。

UIKit 推荐形态：

```swift
@MainActor
final class ConversationListViewModel {
    struct Input {
        let viewDidLoad: AnyPublisher<Void, Never>
        let refresh: AnyPublisher<Void, Never>
        let searchText: AnyPublisher<String, Never>
    }

    struct Output {
        let state: AnyPublisher<ConversationListViewState, Never>
        let route: AnyPublisher<ConversationListRoute, Never>
    }

    func bind(input: Input) -> Output
}
```

SwiftUI 推荐形态：

```swift
@MainActor
final class ConversationListViewModel: ObservableObject {
    @Published private(set) var state = ConversationListViewState()

    func onAppear() async
    func refresh() async
    func pin(conversationID: ConversationID) async
}
```

要求：

- ViewModel 必须标记 `@MainActor`。
- ViewState 和 RowState 必须是值类型，并满足 `Equatable`、`Sendable`。
- ViewModel 的公开状态应为只读，状态修改集中在 ViewModel 内部。
- 用户输入可通过 Combine 防抖、合并、去重；业务调用使用 `async/await`。
- ViewModel 中创建的页面级 Task 必须可取消。
- ViewModel 单元测试必须能够通过 mock UseCase/Service 独立运行。

---

## 3. Swift 6.2+ 并发安全要求

### 3.1 总原则

- 异步业务流程优先使用 `async/await`。
- UI 状态流、订阅、输入防抖和事件广播使用 Combine。
- 所有跨并发域传递的模型必须满足 `Sendable`。
- 所有共享可变状态必须由 `actor`、`@MainActor` 或受控同步机制保护。
- 禁止通过全局可变单例保存用户态、数据库连接、会话状态和消息缓存。
- 禁止用 `DispatchQueue` 作为主要并发抽象；仅允许在桥接旧 API 或第三方回调时局部使用。

### 3.2 Actor 隔离

必须使用 actor 隔离以下状态：

```text
DatabaseActor
AccountSessionActor
SyncEngineActor
PendingJobActor
MediaFileActor
SearchIndexActor
TokenRefreshActor
```

建议职责：

- `DatabaseActor`：串行化写事务，管理连接、迁移、完整性检查。
- `SyncEngineActor`：管理 cursor、seq、补偿同步、消息去重。
- `PendingJobActor`：管理 pending/running/success/failed/cancelled 任务状态。
- `MediaFileActor`：管理媒体落盘、缩略图、缓存清理、文件校验。
- `SearchIndexActor`：管理 FTS 写入、重建、索引修复。

### 3.3 MainActor 要求

- `UIViewController`、`UIView`、`UICollectionViewDiffableDataSource`、SwiftUI `ViewModel` 默认视为 `@MainActor`。
- `@Published` UI 状态只允许在 `MainActor` 上更新。
- 后台任务完成后必须通过 `await MainActor.run {}` 或 `@MainActor` 方法更新 UI。
- 不得把 UIKit 类型作为跨 actor 数据传递对象，例如 `UIImage`、`UIView`、`UIViewController`。

### 3.4 Sendable 要求

以下类型必须设计为 `struct` 或不可变 `final class`，并显式满足 `Sendable`：

```text
User
Contact
Conversation
Message
MessageContent
MediaResource
Draft
SyncCheckpoint
PendingJob
```

要求：

- ID、时间戳、状态枚举均使用值类型。
- 状态枚举必须满足 `Sendable`。
- JSON 扩展字段不得以 `[String: Any]` 跨并发域传递，应使用 `Data`、`String` 或明确的 Codable 结构。
- 如必须引入 `@unchecked Sendable`，必须附带注释说明线程安全来源，并在 Code Review 中单独审查。

### 3.5 Task 与取消

- 用户离开页面时，页面级 `Task` 必须取消。
- 消息发送、媒体上传、同步拉取应支持取消和超时。
- 批量上传、缩略图生成、索引重建可使用 `withThrowingTaskGroup`。
- 禁止无归属地创建长期运行的 `Task`；长期任务必须归属于 Service 或 actor 生命周期。
- `Task.detached` 仅允许用于明确不继承当前 actor 的 CPU/IO 工作，闭包必须为 `@Sendable`，输入输出必须为 `Sendable`。

---

## 4. async/await 使用要求

### 4.1 异步 API 形态

网络、数据库、同步和媒体服务对外提供 `async throws` API：

```swift
protocol MessageService: Sendable {
    func sendText(_ text: String, in conversationID: ConversationID) async throws -> Message
    func resend(messageID: MessageID) async throws -> Message
    func revoke(messageID: MessageID) async throws
}
```

数据库写入示例要求：

```swift
actor DatabaseActor {
    func write<T: Sendable>(
        _ operation: @Sendable (DatabaseConnection) throws -> T
    ) async throws -> T
}
```

### 4.2 消息发送流程

文本消息必须按以下链路实现：

```text
生成 client_msg_id
↓
事务写入 message + message_text，send_status = sending
↓
事务更新 conversation 摘要、sort_ts
↓
通过 Combine 通知 UI 刷新
↓
async 调用服务端发送接口
↓
收到 ack 后写回 server_msg_id / seq / server_time / success
↓
失败则写入 failed，并创建 pending_job
```

图片、语音、视频、文件消息必须先完成本地落盘和内容表写入，再异步执行上传与消息 ack。

### 4.3 同步流程

同步引擎必须使用 `async/await` 串联：

```text
读取 sync_checkpoint
↓
请求增量数据
↓
按 seq 去重和排序
↓
数据库事务批量入库
↓
更新 conversation 摘要、未读数
↓
写回 sync_checkpoint
↓
发布 Store 变更事件
```

同步必须处理：

- 全量同步
- 增量同步
- 修复同步
- 多端状态同步
- 弱网中断恢复
- ack 丢失补偿

---

## 5. Combine 使用要求

### 5.1 使用边界

Combine 主要用于：

- UI 状态订阅
- 会话列表增量刷新
- 聊天页消息流刷新
- 搜索输入防抖
- 网络状态变化
- 登录状态变化
- App 生命周期事件桥接
- 通知角标变化

不建议用 Combine 作为核心网络请求和数据库事务模型；核心业务流程应使用 `async/await`。

### 5.2 Publisher 设计

Store 或 ViewModel 可暴露只读 Publisher：

```swift
@MainActor
protocol ConversationListViewModel: AnyObject {
    var conversationsPublisher: AnyPublisher<[ConversationRowState], Never> { get }
    func reload() async
    func pin(conversationID: ConversationID) async
}
```

要求：

- Publisher 输出 UI 状态，不直接输出数据库连接、DAO 或可变实体。
- Publisher 必须在主线程或 `MainActor` 更新 UI。
- 对用户输入使用 `debounce`、`removeDuplicates`、`flatMap` 或 `switchToLatest`，避免搜索请求乱序回填。
- Combine 的 `sink` 必须管理生命周期，禁止形成 ViewModel 与闭包之间的强引用环。
- ViewModel 对 View 暴露 `AnyPublisher` 或 `@Published private(set)`，不得暴露可写 subject。

### 5.3 async/await 与 Combine 桥接

- 从 async 数据源到 UI：Service 完成后更新 `@Published` 或 subject。
- 从 Publisher 到 async：使用 `values` 转为 `AsyncSequence` 时必须处理取消。
- 对搜索、网络状态、通知事件可使用 Combine 触发 `Task`，但 Task 生命周期必须受 ViewModel 或 Service 管理。

---

## 6. 本地存储要求

### 6.1 账户隔离

每个账号必须独立目录：

```text
account_xxx/
  main.db
  search.db
  file_index.db
  media/
  cache/
```

要求：

- 退出登录后不得展示上一账号数据。
- 切换账号时关闭旧账号数据库连接与任务队列。
- 删除账号数据只清理当前账号目录。
- 数据库密钥与账号绑定，存入 Keychain。

### 6.2 数据库拆分

第一阶段至少包含：

```text
main.db
search.db
file_index.db
```

大型化后可拆为：

```text
user.db
social.db
message.db
search.db
file_index.db
```

### 6.3 核心表

第一阶段必须实现：

```text
user
contact
conversation
conversation_member
message
message_text
message_image
message_voice
message_video
message_file
message_receipt
message_revoke
media_resource
draft
sync_checkpoint
pending_job
migration_meta
conversation_setting
notification_setting
blacklist
```

### 6.4 事务要求

以下操作必须位于同一事务：

```text
消息主表写入
消息内容表写入
会话摘要更新
未读数更新
sort_ts 更新
搜索索引任务创建
pending_job 创建
```

撤回和删除必须状态化处理：

- 撤回：更新 `message.revoke_status`，写入 `message_revoke`。
- 本地删除：更新 `message.is_deleted`。
- 清空聊天记录：按会话范围状态化删除，并同步更新会话摘要。

### 6.5 分页与索引

禁止深分页：

```sql
LIMIT 20 OFFSET 10000
```

必须使用游标分页：

```sql
SELECT * FROM message
WHERE conversation_id = ?
  AND sort_seq < ?
ORDER BY sort_seq DESC
LIMIT 20;
```

必须建立核心索引：

```sql
CREATE INDEX idx_message_conversation_sort ON message(conversation_id, sort_seq DESC);
CREATE INDEX idx_message_client_msg_id ON message(client_msg_id);
CREATE INDEX idx_message_server_msg_id ON message(server_msg_id);
CREATE INDEX idx_conversation_user_sort ON conversation(user_id, is_pinned DESC, sort_ts DESC);
CREATE INDEX idx_contact_user_wxid ON contact(user_id, wxid);
```

---

## 7. 模块技术要求

### 7.1 账号模块

- 登录、退出、token 刷新使用 `async/await`。
- token 刷新必须通过 `TokenRefreshActor` 防止并发刷新风暴。
- 登录态变化通过 Combine 发布给 UI 和同步模块。
- 多账号切换必须取消当前账号所有同步、上传、下载、搜索索引任务。

### 7.2 会话模块

- 会话列表读取 `conversation` 冗余字段，不实时聚合消息表。
- 会话排序规则为置顶优先，然后按 `sort_ts` 倒序。
- 新消息、草稿、置顶、免打扰变化必须增量刷新 UI。
- 会话列表 ViewModel 使用 Combine 输出 row state。

### 7.3 消息模块

- 消息主表和内容表分离。
- 消息 ID 必须包含 `local_id`、`client_msg_id`、`server_msg_id`、`seq` 四类能力。
- 消息发送必须先本地入库再请求服务端。
- 消息重发必须基于 `client_msg_id` 幂等。
- 收消息必须基于 `client_msg_id`、`server_msg_id`、`seq` 去重。
- 消息状态包括 pending、sending、success、failed。

### 7.4 媒体模块

- 图片、语音、视频、文件必须先落盘，元数据入库。
- 缩略图、波形、视频封面必须异步生成。
- 上传和下载进度可通过 Combine 发布。
- 媒体文件路径不得跨账号复用。
- 文件校验使用 md5 或更强摘要字段。

### 7.5 搜索模块

- 搜索库与主库解耦。
- 搜索索引写入异步化，不阻塞消息入库主链路。
- 搜索索引损坏后必须可重建。
- 搜索输入使用 Combine 防抖。

### 7.6 同步模块

- 同步基于 `cursor`、`seq`、`updated_at`。
- sync checkpoint 写入必须与对应业务数据入库保持事务一致或可补偿。
- 断点续传、缺口补拉和多端状态同步必须纳入第一阶段设计。
- 同步引擎必须由 actor 管理，避免多入口并发拉取造成乱序写入。

### 7.7 通知模块

- 通知权限申请使用 async 封装。
- 角标数量由本地未读数统一计算，不由 UI 分散维护。
- 免打扰会话不弹通知，但未读数仍累加。

### 7.8 安全模块

- 数据库必须加密。
- 数据库密钥不得硬编码。
- 密钥存入 Keychain，并与账号绑定。
- 日志不得打印 token、手机号、消息明文、数据库密钥、完整 SQL 参数。
- 媒体文件目录按账号隔离，重要媒体启用文件保护。

---

## 8. 本地任务队列要求

`pending_job` 必须覆盖：

```text
消息重发
图片上传
视频上传
文件上传
媒体下载
缩略图生成
搜索索引补建
消息补偿同步
```

任务状态：

```text
pending
running
success
failed
cancelled
```

要求：

- 支持最大重试次数。
- 支持 `next_retry_at`。
- 支持指数退避。
- 支持网络恢复后触发。
- App 重启后能恢复未完成任务。
- 同一 `client_msg_id` 或 `media_id` 不得重复创建并发任务。

---

## 9. 错误处理与弱网要求

必须处理：

```text
发送超时
连接断开
服务端 ack 丢失
重复消息
消息乱序
媒体上传失败
媒体下载失败
同步中断
数据库迁移失败
搜索索引损坏
媒体文件丢失
```

要求：

- 网络错误必须映射为统一业务错误。
- 用户可见错误不得暴露底层 SQL、token 或隐私字段。
- 可重试错误写入 `pending_job`。
- 不可重试错误必须有明确 UI 状态。
- 崩溃后消息不能丢失，发送中消息可恢复为 pending 或 failed。

---

## 10. 性能要求

### 10.1 会话列表

- 冷启动加载首屏会话小于 500ms。
- 普通刷新小于 100ms。
- 滚动保持 60 FPS。
- 不允许会话列表实时聚合消息表。
- 使用 diffable data source 或等价增量刷新机制。

### 10.2 聊天页

- 首屏消息加载小于 300ms。
- 上拉加载历史小于 300ms。
- 滚动保持 60 FPS。
- 使用游标分页。
- 图片、视频封面优先显示缩略图。
- 大图解码、语音波形、视频封面必须异步处理。

### 10.3 数据库

- 批量同步必须批量插入。
- 高频小写入可以合并事务。
- 搜索索引异步写入。
- 会话摘要必须在消息事务内同步更新。
- 定期执行完整性检查、FTS 重建和 VACUUM 策略。

---

## 11. 测试与验收要求

### 11.1 并发安全验收

- Swift 6 语言模式构建通过。
- 严格并发检查无警告。
- 无未审计的 `@unchecked Sendable`。
- 无 UI 线程数据库读写。
- 无后台线程直接更新 UIKit 或 SwiftUI 状态。
- 页面离开后相关 Task 能取消。

### 11.2 单元测试

必须覆盖：

- ViewModel 输入输出转换。
- ViewModel 加载、刷新、搜索、防抖和错误状态。
- ViewModel 页面级 Task 取消。
- 消息入库事务。
- 会话摘要更新。
- 未读数累加和清零。
- 消息发送状态流转。
- `client_msg_id` 幂等重发。
- `server_msg_id` 和 `seq` 去重。
- 撤回和删除状态化处理。
- pending job 重试策略。
- sync checkpoint 更新。
- 数据库迁移版本记录。

### 11.3 UI 测试

必须覆盖：

- 登录后进入会话列表。
- 进入单聊或群聊。
- 发送文本消息。
- 发送失败后重发。
- 会话置顶和取消置顶。
- 会话免打扰。
- 搜索聊天记录。

### 11.4 性能测试

必须准备本地压测数据：

```text
1 万条消息
10 万条消息
1000 个会话
100 个群聊
大量图片缩略图
弱网重试任务
```

验收目标：

- 大量会话下首屏加载稳定。
- 大量消息下聊天页分页稳定。
- 搜索索引重建不影响主链路。
- 弱网重试不产生重复消息。

---

## 12. 推荐开发顺序

### 阶段一：工程与并发基线

- 统一 Xcode Build Settings。
- 切换 Swift 6 语言模式。
- 建立模块目录或 Swift Package。
- 建立 MVVM 页面模板。
- 建立 ViewState、RowState、Route、Coordinator 命名规范。
- 定义 Sendable ID、实体、错误类型。
- 建立 actor 化的数据库、账号、任务队列骨架。
- 建立测试基线。

### 阶段二：本地存储

- 账号目录隔离。
- 数据库初始化。
- migration_meta。
- 核心表建表和索引。
- Repository / DAO。
- 事务封装。

### 阶段三：会话与文本消息

- 会话列表读取和刷新。
- 聊天页分页。
- 文本消息发送。
- 消息状态流转。
- 未读数。
- 重发。

### 阶段四：同步与弱网

- sync checkpoint。
- 增量同步。
- 去重和乱序处理。
- pending job。
- 网络恢复重试。

### 阶段五：媒体能力

- 图片消息。
- 语音消息。
- 视频和文件预留。
- 上传下载进度。
- 缩略图和缓存。

### 阶段六：搜索、通知、安全

- 搜索库和 FTS。
- 搜索索引重建。
- 通知权限和角标。
- Keychain 密钥。
- 数据库加密。
- 日志脱敏。

---

## 13. 第一阶段完成定义

第一阶段完成时应满足：

- Swift 6.2+ 工具链下严格并发检查通过。
- App 可以登录并进入会话列表。
- 支持单聊、基础群聊、文本消息、图片消息、语音消息。
- 消息本地持久化，发送失败可重发。
- 支持撤回、删除、未读数、置顶、免打扰、草稿。
- 支持基础搜索、离线消息同步、本地通知。
- 数据库按账号隔离、加密、可迁移。
- 媒体文件按账号隔离并有索引。
- 崩溃、弱网、重启后消息状态可恢复。
- 核心链路有单元测试和 UI 测试覆盖。
