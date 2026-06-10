# AppleIM 架构修复任务清单

## 1. 基线与规格

目标：建立第二轮 Kiro 修复规格，确认当前工作区。

修改范围：

- `.kiro/specs/appleim-architecture-repair/requirements.md`
- `.kiro/specs/appleim-architecture-repair/design.md`
- `.kiro/specs/appleim-architecture-repair/tasks.md`

命令：

```sh
git status --short
xcodebuild -quiet -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

完成标准：规格存在，构建通过或记录环境阻塞。

## 2. 架构边界测试

目标：先用失败测试固定禁止回退的边界。

修改范围：

- `AppleIMTests/App/ArchitectureBoundaryTests.swift`

测试命令：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests/productionFeatureAndAppLayersDoNotRequestWholeRepository -only-testing:AppleIMTests/AppleIMTests/chatViewModelDoesNotExposeUseCaseInitializer
```

完成标准：测试先失败，指向 `AppDependencyContainer`、`ChatViewModel` 等当前违规点。

## 3. Chat 主链路迁移

目标：App 装配直接构造窄服务依赖，不再通过 `ChatUseCase` initializer。

修改范围：

- `AppleIM/Features/Chat/UseCases/ChatServices.swift`
- `AppleIM/Features/Chat/ViewModels/ChatViewModel.swift`
- `AppleIM/App/AppDependencyContainer.swift`
- `AppleIMTests/Chat/ChatViewModelTests.swift`

测试命令：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/Chat
```

完成标准：Chat 测试通过；生产装配不再调用 `ChatViewModel(useCase:)`。

## 4. Store 上层入口迁移

目标：生产 feature/App 层不再调用 `storeProvider.repository()`。

修改范围：

- `AppleIM/Store/ChatStoreProvider.swift`
- `AppleIM/Store/AccountChatStore.swift`
- `AppleIM/App/AppDependencyContainer.swift`
- `AppleIM/App/AppLifecycleService.swift`
- `AppleIM/Network/NetworkRecoveryCoordinator.swift`
- `AppleIM/Features/ConversationList/Coordinators/ConversationUnreadBadgeController.swift`
- `AppleIM/Sync/SimulatedIncomingPushService.swift`

测试命令：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/Store -only-testing:AppleIMTests/Sync -only-testing:AppleIMTests/SearchContactsCatalog
```

完成标准：生产上层通过 `accountStore()` 获取窄能力；架构边界测试通过。

## 5. 全量测试隔离修复

目标：修复 `AppleIMTests` 全量组合运行中 demo fixture、搜索 repair、Store 观察相关不稳定。

修改范围：

- `AppleIMTests/TestSupport/TestDataFactories.swift`
- `AppleIMTests/SearchContactsCatalog/SearchContactsCatalogTests.swift`
- `AppleIMTests/Store/StoreMediaAndRepairTests.swift`

测试命令：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests/bundleDemoDataCatalogReadsAccountDataFromJSON -only-testing:AppleIMTests/AppleIMTests/searchIndexFailureCreatesRepairPendingJob -only-testing:AppleIMTests/AppleIMTests/localChatRepositoryObservesLatestMessages
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests
```

完成标准：代表性失败测试单独通过，全量 `AppleIMTests` 通过。

## 6. 最终验证

目标：确认构建、单元测试、关键 UI 路径和 diff 检查。

命令：

```sh
git diff --check
xcodebuild -quiet -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMUITests/AppleIMUITests/testOpenConversationAndSendTextMessage -only-testing:AppleIMUITests/AppleIMUITests/testFailedSendCanBeRetried -only-testing:AppleIMUITests/AppleIMUITests/testGroupChatAnnouncementAndMentionPicker
```

完成标准：全部通过；如模拟器环境阻塞，记录失败命令、失败原因和剩余风险。
