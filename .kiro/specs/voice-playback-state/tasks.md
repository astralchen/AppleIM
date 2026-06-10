# 语音未播放红点任务清单

## 1. 规格与基线

目标：落地 Kiro 规格并确认工作区状态。

修改范围：

- `.kiro/specs/voice-playback-state/requirements.md`
- `.kiro/specs/voice-playback-state/design.md`
- `.kiro/specs/voice-playback-state/tasks.md`

命令：

```sh
git status --short
```

完成标准：规格存在，工作区无非本任务冲突。

## 2. Store 和 Chat 红灯测试

目标：先用失败测试固定“已读但未播放仍显示红点”和“播放不改已读状态”。

修改范围：

- `AppleIMTests/Store/StoreMediaAndRepairTests.swift`
- `AppleIMTests/Chat/ChatUseCaseAndRecoveryTests.swift`

测试命令：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests/localChatRepositoryMarksVoicePlaybackWithoutChangingMessageReadStatus
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/AppleIMTests/localChatUseCaseKeepsReadVoiceUnplayedUntilPlayback
```

完成标准：测试先失败，失败点指向缺少独立播放状态或旧 `read_status` 映射。

## 3. Schema、模型和 DAO

目标：增加 `message_voice.played_at` 并贯通存储模型。

修改范围：

- `AppleIM/Database/DatabaseSchema.swift`
- `AppleIM/Store/GRDBMessageRecords.swift`
- `AppleIM/Store/ChatStoreModels.swift`
- `AppleIM/Store/MessageDAO.swift`

完成标准：语音内容读写携带 `playedAt`，新库基线包含 `played_at`。

## 4. Repository 和 UI 映射

目标：将语音红点和消息已读解耦。

修改范围：

- `AppleIM/Store/LocalChatRepository.swift`
- `AppleIM/Features/Chat/UseCases/ChatUseCase.swift`
- `AppleIM/Features/Chat/Models/ChatMessageRowMapper.swift`
- `AppleIM/Core/IMModels.swift`

完成标准：`markVoicePlayed` 只写 `played_at`；语音行红点只看 `playedAt == nil` 和消息方向。

## 5. 验证

目标：确认局部测试和构建通过。

命令：

```sh
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/Store
xcodebuild -project AppleIM.xcodeproj -scheme AppleIM -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AppleIMTests/Chat
xcodebuild -quiet -project AppleIM.xcodeproj -scheme AppleIM -destination 'generic/platform=iOS Simulator' build-for-testing
```

完成标准：测试和构建通过；如模拟器环境阻塞，记录具体命令和失败原因。
