# ChatBridge MVP 验收报告

> 日期：2026-05-09；稳定回归更新：2026-05-11
> 范围：第一阶段 MVP，本地 Mock 链路与 iOS Simulator 回归  
> 依据：`ChatBridge_Apple_IM_Requirements.md`、`ChatBridge_Technical_Development_Requirements.md`、`ChatBridge_Development_Task_Schedule.md`

## 1. 验收结论

ChatBridge 第一阶段 MVP 的本地 Mock 链路已具备进入内测的基础条件：账号登录、会话列表、聊天页、文本/图片/语音消息、本地撤回/删除、草稿、搜索、通知、同步、账号隔离、数据库加密与媒体索引均已完成本地闭环或基础验证。

真实生产发布仍依赖服务端联调和设备矩阵补测：文本消息 ack、消息重发、图片/视频上传、撤回/删除多端一致性需要在真实接口完成后补充端到端验收；当前本机无 iOS 15.x runtime 或可用 iOS 15 真机，iOS 15 真机和旧系统矩阵仍需 QA 补跑。2026-05-11 已完成本机稳定回归复测，历史 11 个单元测试超时不再复现，`AppleIMTests` 全量通过。

## 2. 功能验收

| 模块 | 状态 | 验收说明 |
|---|---|---|
| 账号登录 | 已通过 | 支持账号/手机号 + 密码本地模拟登录，登录态可恢复。 |
| 账号切换与本地数据删除 | 已通过 | 支持退出登录、切换账号、二次确认删除当前账号本地数据。 |
| 账号目录隔离 | 已通过 | 数据库、搜索库、媒体目录、缓存按账号隔离。 |
| Keychain 与数据库密钥 | 已通过 | 密钥与账号绑定，SQLCipher 整库加密已接入。 |
| 会话列表 | 已通过 | 支持 MVVM 状态输出、Diffable 刷新、置顶排序、摘要更新。 |
| 未读数 | 部分通过 | 本地累加与进入会话清零已落地，真实多端未读同步仍待服务端联调。 |
| 聊天页 | 已通过 | 支持消息分页、输入栏、状态渲染和主链路 UI 状态更新。 |
| 文本消息 | 部分通过 | 本地入库与 sending 状态已完成；服务端发送适配层、DTO 映射、ack 回写、失败分类、token refresh actor 与 401 自动刷新一次重放已就绪，真实 endpoint 待接入后补充端到端验收。 |
| 消息重发 | 部分通过 | 本地幂等模型和 pending job 基础已具备；服务端适配层失败可入队并复用原 `client_msg_id` 重发，真实接口幂等仍待联调验证。 |
| 消息撤回/删除 | 待联调 | 本地长按菜单、二次确认、逻辑删除、撤回替代文案已闭环；多端一致性待联调。 |
| 草稿 | 已通过 | 离开保存、返回恢复、重启恢复已纳入当前进度。 |
| 图片消息 | 部分通过 | 图片选择、压缩、缩略图和本地落盘已完成；上传完成后的图片消息服务端发送 ack 适配已就绪；真实上传进度与端到端联调待验证。 |
| 语音消息 | 已通过 | 支持录制、取消、发送、播放状态与未读红点。 |
| 视频消息 | 部分通过 | 本地/Mock 发送、缩略图、播放入口已具备；上传完成后的视频消息服务端发送 ack 适配已就绪；真实上传与端到端联调待验证。 |
| 同步与弱网 | 已通过 | SyncEngineActor、checkpoint、去重、pending job、网络恢复重试已完成本地验证。 |
| 搜索 | 已通过 | 支持联系人、会话、文本消息基础搜索和索引重建。 |
| 通知与角标 | 已通过 | 本地通知、免打扰策略和未读角标管理已完成。 |
| 存储安全 | 已通过 | 账号文件保护、日志脱敏、数据库加密、媒体隔离均纳入实现范围。 |

## 3. 性能与稳定性

| 项目 | 状态 | 验收说明 |
|---|---|---|
| 会话列表性能 | 已通过 | 1000 会话首屏目标小于 500ms，滚动 60 FPS 的回归项已标记完成。 |
| 聊天页性能 | 已通过 | 10 万消息游标分页，上拉加载目标小于 300ms 的回归项已标记完成。 |
| 崩溃恢复 | 已通过 | 发送中消息重启后恢复为 pending/failed，消息不丢失。 |
| 弱网恢复 | 已通过 | 超时、断网、ack 丢失、指数退避和网络恢复触发任务已覆盖。 |
| 数据修复 | 已通过 | integrity check、FTS 重建、媒体索引重建已完成，修复失败不阻断 App 启动。 |

## 4. 测试证据

当前进度表记录的 2026-05-09 回归证据如下：

- Swift Testing：`AppleIMTests/AppleIMTests/chatViewModelDeleteRemovesMessageRow`
- Swift Testing：`AppleIMTests/AppleIMTests/chatViewModelRevokeReloadsRevokedMessageRow`
- Swift Testing：`AppleIMTests/AppleIMTests/chatViewModelDeleteFailureKeepsRowsAndReportsFailure`
- Swift Testing：`AppleIMTests/AppleIMTests/chatViewModelRevokeFailureKeepsRowsAndReportsFailure`
- XCTest UI：`AppleIMUITests/AppleIMUITests/testMessageCanBeRevokedAfterConfirmation`
- XCTest UI：`AppleIMUITests/AppleIMUITests/testMessageCanBeDeletedAfterConfirmation`
- XCTest UI：`AppleIMUITests/AppleIMUITests/testCancellingMessageActionKeepsMessageVisible`
- Swift Testing：`AppleIMTests/AppleIMTests/serverMessageSendServiceMapsTextAckToSendResult`
- Swift Testing：`AppleIMTests/AppleIMTests/serverMessageSendServiceMapsTransportFailuresToSendFailures`
- Swift Testing：`AppleIMTests/AppleIMTests/chatUseCasePersistsServerAckFromServerMessageSendService`
- Swift Testing：`AppleIMTests/AppleIMTests/chatUseCaseQueuesPendingJobForServerAckFailureAndResendsWithSameClientMessageID`
- Swift Testing：`AppleIMTests/AppleIMTests/serverMessageSendConfigurationRequiresExplicitBaseURL`
- Swift Testing：`AppleIMTests/AppleIMTests/uiTestMessageSendConfigurationKeepsUsingMockService`
- Swift Testing：`AppleIMTests/AppleIMTests/serverMessageSendServiceMapsImageAckToSendResult`
- Swift Testing：`AppleIMTests/AppleIMTests/serverMessageSendServiceMapsVoiceVideoAndFileRequests`
- Swift Testing：`AppleIMTests/AppleIMTests/serverMessageSendServiceMapsMediaTransportFailuresToSendFailures`
- Swift Testing：`AppleIMTests/AppleIMTests/tokenRefreshingHTTPClientRefreshesMediaSendAfterUnauthorized`
- Swift Testing：`AppleIMTests/AppleIMTests/chatUseCasePersistsServerAckForImageAndVideoSends`
- Swift Testing：`AppleIMTests/AppleIMTests/chatUseCaseQueuesMediaUploadJobWhenServerMediaSendFailsAfterUpload`

本轮执行的验证命令与结果：

```sh
xcodebuild -list -project AppleIM.xcodeproj
```

结果：通过，确认存在共享 scheme `AppleIM`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

结果：通过，输出 `TEST BUILD SUCCEEDED`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test
```

结果：未完成。测试在启动 `AppleIMUITests.xctrunner` 阶段持续卡住并重复输出 `DebuggerLLDB.DebuggerVersionStore.StoreError`；中断后 Xcode 报告 `NSMachErrorDomain Code=-308 "(ipc/mig) server died"`、`DTServiceHubClient failed to bless service hub` 和 `BUILD INTERRUPTED`。该结果记录为当前 Xcode/Simulator 环境阻塞，不作为产品代码失败结论。

文本消息服务端适配层补充验证：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

结果：通过，输出 `TEST BUILD SUCCEEDED`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests
```

结果：通过，输出 `TEST SUCCEEDED`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMUITests/AppleIMUITests/testFailedSendCanBeRetried
```

结果：通过，输出 `TEST SUCCEEDED`。执行期间仍出现一次 `DebuggerLLDB.DebuggerVersionStore.StoreError` 提示，但未阻塞测试完成。

Token refresh actor 补充验证：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests/tokenRefreshActorReturnsCachedTokenAndPersistsRefresh -only-testing:AppleIMTests/AppleIMTests/tokenRefreshActorCoalescesConcurrentRefreshes -only-testing:AppleIMTests/AppleIMTests/serverMessageSendConfigurationUsesTokenProviderActor
```

结果：通过，输出 `TEST SUCCEEDED`。

401 自动刷新与请求重放补充验证：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests/tokenRefreshingHTTPClientRefreshesAfterUnauthorizedAndRetriesWithUpdatedToken -only-testing:AppleIMTests/AppleIMTests/tokenRefreshingHTTPClientDoesNotRefreshNonUnauthorizedFailures -only-testing:AppleIMTests/AppleIMTests/chatUseCaseQueuesPendingJobWhenUnauthorizedRefreshFails
```

结果：通过，输出 `TEST SUCCEEDED`。

媒体消息服务端发送适配层补充验证：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests/serverMessageSendServiceMapsImageAckToSendResult -only-testing:AppleIMTests/AppleIMTests/serverMessageSendServiceMapsVoiceVideoAndFileRequests -only-testing:AppleIMTests/AppleIMTests/serverMessageSendServiceMapsMediaTransportFailuresToSendFailures -only-testing:AppleIMTests/AppleIMTests/tokenRefreshingHTTPClientRefreshesMediaSendAfterUnauthorized -only-testing:AppleIMTests/AppleIMTests/chatUseCasePersistsServerAckForImageAndVideoSends -only-testing:AppleIMTests/AppleIMTests/chatUseCaseQueuesMediaUploadJobWhenServerMediaSendFailsAfterUpload
```

结果：通过，输出 `TEST SUCCEEDED`。

iOS 15 补测摸底与 iOS 26.4.1 对照验证：

```sh
xcrun simctl list devices available
```

结果：沙箱内失败，错误集中在 CoreSimulatorService connection invalid 和 CoreSimulator 日志权限；提权后通过，确认仅存在 iOS 26.4 Simulator runtime，无 iOS 15.x runtime。

```sh
xcrun xctrace list devices
```

结果：提权后通过，可见真机为 iOS 17.6.1、18.7.x、26.x 且处于离线/不可用状态，无 iOS 15.x 可测设备。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -showdestinations
```

结果：通过，可见 iOS 26.4.1 Simulator 目标与多台真机占位；未提供可用 iOS 15 目标。

```sh
rg -n "IPHONEOS_DEPLOYMENT_TARGET|SWIFT_VERSION|SWIFT_STRICT_CONCURRENCY|TARGETED_DEVICE_FAMILY" AppleIM.xcodeproj/project.pbxproj
```

结果：通过，确认各 target 仍配置 `IPHONEOS_DEPLOYMENT_TARGET = 15.0`、`SWIFT_VERSION = 6.0`、`SWIFT_STRICT_CONCURRENCY = complete`，App target 保持 iPhone/iPad。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

结果：通过，输出 `TEST BUILD SUCCEEDED`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests
```

结果：失败，iPhone 17 / iOS 26.4.1 Simulator 上 170 passed / 11 failed；失败均为 `Issue recorded: Timed out waiting for condition`。失败用例：

- `AppleIMTests/AppleIMTests/chatViewModelAppendsImageRowAfterSendingImage`
- `AppleIMTests/AppleIMTests/chatViewModelCanLoadOlderMessagesAfterPaginationFailure`
- `AppleIMTests/AppleIMTests/chatViewModelLoadsGroupAnnouncementAndMentionOptions`
- `AppleIMTests/AppleIMTests/chatViewModelPaginationFailureKeepsCurrentRows`
- `AppleIMTests/AppleIMTests/chatViewModelPrependsOlderMessagesWithoutDuplicates`
- `AppleIMTests/AppleIMTests/chatViewModelSendsComposerImageThenText`
- `AppleIMTests/AppleIMTests/chatViewModelSendsComposerVideoOnly`
- `AppleIMTests/AppleIMTests/chatViewModelSendsSelectedMentionMetadata`
- `AppleIMTests/AppleIMTests/chatViewModelTracksOnlyActiveVoicePlaybackRow`
- `AppleIMTests/AppleIMTests/conversationListViewControllerReportsInitialLoadFinishedOnce`
- `AppleIMTests/AppleIMTests/conversationListViewModelRefreshesAfterPinAndMuteChanges`

2026-05-11 稳定回归复测与修复：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests/chatViewModelAppendsImageRowAfterSendingImage -only-testing:AppleIMTests/AppleIMTests/chatViewModelCanLoadOlderMessagesAfterPaginationFailure -only-testing:AppleIMTests/AppleIMTests/chatViewModelLoadsGroupAnnouncementAndMentionOptions -only-testing:AppleIMTests/AppleIMTests/chatViewModelPaginationFailureKeepsCurrentRows -only-testing:AppleIMTests/AppleIMTests/chatViewModelPrependsOlderMessagesWithoutDuplicates -only-testing:AppleIMTests/AppleIMTests/chatViewModelSendsComposerImageThenText -only-testing:AppleIMTests/AppleIMTests/chatViewModelSendsComposerVideoOnly -only-testing:AppleIMTests/AppleIMTests/chatViewModelSendsSelectedMentionMetadata -only-testing:AppleIMTests/AppleIMTests/chatViewModelTracksOnlyActiveVoicePlaybackRow -only-testing:AppleIMTests/AppleIMTests/conversationListViewControllerReportsInitialLoadFinishedOnce -only-testing:AppleIMTests/AppleIMTests/conversationListViewModelRefreshesAfterPinAndMuteChanges
```

结果：通过，输出 `TEST SUCCEEDED`，测试结果位于 `Test-AppleIM-2026.05.11_10-20-11-+0800.xcresult`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests
```

首轮结果：失败，182 个单元测试中 1 个失败，历史 11 个超时用例均已通过；失败项为 `conversationListCellPrepareForReuseClearsAvatarImage`，错误为复用后头像 `UIImageView` 仍保留旧图片且未隐藏。

修复说明：`ConversationListCell.prepareForReuse()` 现在递归重置 UIKit 包装层内的 `ConversationListCellContentView`，并清理旧 `contentConfiguration`，避免复用时保留上一条头像。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests/conversationListCellPrepareForReuseClearsAvatarImage
```

结果：通过，输出 `TEST SUCCEEDED`，测试结果位于 `Test-AppleIM-2026.05.11_10-18-47-+0800.xcresult`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests
```

修复后结果：通过，输出 `TEST SUCCEEDED`，测试结果位于 `Test-AppleIM-2026.05.11_10-21-03-+0800.xcresult`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

结果：通过，输出 `TEST BUILD SUCCEEDED`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMUITests/AppleIMUITests/testLoginAndSendMessage
```

结果：通过，输出 `TEST SUCCEEDED`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMUITests/AppleIMUITests/testFailedSendCanBeRetried
```

结果：通过，输出 `TEST SUCCEEDED`；执行期间出现一次 `DebuggerLLDB.DebuggerVersionStore.StoreError`，未阻塞测试完成。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMUITests/AppleIMUITests/testGroupChatAnnouncementAndMentionPicker
```

结果：通过，输出 `TEST SUCCEEDED`；执行期间出现一次 `DebuggerLLDB.DebuggerVersionStore.StoreError`，未阻塞测试完成。

## 5. 剩余风险

| 风险 | 当前影响 | 后续动作 |
|---|---|---|
| 服务端文本消息 ack 与 token refresh 未完成联调 | 客户端适配层已具备 ack 回写、失败入队、重发能力、token refresh actor 和 401 自动刷新一次重放，但真实 endpoint 尚未接入 | 接口就绪后补充端到端发送、失败、401 刷新、重试验收。 |
| 媒体消息发送 ack 已具备但未端到端联调 | 上传完成后的图片、语音、视频、文件消息发送 DTO、ack 回写、失败分类和 401 重放已具备；真实服务端字段仍需确认 | Server 接口就绪后用真实 endpoint 补跑媒体消息发送 ack、失败入队与重试验收。 |
| 图片与视频上传未完成联调 | 无法确认真实上传进度、CDN URL、上传失败恢复 | 用真实上传接口补跑媒体上传进度、失败重试和端到端发送测试。 |
| 撤回/删除多端一致性未验证 | 本地状态正确，但无法证明其他端同步一致 | 服务端撤回/删除事件接入后补齐多端同步回归。 |
| iOS 15 真机矩阵待补跑 | 本机无 iOS 15.x Simulator runtime 或可用 iOS 15 真机，低系统 API 兼容仍需设备级确认 | QA 使用 iOS 15+ 真机和旧系统模拟器补充回归。 |
| 生产推送链路待验证 | 本地通知已完成，真实 APNs 行为未覆盖 | 接入推送证书和服务端后补充前后台通知验收。 |

## 6. 发布判断

- 本地 Mock/MVP：可进入内测。
- 真实服务端联调版本：文本消息适配层已就绪，仍需完成真实 endpoint ack、重发幂等、媒体上传、撤回/删除同步验证后再进入灰度。
- 生产发布：需完成 iOS 15 真机/旧系统矩阵补跑，完成真实服务端联调，并确认无 P0/P1 阻塞问题。
