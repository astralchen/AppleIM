# ChatBridge iOS UI 设计方案

> App 类型：IM 聊天  
> 目标平台：iOS 优先，兼容 iOS 15+，面向 iOS 26 采用 Liquid Glass 增强  
> 目标风格：微信式高可用聊天体验 + 年轻化轻娱乐视觉

---

## 1. 设计目标

ChatBridge 的 UI 应以“清楚、快速、稳定”为基础，保留类似微信的低学习成本，同时通过圆角卡片、多色渐变、轻量玻璃材质和趣味状态标识建立更年轻、更娱乐化的视觉识别。

MVP 第一版覆盖 5 个核心屏：

1. 登录页
2. 会话列表
3. 聊天页
4. 搜索页
5. 账号 / 设置页

工程实现保持现有 UIKit / MVVM 架构，不为 UI 装饰新增业务字段，不改 Store、Sync、Search、Repository 或数据库 schema。

---

## 2. 视觉语言

### 2.1 色彩 Token

```text
Brand Mint:        #27D9A5
Brand Sky:         #4DA3FF
Accent Coral:      #FF5A7A
Ink:               #111827
```

背景渐变：

```text
#EAFBFF -> #F7F1FF -> #FFF7EA
```

消息气泡：

```text
Outgoing bubble:   systemBlue / #007AFF，内容白色
Incoming bubble:   systemGray6 / system material，内容使用系统主文字色
Unread badge:      #FF5A7A
```

### 2.2 圆角 Token

```text
Page card:         22pt
Input bar:         24pt
Message bubble:    18pt
Media thumbnail:   14pt
Badge capsule:     11pt
Input field:       17pt
```

### 2.3 材质与阴影

- 页面背景使用低饱和柔和渐变，避免强烈色块干扰阅读。
- 导航、搜索框、底部输入栏、圆形工具按钮、账号操作面板可使用玻璃材质。
- 普通消息内容层不要全部做玻璃，避免聊天信息层级混乱。
- 卡片阴影保持轻量，主要用于输入栏、账号面板等浮层，不给大量列表 cell 增加昂贵实时模糊。

---

## 3. Liquid Glass 策略

iOS 26：

- 优先使用系统控件自动获得的新外观。
- 自定义按钮优先使用：
  - `UIButton.Configuration.glass()`
  - `UIButton.Configuration.prominentGlass()`
  - `UIButton.Configuration.prominentClearGlass()`
- 玻璃效果主要用于控制层和导航层，不覆盖消息主体内容。

iOS 15-25：

- 按钮降级为 `UIButton.Configuration.tinted()` 或 `filled()`。
- 玻璃容器使用 `UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))`。
- 确保浅色 / 深色模式下文字对比度足够，不出现透明度过低导致不可读。

---

## 4. 核心屏设计

### 4.1 登录页

- 全屏柔和渐变背景。
- 中央玻璃登录卡片，承载品牌标题、账号输入、密码输入、登录按钮和错误提示。
- 品牌标题使用 `ChatBridge`，字号大但不做营销式 hero。
- 账号 / 密码输入框使用 16-18pt 圆角。
- 主按钮使用 Mint-Sky 方向的强调色；iOS 26 使用 prominent glass，低版本使用 filled fallback。
- 键盘弹出时登录卡片整体稳定上移，避免输入框被遮挡和切换输入框跳动。

### 4.2 会话列表

- 顶部保留大标题 `ChatBridge`，右侧为圆形账号头像按钮。
- 搜索栏使用悬浮玻璃样式，支持聚焦搜索。
- 会话行从普通系统 list 升级为圆角卡片：
  - 头像、标题、最后消息、时间、未读数。
  - 置顶会话使用轻 Mint tint。
  - 未读数使用 Coral 胶囊。
- 保持长列表滚动性能，不给每个 cell 加实时 blur。

### 4.3 聊天页

- 背景使用低饱和渐变，聊天内容区域保持清爽。
- 消息行整体配色参照会话列表：低饱和系统背景、系统蓝轻强调、文字使用系统主次文字色。
- 所有非撤回消息都显示发送者头像：对方消息头像在左侧，自己发送消息头像在右侧。
- 撤回消息不显示头像，不保留头像占位，使用中性提示样式。
- 对方消息使用 systemGray6 / system material 灰色气泡，内容使用系统主文字色。
- 自己消息使用 Apple Messages 默认 iMessage 蓝色气泡，内容使用白色，不使用品牌渐变。
- 图片 / 视频消息使用大圆角预览。
- 语音消息使用播放图标、时长和轻量状态标识，强化娱乐感。
- 底部输入栏采用 Apple Messages 风格：
  - 轻玻璃底座。
  - 左侧更多按钮和语音按钮。
  - 中间宽输入胶囊，支持 1-5 行自动增长。
  - 右侧圆形上箭头发送按钮。
  - 图片 / 视频入口放入更多菜单。
  - Return 发送切换放入更多菜单，默认 Return 换行。
- 录音交互拆成录音中和预览确认两态：
  - 录音中使用白色长胶囊、红色从右往左滚动波形、`0:04` 风格时长和右侧红色停止按钮。
  - 录音松手或点击停止后进入待发送预览，不立即发送。
  - 预览态显示取消按钮、播放 / 暂停按钮、灰色静态波形、时长和绿色上箭头发送按钮。
  - 只有预览态绿色上箭头会发送语音；取消会删除本地临时录音。

### 4.4 搜索页

- 搜索结果按联系人、会话、消息分组。
- 每组使用紧凑圆角卡片。
- 命中文本使用 Mint 高亮。
- 空状态使用轻插画式抽象气泡或简洁图形，不使用重装饰。

### 4.5 账号 / 设置页

- 从传统 alert 升级为底部 Sheet 或玻璃操作面板。
- 面板内包含头像、昵称、账号 ID、切换账号、退出登录。
- 操作分区使用独立卡片。
- 破坏性操作使用 Coral，但保留系统确认流程。

---

## 5. 可复用组件

### 5.1 Design System

新增或维护 `ChatBridgeDesignSystem`：

- `ColorToken`
- `GradientToken`
- `RadiusToken`
- `SpacingToken`
- `ShadowToken`
- `makeGlassButtonConfiguration(role:)`
- `makeFallbackButtonConfiguration(role:)`

### 5.2 UIKit 组件

建议组件：

- `GradientBackgroundView`
- `GlassContainerView`
- `RoundedConversationCell`
- `ChatInputBarView`
- `ChatBubbleBackgroundView`
- `ChatBubbleStyle`

组件原则：

- UI 组件只接收展示状态、用户动作和必要的布局协调对象。
- 不直接持有 Repository / Store。
- 不新增 ViewState 字段来保存纯装饰状态。
- 可访问性 identifier 保持稳定，避免 UI 测试易碎。
- 交互型复合控件继承 `UIControl`，通过 target-action 与 `sendActions(for:)` 发布用户事件；带 payload 的动作由控件暴露只读 `lastAction` 或 `currentValue` 供 target 读取。
- 非用户事件但需要外部协调的能力使用 `weak delegate`，例如输入栏高度变化、相册面板拖拽关闭进度和异步选择生命周期。
- Cell、资料头和纯展示模块使用 `UIContentConfiguration` + `UIContentView` 表达内容，避免在 Cell 复用过程中临时创建和移除子视图。
- `UICollectionView` Cell 优先使用 `UICollectionView.CellRegistration` 和 diffable data source，减少手写 reuse identifier 与复用状态遗漏。
- 按钮外观统一从 `ChatBridgeDesignSystem` 获取 `UIButton.Configuration`，通过 `configurationUpdateHandler` 表达 normal、highlighted、disabled 等状态。

---

## 6. Canva 画稿结构

画布尺寸：

```text
iPhone 15/16 Pro portrait
393 x 852
```

页面结构：

1. 登录页 Frame
2. 会话列表 Frame
3. 聊天页 Frame
4. 搜索页 Frame
5. 账号 / 设置页 Frame
6. 组件页
7. 设计 Token 页

组件页包含：

- 导航栏
- 搜索栏
- 会话卡片
- 未读徽标
- 消息气泡
- 媒体气泡
- 语音条：播放图标、时长、未播放状态和播放中状态。
- 输入栏：普通文本 / 附件态、录音中动态波形态、待发送语音预览态。
- 玻璃按钮
- 账号操作 Sheet

---

## 7. 可访问性与适配

- Dynamic Type 至少支持到 `accessibilityLarge`。
- VoiceOver label 保持现有语义。
- 所有按钮点击区域不小于 44pt。
- 输入栏多行增长时不遮挡发送、图片、语音等工具入口。
- iPhone SE、标准宽度、Pro Max 都需要检查。
- 浅色 / 深色模式均需保证文字和气泡可读。

---

## 8. 验收计划

### 8.1 视觉验收

- 登录页键盘弹出不遮挡输入框。
- 会话列表 1000 条滚动保持流畅。
- 聊天页消息气泡层级清楚，不因玻璃材质造成阅读干扰。
- 输入栏 1-5 行增长平滑，超过 5 行内部滚动。
- 录音中波形从右往左滚动，停止按钮和时长不挤压波形。
- 语音预览态的取消、播放、发送按钮保持 44pt 可点击区域，绿色发送按钮不会触发文本发送。
- 浅色 / 深色模式下蓝色发送气泡白字、灰色接收气泡系统文字对比正常。
- 深色模式下玻璃、渐变、文本对比正常。

### 8.2 兼容验收

- iOS 26 验证 glass configuration 正常。
- iOS 15-25 验证 fallback 不崩溃、不透明度过低、不影响文字可读性。

### 8.3 回归路径

- 登录
- 进入会话
- 发送文本
- 发送多行文本
- 发送图片 / 视频
- 语音录制中取消
- 语音录制后预览播放
- 语音预览确认发送
- 搜索
- 切换账号
- 退出登录

### 8.4 构建与测试

```bash
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build
```

推荐 UI 测试覆盖：

- 普通文本发送
- 多行文本发送
- Return 发送模式
- 失败消息重试
- 搜索会话
- 登录 / 退出 / 切换账号

---

## 9. 默认假设

- 第一版使用现有 UIKit 工程落地，不重写为 SwiftUI。
- Canva 产出用于 UI 规格和沟通，工程实现以 Xcode / UIKit 为准。
- Liquid Glass 主要用于控制层、导航层和浮层，不滥用于消息内容层。
- UI 装饰从现有业务状态推导，避免影响同步、搜索、数据库和消息模型。
