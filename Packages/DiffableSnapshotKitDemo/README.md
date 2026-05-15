# DiffableSnapshotKitDemo

这是一个标准 UIKit iOS Xcode 工程，用来演示如何在 UIKit 页面中使用本地 `DiffableSnapshotKit` 生成 diffable snapshot 更新计划。

## 打开方式

在 Xcode 中打开：

```text
Packages/DiffableSnapshotKitDemo/DiffableSnapshotKitDemo.xcodeproj
```

选择 `DiffableSnapshotKitDemo` scheme，运行到 iPhone 或 iPad 模拟器。

运行后在首页右上角点击 `功能` 菜单，选择要演示的能力。每个菜单项都会进入详情页，
展示该场景的关键代码和 `DiffableSnapshotPlanner` 输出。

## 工程结构

```text
DiffableSnapshotKitDemo/
  DiffableSnapshotKitDemo.xcodeproj/
  DiffableSnapshotKitDemo/
    AppDelegate.swift
    ChatSimulationViewController.swift
    DemoModels.swift
    DemoHomeViewController.swift
    DemoScenarioViewController.swift
    Assets.xcassets/
    Base.lproj/LaunchScreen.storyboard
    Info.plist
```

## 本地 Package 引入方式

工程通过 Xcode 本地 Swift Package 依赖引用：

```text
../DiffableSnapshotKit
```

也就是仓库里的：

```text
Packages/DiffableSnapshotKit
```

Demo target 链接 `DiffableSnapshotKit` product，因此页面代码可以直接：

```swift
import DiffableSnapshotKit
```

## Demo 场景

- `功能 > 模拟聊天消息`：进入真实 UIKit diffable list，用菜单触发消息 append、prepend、reconfigure、reload 和 rebuild。
- `功能 > 消息追加 + 撤回`：聊天消息底部追加，同时某条同 ID 消息从普通文本变成撤回提示。
- `功能 > 联系人 Section 变化`：联系人列表删除一个 section、新增一个 section，同时刷新某个联系人内容。
- `功能 > 中间插入触发 Rebuild`：新 item 插入到中间位置，触发 rebuild。

## reconfigure 和 reload

使用 `.reconfigure`：

- item ID 不变。
- cell 类型不变。
- 只是标题、副标题、时间、状态等内容变化。

使用 `.reload`：

- item ID 不变。
- cell 类型或 cell registration 可能变化。
- 典型场景：普通消息变成撤回消息，需要从文本消息 cell 换成撤回提示 cell。

新增 item 不需要 `.reconfigure` 或 `.reload`，因为插入时 cell provider 会重新配置它。删除 item 也不能刷新，否则接入 UIKit 时容易触发 diffable snapshot 的前置条件错误。

## UIKit adapter 推荐顺序

`DiffableSnapshotKit` 只输出计划，不直接操作 UIKit。未来封装 adapter 时，建议按这个顺序应用：

```text
删 item -> 删 section -> 加 section -> 加 item -> reloadItems -> reconfigureItems
```
