# AGENTS.md

本文件为自动化编码代理在本仓库工作的工程约定。适用范围为仓库根目录及全部子目录。

## Project Overview

- 工程名：`AppleIM`，产品方向为 `ChatBridge`。
- 技术栈：iOS UIKit 应用，按需可引入 SwiftUI；当前以 `ViewController + ViewModel + ViewState` 的 MVVM 结构为主。
- 最低系统版本：iOS 15.0，支持 iPhone 与 iPad。
- Swift：使用 Swift 6 语言模式，要求通过完整严格并发检查。
- 主要依赖：`SQLCipher.swift` Swift Package。
- 主要文档：
  - `ChatBridge_Technical_Development_Requirements.md`
  - `ChatBridge_Apple_IM_Requirements.md`
  - `ChatBridge_iOS_UI_Design_Spec.md`
  - `ChatBridge_Development_Task_Schedule.md`
  - `mobile_wechat_database_design_field_comments.md`

## Communication

- 必须始终使用中文回答。
- 所有代码解释、分析、注释必须使用中文。
- 除非用户明确要求，否则禁止使用英文。

## Repository Layout

- `AppleIM/`: App 源码。
- `AppleIM/App/`: 应用装配、依赖容器、UI 测试配置。
- `AppleIM/Features/`: 页面功能模块，目前包含登录、会话列表、聊天。
- `AppleIM/Core/`: 基础模型、标识符、日志。
- `AppleIM/Store/`: Repository、DAO、存储模型、本地种子数据。
- `AppleIM/Database/`: SQLite/SQLCipher actor、schema、迁移、修复。
- `AppleIM/Storage/`: 账号隔离的本地目录与文件保护。
- `AppleIM/Media/`: 语音、媒体文件、上传服务。
- `AppleIM/Search/`: 搜索模型、索引 actor、搜索用例。
- `AppleIM/Sync/`: 同步模型与同步引擎。
- `AppleIM/Security/`: 数据库密钥与 Keychain 相关能力。
- `AppleIMTests/`: Swift Testing 单元测试。
- `AppleIMUITests/`: XCTest UI 测试与启动辅助。

## Architecture Rules

- 遵循 MVVM：
  - View / ViewController 只负责布局、渲染、用户事件转发和导航触发。
  - ViewModel 负责 UI 状态组装、输入事件处理、调用 UseCase/Service，并通过 Combine 或明确 API 暴露状态。
  - ViewState 使用值类型表达界面状态。
  - UseCase / Service 编排业务流程。
  - Repository 聚合数据库、缓存、网络、文件与任务队列。
  - DAO / Store 处理 SQL 与单表或强相关表读写。
- UI 层不得直接访问数据库、Keychain、文件系统或底层网络 Client。
- ViewModel 不持有 `UIView`、`UIViewController`、`UITableView`、`UICollectionView` 等 UIKit 控件。
- App 级依赖通过 `AppDependencyContainer` 装配；新增功能优先用构造函数注入依赖，避免隐式单例。
- 导航应保持在 ViewController、Coordinator/Router 或依赖容器的装配层，不要散落到底层业务对象。

## Swift And Concurrency

- 新代码必须兼容 Swift 6 严格并发检查，不引入并发警告。
- UI 类型与 UI 状态修改保持在 `@MainActor`。
- 数据库、文件、搜索索引、媒体处理、同步和任务队列不得在主线程执行。
- 共享可变状态优先使用 `actor` 或主 actor 隔离。
- 跨并发边界的数据类型应显式满足 `Sendable`，必要时使用值类型建模。
- 避免用 `@unchecked Sendable` 规避设计问题；如必须使用，需要在代码附近说明线程安全依据。
- 使用 iOS 16+、17+、18+、26+ API 时必须加 `#available` 降级路径，不能破坏 iOS 15 兼容性。

## Data, Storage, And Security

- 本地数据按账号隔离，优先复用 `AccountStorageService`、`AccountStoragePaths`、`ChatStoreProvider`。
- SQL 访问集中在 `DatabaseActor`、DAO 和 Store 层，使用参数绑定，不拼接用户输入。
- 数据库错误、日志和 UI 错误文案不得泄漏完整路径、SQL、密钥、token、密码或消息明文。
- 敏感数据库、搜索库、媒体目录等路径需要保持文件保护策略。
- 数据库 schema、迁移、修复逻辑应保持幂等；更新 schema 时同步补充迁移和测试。
- 不要把真实账号、真实 token、真实密钥或用户隐私数据提交到仓库。

## UI Guidelines

- 当前 UI 以 UIKit 为主；新增页面应延续既有 `Features/<FeatureName>/` 目录结构。
- 复杂页面可逐步引入 SwiftUI，但避免 UIKit 和 SwiftUI 对同一状态双写。
- 复用 `ChatBridgeDesignSystem` 中的颜色、字体、间距和组件风格。
- `ChatInputBarView` 等复杂 UIKit 视图不要继续平铺堆叠同类 UI 属性；新增或调整一类视觉结构（如材质背景、输入胶囊、媒体预览、面板背景）时，应优先封装成专用子视图或设计系统组件，再由宿主视图组合使用。
- `ChatInputBarView` 的输入行、待发送预览、相册面板、表情面板应共享宿主视图内的同一个输入区材质背景；子面板和预览只作为透明内容层，不再各自新增大块背景。
- `ChatInputBarView` 内部同类控件应按职责收敛为私有子视图，例如附件预览轨道、文本输入胶囊、录音态胶囊、待发送语音预览胶囊；宿主视图只保留组合入口、输入模式状态和 action 转发。
- 交互控件应设置稳定的 accessibility identifier，尤其是登录、会话列表、聊天输入、账号操作等 UI 测试路径。
- 页面文案和错误信息应面向用户，调试细节放日志，不直接展示底层错误。

## Testing

- 单元测试使用 Swift Testing，文件位于 `AppleIMTests/`。
- UI 测试使用 XCTest，文件位于 `AppleIMUITests/`。
- 改动 ViewModel、UseCase、Repository、DAO、数据库迁移、账号隔离、搜索、同步、媒体或安全逻辑时，应添加或更新相关单元测试。
- 改动登录、会话列表、聊天发送、账号切换、删除本地数据等用户流程时，应考虑补充 UI 测试。
- UI 测试启动应复用 `makeUITestApplication(...)`，它会配置：
  - `--chatbridge-ui-testing`
  - `CHATBRIDGE_UI_TEST_RUN_ID`
  - `CHATBRIDGE_UI_TEST_SEND_MODE`
  - `CHATBRIDGE_UI_TEST_RESET_SESSION`

## Common Commands

优先使用共享 scheme `AppleIM`。

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test
```

如本机模拟器名称不同，先查询可用设备：

```sh
xcrun simctl list devices available
```

## Coding Style

- 保持文件内既有风格：本工程大量使用中文注释和 Swift 文档注释，新注释应简短且有实际解释价值。
- 优先小而清晰的类型和方法；不要为单次使用的简单逻辑过度抽象。
- 保持 async API 的取消语义；长任务应检查 `Task.isCancelled` 或处理 `CancellationError`。
- Combine 订阅、Task、闭包捕获要避免循环引用。
- 修改 Xcode 工程文件时保持最小 diff，不重排无关 sections。
- 新资源、测试 fixtures、mock 数据要放在对应模块附近，并确保 target membership 正确。

## Agent Workflow

- 开始改动前先检查 `git status --short`，不要覆盖用户未提交修改。
- 搜索文件和文本优先使用 `rg` / `rg --files`。
- 先阅读相邻实现和测试，再按现有模式改动。
- 对行为改动优先补测试，再实现。
- 完成后运行与改动范围匹配的最小验证；如果无法运行，说明原因和剩余风险。
- 不要执行破坏性 git 命令，不要回滚非本人改动，除非用户明确要求。
