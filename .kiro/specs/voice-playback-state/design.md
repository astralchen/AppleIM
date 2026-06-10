# 语音未播放红点设计规格

## 总体设计

将消息已读状态继续保留在 `message.read_status`，将语音播放状态放到 `message_voice.played_at`。聊天 UI 的语音小红点只依赖语音播放状态和消息方向，不再依赖消息已读状态。

```text
message.read_status        -> 会话未读数、消息已读语义
message_voice.played_at    -> 语音是否播放过
ChatMessageRowContent.voice.isUnplayed -> !isOutgoing && played_at == nil
```

## 数据库设计

`message_voice` 新增字段：

- `played_at INTEGER NULL`：本账号首次播放语音的毫秒时间戳；`NULL` 表示未播放。

当前项目未上架，数据库继续以完整基线为准：

- `DatabaseSchema.currentVersion` 从 8 提升到 9。
- `DatabaseSchema.requiredColumns[.main]["message_voice"]` 增加关键字段校验，确保缺少 `played_at` 的旧基线会触发重建。
- 不新增历史迁移脚本。

## Store 设计

`MessageVoiceDatabaseRecord` 增加 `playedAt: Int64?`，读写 `played_at`。

`StoredVoiceContent` 增加：

```swift
let playedAt: Int64?
var isPlayed: Bool { playedAt != nil }
```

写入新的本地语音消息时，`playedAt` 默认使用输入内容的值；常规发送路径保持 `nil`。

## Repository 设计

`LocalChatRepository.markConversationRead` 只处理会话未读数和 `message.read_status`，不修改 `message_voice.played_at`。

`LocalChatRepository.markVoicePlayed`：

- 找不到消息时继续抛出 `messageNotFound`。
- 非语音消息直接返回。
- 语音消息更新 `message_voice.played_at = currentTimestamp()`。
- 不修改 `message.read_status`。

## UI 映射设计

`ChatUseCase` 和 `ChatMessageRowMapper` 的语音行状态统一使用：

```swift
isUnplayed: !isOutgoing && voice.playedAt == nil
```

这样进入会话后消息已读不会影响语音小红点；只有播放语音后才消除小红点。
