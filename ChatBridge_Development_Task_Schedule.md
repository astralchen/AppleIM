# ChatBridge 开发需求任务周期表

> 依据：`ChatBridge_Apple_IM_Requirements.md`、`mobile_wechat_database_design_field_comments.md`、`ChatBridge_Technical_Development_Requirements.md`。  
> 技术基线：iOS 15+、Swift 6.0 语言模式、Swift 6.2+ 工具链、MVVM、async/await、Combine、严格并发检查。  
> 周期假设：第一阶段 MVP 按 14 周规划；可根据团队人数、服务端接口就绪情况和 UI 设计交付情况调整。

---

## 1. 总体周期规划

| 阶段 | 周期 | 目标 | 核心交付物 |
|---|---:|---|---|
| 阶段 0 | 第 1 周 | 工程与规范基线 | Swift 6 并发配置、iOS 15+ 配置、MVVM 模板、模块目录、编码规范 |
| 阶段 1 | 第 2-3 周 | 本地存储与账号隔离 | 账号目录、数据库初始化、核心表、迁移、Repository/DAO |
| 阶段 2 | 第 4-6 周 | 会话与文本消息主链路 | 会话列表、聊天页、文本消息发送、未读数、重发 |
| 阶段 3 | 第 7-8 周 | 同步、弱网与任务队列 | 增量同步、去重、pending job、断网恢复、ack 补偿 |
| 阶段 4 | 第 9-10 周 | 图片与语音媒体能力 | 图片消息、语音消息、媒体落盘、上传下载、进度 |
| 阶段 5 | 第 11-12 周 | 搜索、通知、安全 | 基础搜索、本地通知、角标、Keychain、数据库加密、日志脱敏 |
| 阶段 6 | 第 13 周 | 稳定性与性能优化 | 大数据量压测、滚动性能、数据库事务优化、崩溃恢复 |
| 阶段 7 | 第 14 周 | 验收与发布准备 | 单元测试、UI 测试、回归测试、MVP 验收报告 |

---

## 2. Sprint 任务表

状态说明：`已完成` 表示当前仓库已有实现和基础验证；`部分完成` 表示主链路已落地但仍有明确缺口；`待联调` 表示本地/Mock 链路已通但依赖服务端或系统能力验证；`下一步` 表示当前应优先推进；`待开始` 表示尚未进入实现。

> 当前做到：MVP 验收报告已输出，进入服务端联调与 iOS 15+ 设备矩阵补测阶段。

### Sprint 0：工程基线与开发规范

| 状态 | 周期 | 任务 | 技术要求 | 验收标准 | 负责人 |
|---|---|---|---|---|---|
| 已完成 | 第 1 周 | 统一 Xcode 配置 | `SWIFT_VERSION = 6.0`、`SWIFT_STRICT_CONCURRENCY = complete`、`IPHONEOS_DEPLOYMENT_TARGET = 15.0` | App、Tests、UITests 编译通过 | iOS |
| 部分完成 | 第 1 周 | 建立 MVVM 模板 | `ViewController/View + ViewModel + ViewState + Coordinator` | 新页面可按模板创建 | iOS |
| 部分完成 | 第 1 周 | 建立模块目录 | Core、Store、Sync、Media、Search、Security、UI | 目录结构清晰，依赖方向明确 | iOS |
| 已完成 | 第 1 周 | 定义基础类型 | ID、时间戳、错误类型、状态枚举满足 `Sendable` | 严格并发检查无警告 | iOS |
| 部分完成 | 第 1 周 | 建立测试基线 | 单元测试、UI 测试、Mock Service | CI/本地测试可运行 | iOS/QA |

### Sprint 1：账号、存储与数据库骨架

| 状态 | 周期 | 任务 | 技术要求 | 验收标准 | 负责人 |
|---|---|---|---|---|---|
| 已完成 | 第 2 周 | 账号密码登录（本地模拟） | 基于 App Bundle `mock_accounts.json` 读取账号文件，账号/手机号 + 密码校验，`UserDefaults` 缓存登录态 | 首次启动展示登录页，登录成功进入会话列表，再次启动可恢复登录态 | iOS |
| 已完成 | 第 2 周 | 退出登录、账号切换与本地数据删除 | 会话列表账号入口，清除登录态后回到登录页，重新登录其他账号重建依赖容器；删除本地数据需二次确认并清理当前账号数据库、搜索库、媒体目录、缓存和账号绑定密钥 | 退出登录后不展示原账号数据；切换账号后进入新账号会话列表且不串目录；删除当前账号本地数据后回到登录页，重新登录会重建干净账号存储 | iOS |
| 已完成 | 第 2 周 | 账号目录隔离 | `account_xxx/main.db/search.db/file_index.db/media/cache` | 切换账号不串数据 | iOS |
| 已完成 | 第 2 周 | Keychain 密钥管理 | 密钥与账号绑定，不硬编码 | 登录后可读取当前账号密钥 | iOS |
| 已完成 | 第 2 周 | DatabaseActor | actor 串行化连接、迁移、事务 | 数据库访问不在主线程 | iOS |
| 已完成 | 第 2 周 | migration_meta | 记录 schema 版本、迁移 ID、检查时间 | 重启后版本可追踪 | iOS |
| 已完成 | 第 3 周 | 核心表建表 | user、contact、conversation、message、content tables | 建表和索引完成 | iOS |
| 已完成 | 第 3 周 | Repository/DAO | UI 不直接访问数据库 | 单元测试覆盖基础 CRUD | iOS |
| 已完成 | 第 3 周 | 事务封装 | 消息、内容、会话摘要、未读数同事务 | 模拟异常时不产生半写入 | iOS |

### Sprint 2：会话列表与聊天页

| 状态 | 周期 | 任务 | 技术要求 | 验收标准 | 负责人 |
|---|---|---|---|---|---|
| 已完成 | 第 4 周 | 会话列表 MVVM | Combine 输出 row state，Diffable 增量刷新 | 首屏可展示会话 | iOS |
| 已完成 | 第 4 周 | 会话排序 | 置顶优先，`sort_ts` 倒序 | 新消息会话移动到顶部 | iOS |
| 已完成 | 第 4 周 | 未读数 | 本地准确累加、清零；进入会话后会话未读数与 incoming 消息 read_status 同事务置已读 | 进入会话后列表未读数清零，消息级未读状态不残留 | iOS |
| 已完成 | 第 5 周 | 聊天页 MVVM | 游标分页，UI 状态只在 MainActor 更新 | 首屏消息小于 300ms | iOS |
| 已完成 | 第 5 周 | 文本消息入库 | message + message_text + conversation 同事务 | 发送后立即展示 sending | iOS |
| 部分完成 | 第 5 周 | 文本消息发送 | `async/await` 请求服务端，ack 回写；服务端适配层、DTO 映射、baseURL/token provider、`TokenRefreshActor` 与 401 自动刷新一次重放已就绪，真实 endpoint 待接入 | 本地/适配层 success/failed 状态正确；真实接口联调后补齐端到端验收 | iOS/Server |
| 部分完成 | 第 6 周 | 消息重发 | 基于 `client_msg_id` 幂等；服务端适配层失败映射可进入 pending_job 并复用原 client message ID 重发 | 本地/适配层重发不重复插入；真实接口联调后验证服务端幂等 | iOS/Server |
| 待联调 | 第 6 周 | 撤回与删除 | 本地长按菜单、二次确认、逻辑删除和撤回替代文案已闭环；真实服务端撤回/删除接口待联调 | 本地 UI 可展示撤回/删除状态；服务端联调后补齐多端一致性验证 | iOS/Server |
| 已完成 | 第 6 周 | 草稿 | 离开保存，回来恢复 | 重启后草稿仍存在 | iOS |
| 已完成 | 第 6 周 | 群聊 P1 本地体验闭环 | 群成员角色、群公告、本地 @ 成员/@所有人、会话列表 @ 提示；基于 `conversation_member` 与 `conversation.extra_json`，真实群管理服务端接口不在本轮范围 | `group_core` demo 群可查看/编辑公告、选择 @ 成员并写入 mention 元数据；incoming @ 与 @所有人 可触发列表提示，进入会话标记已读后清除 | iOS |

### Sprint 3：同步、弱网与任务队列

| 状态 | 周期 | 任务 | 技术要求 | 验收标准 | 负责人 |
|---|---|---|---|---|---|
| 已完成 | 第 7 周 | SyncEngineActor | 管理 cursor、seq、补拉、去重 | 不出现并发乱序写入 | iOS |
| 已完成 | 第 7 周 | 增量同步 | `sync_checkpoint` + 批量事务 | 离线后上线可补齐消息 | iOS/Server |
| 已完成 | 第 7 周 | 消息去重 | `client_msg_id/server_msg_id/seq` | 重复推送不重复显示 | iOS/Server |
| 已完成 | 第 8 周 | pending_job | pending/running/success/failed/cancelled | App 重启后可恢复任务 | iOS |
| 已完成 | 第 8 周 | 弱网重试 | 超时、断网、ack 丢失、指数退避 | 弱网不丢消息 | iOS/QA |
| 已完成 | 第 8 周 | 网络状态桥接 | Combine 监听网络恢复，触发任务 | 恢复网络后自动重试 | iOS |

### Sprint 4：图片与语音消息

| 状态 | 周期 | 任务 | 技术要求 | 验收标准 | 负责人 |
|---|---|---|---|---|---|
| 已完成 | 第 9 周 | 图片选择与落盘 | PhotosUI/相册权限，账号目录隔离 | 本地缩略图立即显示 | iOS |
| 已完成 | 第 9 周 | 图片压缩与缩略图 | MediaFileActor 异步处理 | 大图不阻塞 UI | iOS |
| 部分完成 | 第 9 周 | 图片上传 | 上传进度 Combine 发布；上传完成后的图片消息发送服务端适配层已就绪 | 失败可重试；真实上传 endpoint 与端到端联调待验证 | iOS/Server |
| 部分完成 | 第 9-10 周 | 视频消息发送与展示 | 视频选择、缩略图、上传、重试、播放入口；上传完成后的视频消息发送服务端适配层已就绪 | 本地/Mock 视频消息可发送、失败可重试、聊天页可识别播放；真实上传 endpoint 与端到端联调待验证 | iOS/Server |
| 已完成 | 第 10 周 | 语音录制 | AVFoundation，权限降级 | 可录制、取消、发送 | iOS |
| 已完成 | 第 10 周 | 语音播放 | 播放状态、未读红点 | 播放后状态更新 | iOS |
| 已完成 | 第 10 周 | 媒体索引 | `media_resource/file_index.db` | 文件丢失可识别并触发下载 | iOS |

### Sprint 5：搜索、通知与安全

| 状态 | 周期 | 任务 | 技术要求 | 验收标准 | 负责人 |
|---|---|---|---|---|---|
| 已完成 | 第 11 周 | 基础搜索 | 搜索库独立，输入 Combine 防抖 | 可搜索联系人、会话、文本消息 | iOS |
| 已完成 | 第 11 周 | 搜索索引任务 | 异步索引，不阻塞消息主链路 | 索引失败不影响聊天 | iOS |
| 已完成 | 第 11 周 | 索引重建 | SearchIndexActor 支持全量重建 | 删除索引后可恢复 | iOS |
| 已完成 | 第 12 周 | 本地通知 | 免打扰不弹通知 | 前后台通知行为正确 | iOS |
| 已完成 | 第 12 周 | 角标管理 | 未读数统一计算 | 多会话未读角标准确 | iOS |
| 已完成 | 第 12 周 | 安全加固 | 本地安全基线完成；SQLCipher 整库加密已接入 | 不打印 token、消息明文、密钥；账号文件启用保护 | iOS |

### Sprint 6：性能、稳定性与数据修复

| 状态 | 周期 | 任务 | 技术要求 | 验收标准 | 负责人 |
|---|---|---|---|---|---|
| 已完成 | 第 13 周 | 会话列表性能 | 1000 会话，首屏小于 500ms | 滚动 60 FPS | iOS/QA |
| 已完成 | 第 13 周 | 聊天页性能 | 10 万消息，游标分页 | 上拉加载小于 300ms | iOS/QA |
| 已完成 | 第 13 周 | 崩溃恢复 | 发送中消息恢复为 pending/failed | 重启后消息不丢 | iOS/QA |
| 已完成 | 第 13 周 | 数据修复 | integrity check、FTS 重建、媒体索引重建 | 修复失败不影响 App 启动 | iOS |

### Sprint 7：验收与发布准备

| 状态 | 周期 | 任务 | 技术要求 | 验收标准 | 负责人 |
|---|---|---|---|---|---|
| 已完成 | 第 14 周 | 单元测试补齐 | ViewModel、Repository、Sync、PendingJob | 核心链路覆盖完成 | iOS/QA |
| 已完成 | 第 14 周 | UI 测试补齐 | 登录、会话、发送、重发、搜索 | 关键路径自动化通过 | iOS/QA |
| 已完成 | 第 14 周 | 回归测试 | iOS 15+ 机型和模拟器覆盖 | 无 P0/P1 阻塞问题 | QA |
| 已完成 | 第 14 周 | MVP 验收报告 | 功能、性能、稳定性、安全项 | 已输出 `ChatBridge_MVP_Acceptance_Report.md`；本地 Mock/MVP 可进入内测，真实生产发布仍依赖服务端联调与 iOS 15+ 设备矩阵补测 | PM/iOS/QA |

> 回归记录：当前环境已完成 iOS 26.4.1 Simulator 回归；iOS 15 真机/旧系统矩阵待 QA 设备补跑。  
> 本轮验证（2026-05-09）：撤回/删除 UI 已接入长按菜单后的二次确认，并补充 ViewModel 单元测试与 UI 回归用例；`AppleIMTests/AppleIMTests/chatViewModelDeleteRemovesMessageRow`、`chatViewModelRevokeReloadsRevokedMessageRow`、`chatViewModelDeleteFailureKeepsRowsAndReportsFailure`、`chatViewModelRevokeFailureKeepsRowsAndReportsFailure` 在 iPhone 17 Simulator 通过；`AppleIMUITests/AppleIMUITests/testMessageCanBeRevokedAfterConfirmation`、`testMessageCanBeDeletedAfterConfirmation`、`testCancellingMessageActionKeepsMessageVisible` 在 iPhone 17 Simulator 通过。  
> 进度更新（2026-05-09）：已输出 `ChatBridge_MVP_Acceptance_Report.md`，完成第一阶段 MVP 功能、性能、稳定性、安全项验收归档；`xcodebuild -list -project AppleIM.xcodeproj` 已确认存在共享 scheme `AppleIM`，`xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing` 通过并输出 `TEST BUILD SUCCEEDED`。完整 `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17' test` 在启动 `AppleIMUITests.xctrunner` 阶段遇到 Simulator/LLDB 环境异常，最终 `BUILD INTERRUPTED`，需重启 CoreSimulator/Xcode 后补跑。后续剩余风险集中在服务端文本 ack、重发、图片/视频上传、撤回/删除多端一致性联调，以及 iOS 15 真机/旧系统矩阵补测。
> 进度更新（2026-05-09）：收口未读数本地链路，`markConversationRead` 现在在同一事务中清零 conversation.unread_count 并将会话内 incoming unread message.read_status 置为 read，避免进入聊天后消息级未读状态残留；新增 `AppleIMTests/AppleIMTests/localChatRepositoryMarksIncomingMessagesReadWhenConversationIsRead` 覆盖该行为。`xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests` 已通过。
> 进度更新（2026-05-09）：文本消息服务端适配层已就绪，新增 `ChatBridgeHTTPClient` 与 `ServerMessageSendService`，支持 baseURL、超时、Bearer token、文本发送 DTO、ack 映射、离线/超时/ack 缺失失败分类；`AppDependencyContainer` 默认仍使用 Mock，只有显式配置 `CHATBRIDGE_SERVER_BASE_URL` 且当前登录态存在 token 时启用服务端适配层，UI 测试继续强制使用 Mock/fail-first。新增 `serverMessageSendServiceMapsTextAckToSendResult`、`serverMessageSendServiceMapsTransportFailuresToSendFailures`、`chatUseCasePersistsServerAckFromServerMessageSendService`、`chatUseCaseQueuesPendingJobForServerAckFailureAndResendsWithSameClientMessageID`、`serverMessageSendConfigurationRequiresExplicitBaseURL`、`uiTestMessageSendConfigurationKeepsUsingMockService` 覆盖发送 ack、失败入队、重发幂等和测试配置隔离；`xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing`、`xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests`、`xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMUITests/AppleIMUITests/testFailedSendCanBeRetried` 均已通过。真实服务端 endpoint 字段与联调验收仍待 Server 接口确认。
> 进度更新（2026-05-09）：新增独立 `TokenRefreshActor` 与 async token provider 注入，支持当前 token 读取、刷新成功后更新 `AccountSessionStore`、并发刷新合并为单次请求；`SceneDelegate` 在真实服务端配置存在时为 `ServerMessageSendService` 注入 actor provider，UI 测试路径仍优先使用 Mock/fail-first。新增 `tokenRefreshActorReturnsCachedTokenAndPersistsRefresh`、`tokenRefreshActorCoalescesConcurrentRefreshes`、`serverMessageSendConfigurationUsesTokenProviderActor` 覆盖缓存、持久化、并发合并与 provider 注入。真实 token refresh endpoint 字段仍待接口确认后联调。
> 进度更新（2026-05-09）：401 自动刷新与一次请求重放已接入文本发送网络边界，新增 `TokenRefreshingHTTPClient` 包装 `ChatBridgeHTTPPosting`，仅在 `unacceptableStatus(401)` 时调用 `authTokenRefresher`，刷新成功后重放原请求一次；刷新失败、非 401、二次失败继续沿用现有失败入队与重试链路。新增 `tokenRefreshingHTTPClientRefreshesAfterUnauthorizedAndRetriesWithUpdatedToken`、`tokenRefreshingHTTPClientDoesNotRefreshNonUnauthorizedFailures`、`chatUseCaseQueuesPendingJobWhenUnauthorizedRefreshFails` 覆盖 401 刷新重放、非 401 不刷新、刷新失败入队。
> 进度更新（2026-05-09）：媒体消息服务端发送适配层已按分类型接口接入，新增 `/v1/messages/image`、`/v1/messages/voice`、`/v1/messages/video`、`/v1/messages/file` 请求 DTO，上传完成后携带 `media_id`、`cdn_url`、`md5` 与图片/语音/视频/文件元数据换取统一 ack，并复用现有 401 token refresh 一次重放、失败分类和 pending job 重试链路。新增 `serverMessageSendServiceMapsImageAckToSendResult`、`serverMessageSendServiceMapsVoiceVideoAndFileRequests`、`serverMessageSendServiceMapsMediaTransportFailuresToSendFailures`、`tokenRefreshingHTTPClientRefreshesMediaSendAfterUnauthorized`、`chatUseCasePersistsServerAckForImageAndVideoSends`、`chatUseCaseQueuesMediaUploadJobWhenServerMediaSendFailsAfterUpload` 覆盖媒体请求映射、ack 持久化、刷新重放、发送失败后保留 upload ack 并入队。真实媒体上传 endpoint、上传进度与端到端联调仍待 Server 接口确认。
> 进度更新（2026-05-09）：群聊 P1 本地体验闭环已接入，新增 `GroupMember`、`GroupMemberRole`、`GroupAnnouncement`，复用 `conversation_member` 存储角色并用 `conversation.extra_json` 保存群公告与未读 @ 提示；聊天页支持群公告入口、管理员公告编辑、输入 `@` 展示成员选择、管理员/群主 `@所有人`，文本发送会写入 `mentions_json` 与 `at_all`；incoming @ 当前用户或 @所有人 会让会话列表 subtitle 前展示 `[有人@我]`，进入会话标记已读后清除。`xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing`、`xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests`、`xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMUITests/AppleIMUITests/testGroupChatAnnouncementAndMentionPicker` 均已通过。真实创建群、邀请、移除、退出、解散、群主转让和服务端群管理接口仍在范围外。

---

## 3. 功能优先级

### P0 必做

| 模块 | 需求 |
|---|---|
| 工程 | iOS 15+、Swift 6、严格并发检查、MVVM |
| 账号 | 登录态、账号目录隔离、Keychain 密钥 |
| 数据库 | 核心表、索引、迁移、事务、加密 |
| 会话 | 会话列表、排序、未读数、置顶、免打扰、草稿 |
| 消息 | 文本、图片、语音、重发、撤回、删除 |
| 同步 | 增量同步、断网恢复、去重、pending job |
| 安全 | 日志脱敏、媒体隔离、数据库密钥保护 |
| 测试 | 单元测试、UI 测试、弱网和崩溃恢复测试 |

### P1 应做

| 模块 | 需求 |
|---|---|
| 搜索 | 会话内搜索、全局基础搜索、索引重建 |
| 通知 | 本地通知、角标、免打扰通知策略 |
| 媒体 | 视频消息、文件消息基础收发 |
| 群聊 | 群成员角色、@ 用户、群公告基础 |
| 性能 | 大数据量压测、滚动优化、批量写入优化 |

### P2 可延后

| 模块 | 需求 |
|---|---|
| 收藏 | 收藏内容、收藏列表、收藏标签 |
| 表情 | 表情包、收藏表情、最近使用 |
| 高级消息 | 消息置顶、消息翻译、消息编辑历史 |
| 多端 | 设备管理、复杂同步冲突处理 |
| 修复 UI | 数据库修复进度页、用户可见修复入口 |

---

## 4. 关键里程碑

| 时间点 | 里程碑 | 验收口径 |
|---|---|---|
| 第 1 周末 | 工程基线完成 | Swift 6 严格并发编译通过，MVVM 模板可用 |
| 第 3 周末 | 本地存储完成 | 账号隔离、核心表、事务、迁移可用 |
| 第 6 周末 | 消息主链路完成 | 文本消息可发送、失败可重发、会话未读准确 |
| 第 8 周末 | 弱网同步完成 | 断网、重连、重复消息、ack 丢失可处理 |
| 第 10 周末 | 媒体消息完成 | 图片和语音可发送、上传失败可恢复 |
| 第 12 周末 | 搜索通知安全完成 | 搜索、通知、角标、加密、日志脱敏可验收 |
| 第 13 周末 | 性能稳定性完成 | 大数据量、崩溃恢复、数据库修复验证完成 |
| 第 14 周末 | MVP 验收完成 | 无 P0/P1 阻塞问题，可进入内测 |

---

## 5. 依赖与风险

| 风险 | 影响 | 应对 |
|---|---|---|
| 服务端接口延期 | 消息发送、同步、媒体上传无法完整联调 | 先实现 Mock Service 和本地回环模式 |
| 数据库方案未定 | Store 层返工风险 | 先封装 Repository/DAO 协议，隔离 WCDB/GRDB/SQLite 细节 |
| Swift 6 并发警告积累 | 后期修复成本高 | 每个 Sprint 必须保持严格并发零警告 |
| iOS 15 API 兼容 | 新 API 无降级导致低版本崩溃 | Code Review 必查 `#available` 和降级路径 |
| 媒体链路复杂 | 上传、缓存、索引、重试容易互相影响 | 媒体任务全部进入 pending_job，状态机单独测试 |
| 搜索索引阻塞主链路 | 消息收发卡顿 | 搜索索引异步化，支持失败后补建 |

---

## 6. 每周交付要求

- 每周至少完成一次 iOS Simulator 构建验证。
- 每周合并前必须保证 Swift 6 严格并发检查无新增警告。
- 每周补齐对应模块单元测试。
- 每周输出当前 Sprint 完成项、延期项、风险项。
- 涉及 UI 的任务必须提供 iOS 15+ 兼容验证。
- 涉及数据库的任务必须附带迁移和回滚验证说明。
- 涉及消息链路的任务必须覆盖弱网、重试和去重场景。
