# AppleIM 架构修复需求规格

## 目标

在上一轮架构优化基础上，继续收敛生产主链路的依赖边界：移除上层对全能 `LocalChatRepository` 和过宽 `ChatUseCase` 的依赖，修复全量单元测试组合运行不稳定问题，并用架构测试防止边界回退。

本轮不改变用户可见 UI 行为，不引入 SwiftUI 重写，不改变 iOS 15 兼容要求。

## 范围

- Store 上层入口从 `ChatStoreProvider.repository()` 迁移到 `AccountChatStore` 或具体窄 Store。
- Chat 页面主链路从 `ChatUseCase` 兼容入口迁移到 `ChatViewModel.Dependencies` 窄服务。
- App 装配层继续下沉账号会话、删除本地数据和依赖创建流程。
- 测试 fixture 和异步观察测试需要具备全量组合运行稳定性。
- 新增静态架构测试，禁止生产主链路继续依赖旧兼容入口。

## 需求

### R1 Store 暴露边界

作为 Store 层维护者，我希望生产上层模块不再通过 `ChatStoreProvider.repository()` 获取全能仓储，以便数据能力按账号 Store 和窄协议暴露。

验收标准：

- 生产功能模块不得调用 `storeProvider.repository()`。
- `ChatStoreProvider` 对生产上层优先暴露 `accountStore()`。
- `LocalChatRepository` 可以暂时作为 Store 内部实现保留，但不得作为页面、App 装配或 feature service 的直接依赖传递。
- 数据修复、演示数据初始化等 Store 内部流程可以通过专门 internal 入口获取底层能力。

### R2 Chat 窄服务主链路

作为聊天页维护者，我希望 `ChatViewModel` 的生产构造只接受窄服务依赖，以便每项能力可以独立测试和替换。

验收标准：

- `AppDependencyContainer.makeChatViewController` 直接构造 `ChatViewModel.Dependencies`。
- `ChatViewModel` 不再提供面向 `ChatUseCase` 的生产兼容 initializer。
- `ChatUseCase`、`LocalChatUseCase`、`StoreBackedChatUseCase` 不再作为 App 主装配入口。
- 文本、媒体、表情发送，分页，最新消息观察，草稿，群公告，@ 提及，删除、撤回、重发和模拟收消息行为保持不变。

### R3 App 装配职责

作为 App 层维护者，我希望 `SceneDelegate` 和 `AppDependencyContainer` 的职责继续收敛，以便账号生命周期和依赖创建可独立测试。

验收标准：

- `SceneDelegate` 不直接执行账号删除、本地数据清理或连接关闭细节。
- `AppDependencyContainer` 不再通过底层 repository 准备账号存储。
- UI 测试隔离存储、Mock 发送服务和 fail-first 发送服务行为保持不变。

### R4 全量测试稳定

作为项目维护者，我希望 `AppleIMTests` 全量组合运行稳定，以便架构重构不会被测试隔离问题掩盖。

验收标准：

- demo JSON fixture 在写入前完成结构化编码和解析校验。
- 搜索、Store 观察和 repair pending job 测试使用确定性等待，不依赖不受控异步副作用。
- 依赖 UIKit 全局状态或共享通知的测试具备隔离或串行约束。
- 全量 `AppleIMTests` 通过；如环境阻塞，需要记录具体失败和单独复现结果。

### R5 架构边界测试

作为项目维护者，我希望架构约束由测试表达，避免后续新增代码回流到旧结构。

验收标准：

- 新增测试扫描生产源码，禁止 feature/App 层调用 `storeProvider.repository()`。
- 新增测试扫描生产源码，禁止 `ChatViewModel` 兼容 `ChatUseCase` initializer。
- 新增测试扫描生产源码，禁止新增 `UseCase` 兼容 typealias 作为生产主命名。
- 架构测试失败信息指出违规文件和违规片段。
