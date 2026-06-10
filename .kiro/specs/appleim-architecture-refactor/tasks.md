# AppleIM 架构优化任务清单

## 1. 基线验证

目标：确认开始重构前工作区和构建状态。

修改范围：无源码修改。

命令：

```sh
git status --short
xcodebuild -quiet -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

完成标准：工作区只包含本规格文件变更，构建通过或记录环境阻塞。

## 2. Store 架构重组

目标：引入账号 Store 和模块 Store，迁移上层调用方远离全能 `LocalChatRepository`。

修改范围：

- `AppleIM/Store/ChatStoreModels.swift`
- `AppleIM/Store/LocalChatRepository.swift`
- `AppleIM/Store/ChatStoreProvider.swift`
- 新增 Store 模块文件
- Store、Database、Sync、Media、Search 测试

完成标准：

- 上层生产代码不再把 `LocalChatRepository` 作为全能依赖传递。
- 消息发送、同步入库、未读、pending job、媒体索引、表情测试通过。

## 3. Chat 服务拆分

目标：移除过宽 `ChatUseCase`，改为 Chat 窄服务组合注入。

修改范围：

- `AppleIM/Features/Chat/UseCases/`
- `AppleIM/Features/Chat/ViewModels/ChatViewModel.swift`
- `AppleIM/App/AppDependencyContainer.swift`
- `AppleIMTests/TestSupport/ChatUseCaseSpies.swift`
- `AppleIMTests/Chat/`

完成标准：

- `ChatViewModel` 使用 `Dependencies` 注入。
- 生产类型不再声明 `ChatUseCase`、`LocalChatUseCase`、`StoreBackedChatUseCase`。
- `AppleIMTests/Chat` 通过。

## 4. 其他模块服务化

目标：将会话列表、通讯录、搜索、登录统一到 Service 命名和边界。

修改范围：

- `AppleIM/Features/ConversationList/UseCases/ConversationListUseCase.swift`
- `AppleIM/Features/Contacts/UseCases/ContactListUseCase.swift`
- `AppleIM/Search/SearchUseCase.swift`
- `AppleIM/Features/Login/ViewModels/LoginViewModel.swift`
- 相关测试和测试替身

完成标准：

- 生产主类型使用 `Servicing` 命名。
- ViewModel 不直接持有多个底层业务对象。
- 相关单元测试通过。

## 5. App 装配收敛

目标：让 `SceneDelegate` 只保留场景和窗口职责。

修改范围：

- `AppleIM/SceneDelegate.swift`
- `AppleIM/App/AppDependencyContainer.swift`
- `AppleIM/App/MainInterfaceBuilder.swift`
- 新增 App 级协调/工厂服务
- `AppleIMTests/App/`

完成标准：

- 登录态、退出、切换账号、删除本地数据和主依赖创建可独立测试。
- UI 测试配置隔离行为保持不变。

## 6. 测试替身瘦身

目标：降低测试文件维护成本，避免测试替身实现无关协议方法。

修改范围：

- `AppleIMTests/TestSupport/`
- `AppleIMTests/Chat/`
- `AppleIMTests/ConversationList/`
- `AppleIMTests/SearchContactsCatalog/`

完成标准：

- Chat 测试替身按能力拆分。
- 无空实现的大而全 `ChatUseCase` spy。
- 相关测试通过。

## 7. 全量验证

目标：确认重构后功能、构建和并发基线稳定。

命令：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMUITests/AppleIMUITests/testLoginAndSendMessage
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMUITests/AppleIMUITests/testFailedSendCanBeRetried
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMUITests/AppleIMUITests/testGroupChatAnnouncementAndMentionPicker
git diff --check
xcodebuild -quiet -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

完成标准：全部命令通过；如模拟器或外部环境阻塞，记录具体命令、失败原因和剩余风险。
