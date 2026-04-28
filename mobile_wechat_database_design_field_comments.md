# 手机微信级 IM 本地数据库详细设计

> 说明：微信手机端真实完整数据库表结构没有官方公开。本文分为两部分：
>
> 1. **公开可确认信息**：基于腾讯官方 WCDB 资料和公开项目中可观察到的事实。
> 2. **工程化设计方案**：基于移动 IM、微信级聊天产品的通用工程实践整理，可用于自研 IM、本地聊天存储、仿微信消息系统设计。

---

## 一、公开可确认的信息

腾讯官方公开资料中可以确认：

- 微信内部使用 **WCDB** 作为移动端数据库框架。
- WCDB 基于 **SQLite** 和 **SQLCipher**。
- WCDB 支持：
  - 数据库加密
  - 全文搜索
  - 字段升级
  - 数据迁移
  - 损坏修复
  - 数据压缩
  - 多线程安全访问
- 公开分析工具中，Android 微信用户目录下常见核心数据库文件，例如 `EnMicroMsg.db`。

因此可以合理判断，微信移动端数据库并不是简单的一张聊天记录表，而是接近下面这种结构：

- 核心消息数据库
- 联系人/会话/索引表
- 媒体资源文件目录
- 搜索索引库
- 加密与迁移层
- 数据修复与压缩机制

---

## 二、整体数据库分层设计

如果设计一个“手机微信级”的 IM 本地数据库，建议拆成以下几层。

### 1. 账户层

按登录账号隔离数据。

推荐目录结构：

```text
account_xxx/
  main.db
  search.db
  file_index.db
  media/
  cache/
```

好处：

- 多账号切换简单
- 退出登录时可单独清理
- 避免账号之间串数据
- 加密密钥可按账号管理

---

### 2. 主业务库 main.db

存储强一致核心业务数据：

- 用户信息
- 联系人
- 会话
- 消息
- 消息扩展内容
- 群信息
- 已读状态
- 草稿
- 本地任务队列

---

### 3. 搜索库 search.db

专门处理全文搜索。

适合存储：

- 聊天记录全文索引
- 联系人搜索索引
- 群名搜索索引
- 文件搜索索引

好处：

- 搜索索引与主库解耦
- 索引损坏后可重建
- 避免主库过大影响普通读写

---

### 4. 文件索引库 file_index.db

用于管理媒体和文件资源。

适合存储：

- 图片
- 视频
- 语音
- 文件
- 表情
- 头像
- 缩略图
- 下载状态
- 上传状态

---

### 5. 缓存层

缓存层不要求强一致，可以丢失后重建。

适合存储：

- 头像缓存
- 会话列表 UI 快照
- 最近表情
- 已解码富文本
- 临时上传任务状态

---

## 三、核心实体关系

推荐核心实体：

- `user`
- `contact`
- `conversation`
- `conversation_member`
- `message`
- `message_text`
- `message_image`
- `message_voice`
- `message_video`
- `message_file`
- `message_receipt`
- `message_reaction`
- `message_revoke`
- `media_resource`
- `draft`
- `sync_checkpoint`
- `pending_job`

### 核心关系

```text
user
 └── contact

conversation
 ├── conversation_member
 ├── message
 │    ├── message_text
 │    ├── message_image
 │    ├── message_voice
 │    ├── message_video
 │    ├── message_file
 │    ├── message_receipt
 │    ├── message_reaction
 │    └── message_revoke
 └── draft
```

---

## 四、核心表结构设计

> 字段注释说明：以下 SQL 采用 `-- 注释` 写在字段行尾，便于直接阅读字段含义。SQLite 本身没有 MySQL 那种 `COMMENT` 字段属性；如果使用 WCDB/SQLite，字段说明通常放在文档、迁移脚本或代码模型注释中。


## 1. 用户表 user

```sql
CREATE TABLE user (
    user_id              TEXT PRIMARY KEY,              -- 当前登录账号或所属用户 ID，用于账号隔离
    wxid                 TEXT UNIQUE,                   -- 微信号/业务账号唯一标识
    nickname             TEXT,                          -- 用户昵称
    avatar_url           TEXT,                          -- 头像远程地址
    gender               INTEGER,                       -- 性别枚举值
    region               TEXT,                          -- 地区信息
    signature            TEXT,                          -- 个性签名
    remark               TEXT,                          -- 联系人备注名
    mobile               TEXT,                          -- 手机号，建议脱敏或加密存储
    extra_json           TEXT,                          -- 扩展字段，存放暂未结构化的业务数据
    updated_at           INTEGER,                       -- 更新时间，Unix 毫秒时间戳
    created_at           INTEGER                        -- 创建时间，Unix 毫秒时间戳
);
```

### 字段说明

| 字段 | 说明 |
|---|---|
| `user_id` | 内部用户 ID |
| `wxid` | 用户唯一标识，可理解为业务账号 ID |
| `nickname` | 昵称 |
| `avatar_url` | 头像地址 |
| `gender` | 性别 |
| `region` | 地区 |
| `signature` | 个性签名 |
| `remark` | 备注 |
| `extra_json` | 扩展字段 |
| `updated_at` | 更新时间 |
| `created_at` | 创建时间 |

---

## 2. 联系人表 contact

```sql
CREATE TABLE contact (
    contact_id           TEXT PRIMARY KEY,              -- 联系人记录 ID
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    wxid                 TEXT NOT NULL,                 -- 微信号/业务账号唯一标识
    nickname             TEXT,                          -- 用户昵称
    remark               TEXT,                          -- 联系人备注名
    avatar_url           TEXT,                          -- 头像远程地址
    type                 INTEGER NOT NULL,              -- 联系人类型枚举
    is_starred           INTEGER DEFAULT 0,             -- 是否星标/特别关注，0 否 1 是
    is_blocked           INTEGER DEFAULT 0,             -- 是否已拉黑，0 否 1 是
    is_deleted           INTEGER DEFAULT 0,             -- 是否逻辑删除，0 否 1 是
    source               INTEGER,                       -- 来源类型，例如搜索、群聊、扫码添加等
    extra_json           TEXT,                          -- 扩展字段，存放暂未结构化的业务数据
    updated_at           INTEGER,                       -- 更新时间，Unix 毫秒时间戳
    created_at           INTEGER                        -- 创建时间，Unix 毫秒时间戳
);

CREATE INDEX idx_contact_user_wxid ON contact(user_id, wxid);
CREATE INDEX idx_contact_user_updated ON contact(user_id, updated_at);
```

### type 建议枚举

| 值 | 含义 |
|---|---|
| 1 | 好友 |
| 2 | 群 |
| 3 | 公众号 |
| 4 | 系统账号 |
| 5 | 陌生人 |

---

## 3. 会话表 conversation

```sql
CREATE TABLE conversation (
    conversation_id      TEXT PRIMARY KEY,              -- 会话 ID，单聊/群聊/系统会话的唯一标识
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    biz_type             INTEGER NOT NULL,              -- 会话业务类型枚举
    target_id            TEXT NOT NULL,                 -- 会话目标 ID，单聊为对方用户 ID，群聊为群 ID
    title                TEXT,                          -- 标题
    avatar_url           TEXT,                          -- 头像远程地址
    last_message_id      TEXT,                          -- 最后一条消息 ID，用于会话列表展示
    last_message_time    INTEGER,                       -- 最后一条消息时间
    last_message_digest  TEXT,                          -- 最后一条消息摘要文本
    unread_count         INTEGER DEFAULT 0,             -- 当前会话未读数
    draft_text           TEXT,                          -- 会话草稿文本
    is_pinned            INTEGER DEFAULT 0,             -- 是否置顶，0 否 1 是
    is_muted             INTEGER DEFAULT 0,             -- 是否免打扰，0 否 1 是
    is_hidden            INTEGER DEFAULT 0,             -- 是否隐藏会话，0 否 1 是
    sort_ts              INTEGER NOT NULL,              -- 会话排序时间戳，置顶和普通会话统一排序使用
    extra_json           TEXT,                          -- 扩展字段，存放暂未结构化的业务数据
    updated_at           INTEGER,                       -- 更新时间，Unix 毫秒时间戳
    created_at           INTEGER                        -- 创建时间，Unix 毫秒时间戳
);

CREATE INDEX idx_conversation_user_sort ON conversation(user_id, is_pinned DESC, sort_ts DESC);
CREATE INDEX idx_conversation_user_target ON conversation(user_id, target_id);
```

### biz_type 建议枚举

| 值 | 含义 |
|---|---|
| 1 | 单聊 |
| 2 | 群聊 |
| 3 | 系统会话 |
| 4 | 服务号/订阅号 |

### 设计重点

会话表应当冗余以下字段：

- `last_message_id`
- `last_message_time`
- `last_message_digest`
- `unread_count`
- `sort_ts`

这样会话列表可以直接读取，不需要每次从消息表实时聚合。

---

## 4. 群成员表 conversation_member

```sql
CREATE TABLE conversation_member (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT, -- 自增主键 ID
    conversation_id      TEXT NOT NULL,                 -- 会话 ID，单聊/群聊/系统会话的唯一标识
    member_id            TEXT NOT NULL,                 -- 群成员用户 ID
    display_name         TEXT,                          -- 成员在群内的显示名称
    role                 INTEGER DEFAULT 0,             -- 群成员角色枚举
    join_time            INTEGER,                       -- 入群时间
    extra_json           TEXT,                          -- 扩展字段，存放暂未结构化的业务数据
    UNIQUE(conversation_id, member_id)
);

CREATE INDEX idx_member_conversation ON conversation_member(conversation_id);
```

### role 建议枚举

| 值 | 含义 |
|---|---|
| 0 | 普通成员 |
| 1 | 管理员 |
| 2 | 群主 |

---

## 5. 消息主表 message

消息主表只存公共字段，不建议把所有消息类型字段都塞进一张大表。

```sql
CREATE TABLE message (
    message_id           TEXT PRIMARY KEY,              -- 消息 ID，本地全局唯一
    local_id             INTEGER UNIQUE,                -- 本地自增 ID，便于游标分页
    conversation_id      TEXT NOT NULL,                 -- 会话 ID，单聊/群聊/系统会话的唯一标识
    sender_id            TEXT NOT NULL,                 -- 发送者用户 ID
    client_msg_id        TEXT UNIQUE,                   -- 客户端生成的消息 ID，用于发送幂等和重试映射
    server_msg_id        TEXT,                          -- 服务端返回的正式消息 ID
    seq                  INTEGER,                       -- 服务端会话内递增序号，用于同步和排序
    msg_type             INTEGER NOT NULL,              -- 消息类型枚举
    direction            INTEGER NOT NULL,              -- 消息方向，发出或收到
    send_status          INTEGER NOT NULL,              -- 发送状态，本地发送流程使用
    delivery_status      INTEGER DEFAULT 0,             -- 投递状态，表示是否到达服务端/对端
    read_status          INTEGER DEFAULT 0,             -- 已读状态
    revoke_status        INTEGER DEFAULT 0,             -- 撤回状态，0 正常 1 已撤回
    is_deleted           INTEGER DEFAULT 0,             -- 是否逻辑删除，0 否 1 是
    quoted_message_id    TEXT,                          -- 被引用消息 ID
    reply_to_message_id  TEXT,                          -- 回复目标消息 ID
    content_table        TEXT,                          -- 具体内容所在的扩展表名
    content_id           TEXT,                          -- 消息内容 ID，与 message.content_id 对应
    sort_seq             INTEGER NOT NULL,              -- 本地排序序号，优先使用服务端 seq 回填
    server_time          INTEGER,                       -- 服务端消息时间
    local_time           INTEGER NOT NULL,              -- 本地创建或接收时间
    edit_version         INTEGER DEFAULT 0,             -- 消息编辑版本号
    extra_json           TEXT                           -- 扩展字段，存放暂未结构化的业务数据
);

CREATE INDEX idx_message_conversation_sort ON message(conversation_id, sort_seq DESC);
CREATE INDEX idx_message_conversation_server ON message(conversation_id, server_time DESC);
CREATE INDEX idx_message_client_msg_id ON message(client_msg_id);
CREATE INDEX idx_message_server_msg_id ON message(server_msg_id);
```

### msg_type 建议枚举

| 值 | 类型 |
|---|---|
| 1 | 文本 |
| 2 | 图片 |
| 3 | 语音 |
| 4 | 视频 |
| 5 | 文件 |
| 6 | 名片 |
| 7 | 位置 |
| 8 | 系统消息 |
| 9 | 撤回提示 |
| 10 | 表情 |
| 11 | 引用消息 |
| 12 | 卡片消息 |
| 13 | 通话记录 |

### direction 建议枚举

| 值 | 含义 |
|---|---|
| 1 | 发出 |
| 2 | 收到 |

### send_status 建议枚举

| 值 | 含义 |
|---|---|
| 0 | 待发送 |
| 1 | 发送中 |
| 2 | 发送成功 |
| 3 | 发送失败 |

### delivery_status 建议枚举

| 值 | 含义 |
|---|---|
| 0 | 未投递 |
| 1 | 已投递服务器 |
| 2 | 已到达对端设备 |

### read_status 建议枚举

| 值 | 含义 |
|---|---|
| 0 | 未读 |
| 1 | 已读 |

---

## 6. 文本消息表 message_text

```sql
CREATE TABLE message_text (
    content_id           TEXT PRIMARY KEY,              -- 消息内容 ID，与 message.content_id 对应
    text                 TEXT NOT NULL,                 -- 文本消息内容
    mentions_json        TEXT,                          -- @ 用户列表 JSON
    at_all               INTEGER DEFAULT 0,             -- 是否 @ 所有人，0 否 1 是
    rich_text_json       TEXT                           -- 富文本结构 JSON
);
```

### 字段说明

| 字段 | 说明 |
|---|---|
| `text` | 文本内容 |
| `mentions_json` | @ 用户列表 |
| `at_all` | 是否 @ 所有人 |
| `rich_text_json` | 富文本扩展数据 |

---

## 7. 图片消息表 message_image

```sql
CREATE TABLE message_image (
    content_id           TEXT PRIMARY KEY,              -- 消息内容 ID，与 message.content_id 对应
    media_id             TEXT,                          -- 媒体资源 ID，通常由服务端或文件系统生成
    width                INTEGER,                       -- 图片/视频宽度
    height               INTEGER,                       -- 图片/视频高度
    size_bytes           INTEGER,                       -- 文件大小，单位字节
    local_path           TEXT,                          -- 本地文件路径
    thumb_path           TEXT,                          -- 缩略图本地路径
    cdn_url              TEXT,                          -- 媒体远程 CDN 地址
    md5                  TEXT,                          -- 文件 MD5，用于校验和去重
    format               TEXT,                          -- 文件格式，例如 jpg、png、mp4、amr
    upload_status        INTEGER DEFAULT 0,             -- 上传状态枚举
    download_status      INTEGER DEFAULT 0              -- 下载状态枚举
);
```

---

## 8. 语音消息表 message_voice

```sql
CREATE TABLE message_voice (
    content_id           TEXT PRIMARY KEY,              -- 消息内容 ID，与 message.content_id 对应
    media_id             TEXT,                          -- 媒体资源 ID，通常由服务端或文件系统生成
    duration_ms          INTEGER,                       -- 时长，单位毫秒
    size_bytes           INTEGER,                       -- 文件大小，单位字节
    local_path           TEXT,                          -- 本地文件路径
    cdn_url              TEXT,                          -- 媒体远程 CDN 地址
    format               TEXT,                          -- 文件格式，例如 jpg、png、mp4、amr
    transcript           TEXT,                          -- 语音转文字结果
    upload_status        INTEGER DEFAULT 0,             -- 上传状态枚举
    download_status      INTEGER DEFAULT 0              -- 下载状态枚举
);
```

---

## 9. 视频消息表 message_video

```sql
CREATE TABLE message_video (
    content_id           TEXT PRIMARY KEY,              -- 消息内容 ID，与 message.content_id 对应
    media_id             TEXT,                          -- 媒体资源 ID，通常由服务端或文件系统生成
    duration_ms          INTEGER,                       -- 时长，单位毫秒
    width                INTEGER,                       -- 图片/视频宽度
    height               INTEGER,                       -- 图片/视频高度
    size_bytes           INTEGER,                       -- 文件大小，单位字节
    local_path           TEXT,                          -- 本地文件路径
    thumb_path           TEXT,                          -- 缩略图本地路径
    cdn_url              TEXT,                          -- 媒体远程 CDN 地址
    md5                  TEXT,                          -- 文件 MD5，用于校验和去重
    upload_status        INTEGER DEFAULT 0,             -- 上传状态枚举
    download_status      INTEGER DEFAULT 0              -- 下载状态枚举
);
```

---

## 10. 文件消息表 message_file

```sql
CREATE TABLE message_file (
    content_id           TEXT PRIMARY KEY,              -- 消息内容 ID，与 message.content_id 对应
    media_id             TEXT,                          -- 媒体资源 ID，通常由服务端或文件系统生成
    file_name            TEXT,                          -- 文件名
    file_ext             TEXT,                          -- 文件扩展名
    size_bytes           INTEGER,                       -- 文件大小，单位字节
    local_path           TEXT,                          -- 本地文件路径
    cdn_url              TEXT,                          -- 媒体远程 CDN 地址
    md5                  TEXT,                          -- 文件 MD5，用于校验和去重
    upload_status        INTEGER DEFAULT 0,             -- 上传状态枚举
    download_status      INTEGER DEFAULT 0              -- 下载状态枚举
);
```

---

## 11. 消息已读回执表 message_receipt

```sql
CREATE TABLE message_receipt (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT, -- 自增主键 ID
    message_id           TEXT NOT NULL,                 -- 消息 ID，本地全局唯一
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    receipt_type         INTEGER NOT NULL,              -- 回执类型，送达或已读
    receipt_time         INTEGER,                       -- 回执时间
    UNIQUE(message_id, user_id, receipt_type)
);

CREATE INDEX idx_receipt_message ON message_receipt(message_id);
```

### receipt_type 建议枚举

| 值 | 含义 |
|---|---|
| 1 | 已送达 |
| 2 | 已读 |

---

## 12. 消息反应表 message_reaction

```sql
CREATE TABLE message_reaction (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT, -- 自增主键 ID
    message_id           TEXT NOT NULL,                 -- 消息 ID，本地全局唯一
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    reaction             TEXT NOT NULL,                 -- 表情回应内容，例如 👍 或 emoji key
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    UNIQUE(message_id, user_id, reaction)
);
```

用于实现：

- 点赞
- 表情回应
- Emoji reaction

---

## 13. 撤回记录表 message_revoke

```sql
CREATE TABLE message_revoke (
    message_id           TEXT PRIMARY KEY,              -- 消息 ID，本地全局唯一
    operator_id          TEXT NOT NULL,                 -- 操作者用户 ID
    revoke_time          INTEGER NOT NULL,              -- 撤回时间
    reason               TEXT,                          -- 原因说明
    replace_text         TEXT                           -- 撤回后展示的替代文案
);
```

### 撤回逻辑建议

撤回不建议物理删除原消息，而是：

1. `message.revoke_status = 1`
2. 插入 `message_revoke`
3. UI 渲染为撤回提示
4. 如果撤回的是最后一条消息，更新会话摘要

例如：

- 你撤回了一条消息
- 对方撤回了一条消息
- 管理员撤回了一条成员消息

---

## 14. 草稿表 draft

```sql
CREATE TABLE draft (
    conversation_id      TEXT PRIMARY KEY,              -- 会话 ID，单聊/群聊/系统会话的唯一标识
    text                 TEXT,                          -- 文本消息内容
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);
```

也可以把草稿直接冗余到 `conversation.draft_text`。如果草稿未来比较复杂，例如支持引用、图片、@ 人，可以单独建表。

---

## 15. 同步游标表 sync_checkpoint

```sql
CREATE TABLE sync_checkpoint (
    biz_key              TEXT PRIMARY KEY,              -- 同步业务 key，例如 contact/message/group
    cursor               TEXT,                          -- 服务端同步游标
    seq                  INTEGER,                       -- 服务端会话内递增序号，用于同步和排序
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);
```

适合记录：

- 联系人同步游标
- 会话同步游标
- 消息漫游同步点
- 群成员同步版本
- 文件同步游标

---

## 16. 本地任务表 pending_job

```sql
CREATE TABLE pending_job (
    job_id               TEXT PRIMARY KEY,              -- 本地任务 ID
    job_type             INTEGER NOT NULL,              -- 任务类型枚举
    ref_id               TEXT,                          -- 关联业务 ID，例如 message_id/media_id
    payload_json         TEXT,                          -- 任务参数 JSON
    status               INTEGER NOT NULL,              -- 状态枚举
    retry_count          INTEGER DEFAULT 0,             -- 已重试次数
    next_retry_at        INTEGER,                       -- 下次重试时间
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);

CREATE INDEX idx_job_status_retry ON pending_job(status, next_retry_at);
```

适合处理：

- 消息重发
- 图片上传
- 视频上传
- 媒体下载
- 缩略图生成
- 搜索索引补建
- 消息补偿同步

---

## 五、为什么消息要“头表 + 内容分表”

不建议把文本、图片、视频、语音、文件、位置、卡片、引用消息全部塞到 `message` 一张表里。

### 单表问题

- 字段太多
- 空字段太多
- 索引浪费
- 表迁移困难
- 会话列表读取变慢
- 不同消息类型扩展困难

### 推荐方式

```text
message
 ├── message_text
 ├── message_image
 ├── message_voice
 ├── message_video
 ├── message_file
 ├── message_location
 └── message_card
```

`message` 只存公共字段。具体内容通过 `content_table + content_id` 关联。

---

## 六、消息 ID 设计

建议使用四类 ID。

### 1. local_id

本地自增 ID。

用途：

- 本地分页
- 本地排序
- 快速定位

---

### 2. client_msg_id

客户端发送前生成的 UUID。

用途：

- 发送重试
- 幂等去重
- 状态跟踪
- 服务端回包映射

---

### 3. server_msg_id

服务端正式消息 ID。

用途：

- 服务端消息唯一标识
- 多端同步
- 消息撤回
- 消息回执

---

### 4. seq

会话维度的服务端递增序列。

用途：

- 消息排序
- 增量拉取
- 缺口补偿
- 离线同步

---

## 七、消息排序设计

聊天消息不要单纯依赖时间戳排序。

推荐排序优先级：

1. `seq`
2. `server_time`
3. `local_time`
4. `local_id`

原因：

- 弱网下客户端时间不可靠
- 多端同步可能乱序
- 离线补拉可能插入历史消息
- 服务端 seq 更适合作为最终顺序依据

---

## 八、会话列表设计

会话列表不建议实时从消息表聚合。

推荐在 `conversation` 表中冗余：

- `last_message_id`
- `last_message_time`
- `last_message_digest`
- `unread_count`
- `sort_ts`

### 新消息入库流程

```text
收到消息
  ↓
写入 message
  ↓
写入对应内容表
  ↓
更新 conversation.last_message_xxx
  ↓
更新 conversation.unread_count
  ↓
更新 conversation.sort_ts
  ↓
通知 UI 刷新
```

这样会话列表性能更稳定。

---

## 九、搜索设计

建议单独维护全文搜索表。

```sql
CREATE VIRTUAL TABLE fts_message USING fts5(
    message_id,
    conversation_id,
    sender_name,
    content,
    tokenize = 'unicode61'
);
```

### 可拆分搜索索引

- `fts_message`
- `fts_contact`
- `fts_conversation`
- `fts_file`

### 索引维护方式

可以选择：

1. 触发器同步更新
2. 消息入库后异步写入索引
3. 定期补建索引
4. 索引库损坏后全量重建

移动端更推荐异步维护，避免影响消息入库性能。

---

## 十、媒体文件存储设计

大文件不建议直接存入 SQLite BLOB。

推荐方式：

- 数据库存媒体元数据
- 文件实体落磁盘

### 推荐目录结构

```text
media/
  image/
    original/
    thumb/
  video/
    original/
    thumb/
  voice/
  file/
  avatar/
  emoji/
```

### 数据库中存储

- `media_id`
- `local_path`
- `thumb_path`
- `cdn_url`
- `md5`
- `width`
- `height`
- `duration_ms`
- `size_bytes`
- `upload_status`
- `download_status`

### 文件命名建议

- 使用 `md5`
- 使用 `media_id`
- 使用 URL 或路径 hash

这样方便去重和缓存命中。

---

## 十一、消息发送状态流转

## 1. 文本消息发送流程

```text
用户发送文本
  ↓
生成 client_msg_id
  ↓
本地插入 message，状态 pending
  ↓
UI 立即显示
  ↓
请求服务端发送
  ↓
服务端返回 server_msg_id / seq / server_time
  ↓
更新本地消息为 success
  ↓
更新会话摘要
```

---

## 2. 图片消息发送流程

```text
用户发送图片
  ↓
本地保存原图和缩略图
  ↓
插入 message + message_image
  ↓
状态设置为 uploading
  ↓
上传图片到 CDN
  ↓
拿到 media_id / cdn_url
  ↓
发送消息体到服务端
  ↓
服务端 ack
  ↓
更新 server_msg_id / seq / send_status
```

媒体消息比文本消息多一步上传状态管理。

---

## 十二、撤回设计

撤回不要直接删除消息记录。

### 数据层处理

```text
message.revoke_status = 1
插入 message_revoke
更新 conversation.last_message_digest
```

### UI 层处理

渲染成系统提示：

- 你撤回了一条消息
- 对方撤回了一条消息
- 管理员撤回了一条成员消息

### 会话层处理

如果被撤回消息是会话最后一条，则需要更新：

- `conversation.last_message_id`
- `conversation.last_message_digest`
- `conversation.last_message_time`

---

## 十三、删除设计

需要区分三种删除。

### 1. 本地删除消息

只影响本机显示。

```sql
UPDATE message SET is_deleted = 1 WHERE message_id = ?;
```

---

### 2. 服务端撤回

由服务端广播撤回事件，多端同步。

处理方式：

- 更新消息撤回状态
- 插入撤回记录
- 更新会话摘要

---

### 3. 清空聊天记录

不建议一次性删除大量消息。

推荐：

- 分批删除
- 使用事务
- 空闲时执行清理
- 必要时执行 `VACUUM` 或 checkpoint

---

## 十四、同步设计

同步至少分三类。

### 1. 全量同步

适用于：

- 首次登录
- 换机
- 恢复数据

---

### 2. 增量同步

基于：

- `cursor`
- `seq`
- `updated_at`

---

### 3. 修复同步

当发现消息缺口时，按区间补拉。

例如：

```text
当前本地 seq: 100, 101, 102, 106
发现缺少 103, 104, 105
触发补拉 103 - 105
```

---

## 十五、加密与安全设计

推荐做法：

- 整库加密
- 密钥不硬编码
- 密钥与账号绑定
- 密钥存入 Keychain / Keystore
- 媒体文件做文件级保护
- 日志脱敏
- Crash 日志不打印 SQL 和消息明文
- 调试工具只在 Debug 环境开启

---

## 十六、性能设计

### 必加索引

```sql
CREATE INDEX idx_message_conversation_sort ON message(conversation_id, sort_seq DESC);
CREATE INDEX idx_message_client_msg_id ON message(client_msg_id);
CREATE INDEX idx_message_server_msg_id ON message(server_msg_id);
CREATE INDEX idx_conversation_user_sort ON conversation(user_id, is_pinned DESC, sort_ts DESC);
CREATE INDEX idx_contact_user_wxid ON contact(user_id, wxid);
```

---

### 分页策略

不推荐深分页：

```sql
SELECT * FROM message
WHERE conversation_id = ?
ORDER BY sort_seq DESC
LIMIT 20 OFFSET 10000;
```

推荐游标分页：

```sql
SELECT * FROM message
WHERE conversation_id = ?
  AND sort_seq < ?
ORDER BY sort_seq DESC
LIMIT 20;
```

好处：

- 性能稳定
- 大会话不卡
- 更适合移动端

---

### 写入策略

建议：

- 批量插入
- 小事务合并
- 异步搜索索引
- 异步媒体处理
- 会话摘要冗余写入
- UI 层增量刷新

---

## 十七、推荐库拆分方案

如果项目规模较大，可以拆成多个库。

### user.db

- 当前账号
- 用户设置
- 登录态
- 草稿

### social.db

- 联系人
- 群信息
- 群成员
- 会话

### message.db

- 消息主表
- 消息内容分表
- 回执
- 撤回
- reaction

### search.db

- FTS 全文搜索表

### file_index.db

- 媒体索引
- 文件索引
- 下载状态
- 上传状态

---

## 十八、可扩展业务表

如果要更接近微信级产品，除了联系人、会话、消息、媒体、搜索这些核心表之外，还需要补充一批“增强体验”和“系统能力”相关表。

这些表不一定都属于聊天主链路，但会直接影响产品完整度，例如：收藏、表情、群公告、消息置顶、聊天背景、多端同步、隐私设置、迁移记录等。

---

### 18.1 扩展表总览

| 表名 | 用途 | 是否核心 |
|---|---|---|
| `favorite_item` | 收藏消息、图片、文件、链接、笔记等 | 重要 |
| `favorite_tag` | 收藏标签 | 可选 |
| `favorite_tag_relation` | 收藏与标签关系 | 可选 |
| `emoji_store` | 自定义表情、最近表情、收藏表情 | 重要 |
| `emoji_package` | 表情包信息 | 可选 |
| `session_tag` | 会话标签，例如朋友、客户、家人、工作 | 可选 |
| `conversation_tag_relation` | 会话和标签关系 | 可选 |
| `chat_background` | 聊天背景设置 | 可选 |
| `top_notice` | 群公告、置顶公告 | 重要 |
| `message_pin` | 消息置顶 | 重要 |
| `message_edit_history` | 消息编辑历史 | 可选 |
| `device_sync_state` | 多端同步状态 | 重要 |
| `privacy_setting` | 隐私设置 | 重要 |
| `notification_setting` | 消息通知设置 | 重要 |
| `blacklist` | 黑名单 | 重要 |
| `conversation_setting` | 单个会话的免打扰、置顶、背景、输入状态等 | 重要 |
| `message_local_state` | 本地 UI 状态，例如播放状态、展开状态、翻译状态 | 可选 |
| `message_translate` | 消息翻译缓存 | 可选 |
| `migration_meta` | 数据库迁移元数据 | 重要 |
| `database_repair_log` | 数据库修复记录 | 可选 |

---

### 18.2 收藏表 favorite_item

微信类产品通常支持收藏：文本、图片、视频、语音、文件、聊天记录、链接、小程序卡片、位置、笔记等。

收藏不要直接复制一份完整消息，可以保存：

- 原消息 ID
- 收藏类型
- 收藏摘要
- 资源 ID
- 原始会话 ID
- 原发送者
- 收藏时间
- 扩展 JSON

```sql
CREATE TABLE favorite_item (
    favorite_id          TEXT PRIMARY KEY,              -- 收藏记录 ID
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    source_type          INTEGER NOT NULL,              -- 收藏来源类型枚举
    source_id            TEXT,                          -- 来源对象 ID，例如 message_id
    conversation_id      TEXT,                          -- 会话 ID，单聊/群聊/系统会话的唯一标识
    message_id           TEXT,                          -- 消息 ID，本地全局唯一
    sender_id            TEXT,                          -- 发送者用户 ID
    title                TEXT,                          -- 标题
    digest               TEXT,                          -- 收藏摘要，用于列表展示
    cover_path           TEXT,                          -- 封面本地路径
    content_json         TEXT,                          -- 收藏内容 JSON
    is_deleted           INTEGER DEFAULT 0,             -- 是否逻辑删除，0 否 1 是
    sort_time            INTEGER NOT NULL,              -- 收藏排序时间，通常等于收藏时间或最近更新时间
    created_at           INTEGER NOT NULL,              -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);

CREATE INDEX idx_favorite_user_sort ON favorite_item(user_id, sort_time DESC);
CREATE INDEX idx_favorite_message ON favorite_item(message_id);
```

`source_type` 建议：

| 值 | 含义 |
|---|---|
| 1 | 文本 |
| 2 | 图片 |
| 3 | 语音 |
| 4 | 视频 |
| 5 | 文件 |
| 6 | 链接 |
| 7 | 位置 |
| 8 | 名片 |
| 9 | 聊天记录合并转发 |
| 10 | 笔记 |
| 11 | 小程序/卡片 |

---

### 18.3 收藏标签 favorite_tag

如果收藏支持标签，可以加标签表和关系表。

```sql
CREATE TABLE favorite_tag (
    tag_id               TEXT PRIMARY KEY,              -- 标签 ID
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    name                 TEXT NOT NULL,                 -- 名称
    color                TEXT,                          -- 颜色值
    sort_order           INTEGER DEFAULT 0,             -- 排序值，越小越靠前
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER,                       -- 更新时间，Unix 毫秒时间戳
    UNIQUE(user_id, name)
);

CREATE TABLE favorite_tag_relation (
    favorite_id          TEXT NOT NULL,                 -- 收藏记录 ID
    tag_id               TEXT NOT NULL,                 -- 标签 ID
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    PRIMARY KEY(favorite_id, tag_id)
);
```

---

### 18.4 表情表 emoji_store

表情系统一般分三类：

- 最近使用表情
- 收藏表情
- 表情包表情

```sql
CREATE TABLE emoji_store (
    emoji_id             TEXT PRIMARY KEY,              -- 表情 ID
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    package_id           TEXT,                          -- 表情包 ID
    emoji_type           INTEGER NOT NULL,              -- 表情类型枚举
    name                 TEXT,                          -- 名称
    md5                  TEXT,                          -- 文件 MD5，用于校验和去重
    local_path           TEXT,                          -- 本地文件路径
    thumb_path           TEXT,                          -- 缩略图本地路径
    cdn_url              TEXT,                          -- 媒体远程 CDN 地址
    width                INTEGER,                       -- 图片/视频宽度
    height               INTEGER,                       -- 图片/视频高度
    size_bytes           INTEGER,                       -- 文件大小，单位字节
    use_count            INTEGER DEFAULT 0,             -- 使用次数
    last_used_at         INTEGER,                       -- 最近使用时间
    is_favorite          INTEGER DEFAULT 0,             -- 是否收藏，0 否 1 是
    is_deleted           INTEGER DEFAULT 0,             -- 是否逻辑删除，0 否 1 是
    extra_json           TEXT,                          -- 扩展字段，存放暂未结构化的业务数据
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);

CREATE INDEX idx_emoji_user_recent ON emoji_store(user_id, last_used_at DESC);
CREATE INDEX idx_emoji_user_favorite ON emoji_store(user_id, is_favorite, created_at DESC);
```

`emoji_type` 建议：

| 值 | 含义 |
|---|---|
| 1 | 系统 emoji |
| 2 | 自定义图片表情 |
| 3 | GIF 表情 |
| 4 | 表情包表情 |
| 5 | 动态贴纸 |

---

### 18.5 表情包表 emoji_package

```sql
CREATE TABLE emoji_package (
    package_id           TEXT PRIMARY KEY,              -- 表情包 ID
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    title                TEXT NOT NULL,                 -- 标题
    author               TEXT,                          -- 作者
    cover_url            TEXT,                          -- 封面远程地址
    local_cover_path     TEXT,                          -- 封面本地路径
    version              INTEGER DEFAULT 0,             -- 版本号
    status               INTEGER DEFAULT 0,             -- 状态枚举
    sort_order           INTEGER DEFAULT 0,             -- 排序值，越小越靠前
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);
```

`status` 可以表示：

| 值 | 含义 |
|---|---|
| 0 | 未下载 |
| 1 | 下载中 |
| 2 | 已下载 |
| 3 | 失效 |

---

### 18.6 会话标签 session_tag

会话标签适合用于企业 IM、客户管理、私聊分类。

```sql
CREATE TABLE session_tag (
    tag_id               TEXT PRIMARY KEY,              -- 标签 ID
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    name                 TEXT NOT NULL,                 -- 名称
    color                TEXT,                          -- 颜色值
    sort_order           INTEGER DEFAULT 0,             -- 排序值，越小越靠前
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER,                       -- 更新时间，Unix 毫秒时间戳
    UNIQUE(user_id, name)
);

CREATE TABLE conversation_tag_relation (
    conversation_id      TEXT NOT NULL,                 -- 会话 ID，单聊/群聊/系统会话的唯一标识
    tag_id               TEXT NOT NULL,                 -- 标签 ID
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    PRIMARY KEY(conversation_id, tag_id)
);
```

---

### 18.7 聊天背景表 chat_background

聊天背景可以分全局、单聊、群聊三种维度。

```sql
CREATE TABLE chat_background (
    id                   TEXT PRIMARY KEY,              -- 自增主键 ID
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    scope_type           INTEGER NOT NULL,              -- 作用范围类型枚举
    conversation_id      TEXT,                          -- 会话 ID，单聊/群聊/系统会话的唯一标识
    background_type      INTEGER NOT NULL,              -- 背景类型枚举
    local_path           TEXT,                          -- 本地文件路径
    remote_url           TEXT,                          -- 远程资源地址
    color_value          TEXT,                          -- 颜色值
    blur_enabled         INTEGER DEFAULT 0,             -- 是否开启模糊效果，0 否 1 是
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);

CREATE INDEX idx_background_scope ON chat_background(user_id, scope_type, conversation_id);
```

`scope_type`：

| 值 | 含义 |
|---|---|
| 1 | 全局默认背景 |
| 2 | 单个会话背景 |
| 3 | 群聊背景 |

`background_type`：

| 值 | 含义 |
|---|---|
| 1 | 纯色 |
| 2 | 本地图片 |
| 3 | 远程图片 |
| 4 | 系统内置背景 |

---

### 18.8 群公告表 top_notice

群公告建议独立存储，不要只塞在群信息 JSON 里。

```sql
CREATE TABLE top_notice (
    notice_id            TEXT PRIMARY KEY,              -- 公告 ID
    conversation_id      TEXT NOT NULL,                 -- 会话 ID，单聊/群聊/系统会话的唯一标识
    operator_id          TEXT NOT NULL,                 -- 操作者用户 ID
    title                TEXT,                          -- 标题
    content              TEXT NOT NULL,                 -- 正文内容
    notice_type          INTEGER DEFAULT 1,             -- 公告类型枚举
    is_pinned            INTEGER DEFAULT 1,             -- 是否置顶，0 否 1 是
    version              INTEGER DEFAULT 0,             -- 版本号
    published_at         INTEGER,                       -- 发布时间
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);

CREATE INDEX idx_notice_conversation ON top_notice(conversation_id, published_at DESC);
```

`notice_type`：

| 值 | 含义 |
|---|---|
| 1 | 群公告 |
| 2 | 置顶公告 |
| 3 | 系统公告 |
| 4 | 活动公告 |

---

### 18.9 消息置顶表 message_pin

置顶消息建议单独做表，不要改消息本身。一个会话可以有多条置顶消息。

```sql
CREATE TABLE message_pin (
    pin_id               TEXT PRIMARY KEY,              -- 置顶记录 ID
    conversation_id      TEXT NOT NULL,                 -- 会话 ID，单聊/群聊/系统会话的唯一标识
    message_id           TEXT NOT NULL,                 -- 消息 ID，本地全局唯一
    operator_id          TEXT NOT NULL,                 -- 操作者用户 ID
    pin_text             TEXT,                          -- 置顶展示文案
    sort_order           INTEGER DEFAULT 0,             -- 排序值，越小越靠前
    pinned_at            INTEGER NOT NULL,              -- 置顶时间
    is_deleted           INTEGER DEFAULT 0,             -- 是否逻辑删除，0 否 1 是
    extra_json           TEXT                           -- 扩展字段，存放暂未结构化的业务数据
);

CREATE INDEX idx_pin_conversation ON message_pin(conversation_id, is_deleted, sort_order, pinned_at DESC);
CREATE UNIQUE INDEX idx_pin_message ON message_pin(conversation_id, message_id);
```

---

### 18.10 消息编辑历史 message_edit_history

如果支持“已发送消息可编辑”，建议保留编辑历史。

```sql
CREATE TABLE message_edit_history (
    history_id           TEXT PRIMARY KEY,              -- 编辑历史 ID
    message_id           TEXT NOT NULL,                 -- 消息 ID，本地全局唯一
    editor_id            TEXT NOT NULL,                 -- 编辑者用户 ID
    old_content_json     TEXT,                          -- 编辑前内容 JSON
    new_content_json     TEXT,                          -- 编辑后内容 JSON
    edit_version         INTEGER NOT NULL,              -- 消息编辑版本号
    edited_at            INTEGER NOT NULL               -- 编辑时间
);

CREATE INDEX idx_edit_history_message ON message_edit_history(message_id, edit_version DESC);
```

同时 `message` 主表里可以保留：

```sql
ALTER TABLE message ADD COLUMN edit_version INTEGER DEFAULT 0;
ALTER TABLE message ADD COLUMN edited_at INTEGER;
```

---

### 18.11 多端同步状态 device_sync_state

手机、平板、电脑、网页端同时在线时，需要记录设备维度同步状态。

```sql
CREATE TABLE device_sync_state (
    device_id            TEXT PRIMARY KEY,              -- 设备 ID
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    device_name          TEXT,                          -- 设备名称
    device_type          INTEGER,                       -- 设备类型枚举
    platform             TEXT,                          -- 平台名称
    last_online_at       INTEGER,                       -- 最近在线时间
    last_sync_seq        INTEGER DEFAULT 0,             -- 最近同步到的消息序号
    last_sync_cursor     TEXT,                          -- 最近同步游标
    push_enabled         INTEGER DEFAULT 1,             -- 是否开启推送
    is_current_device    INTEGER DEFAULT 0,             -- 是否当前设备
    is_trusted           INTEGER DEFAULT 0,             -- 是否可信设备
    extra_json           TEXT,                          -- 扩展字段，存放暂未结构化的业务数据
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);

CREATE INDEX idx_device_user ON device_sync_state(user_id, last_online_at DESC);
```

`device_type`：

| 值 | 含义 |
|---|---|
| 1 | iPhone |
| 2 | Android |
| 3 | iPad |
| 4 | Mac |
| 5 | Windows |
| 6 | Web |
| 7 | HarmonyOS |

---

### 18.12 隐私设置 privacy_setting

隐私配置建议按 key-value 存，这样未来扩展更容易。

```sql
CREATE TABLE privacy_setting (
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    setting_key          TEXT NOT NULL,                 -- 设置项 key
    setting_value        TEXT,                          -- 设置项值
    value_type           INTEGER DEFAULT 1,             -- 值类型枚举，例如字符串/布尔/数字
    updated_at           INTEGER,                       -- 更新时间，Unix 毫秒时间戳
    PRIMARY KEY(user_id, setting_key)
);
```

常见 `setting_key`：

| key | 说明 |
|---|---|
| `allow_add_by_phone` | 是否允许通过手机号添加 |
| `allow_add_by_wxid` | 是否允许通过微信号添加 |
| `allow_add_by_group` | 是否允许通过群聊添加 |
| `show_moments_to_stranger` | 是否允许陌生人查看朋友圈范围 |
| `read_receipt_enabled` | 是否开启已读回执 |
| `typing_indicator_enabled` | 是否显示“正在输入” |
| `profile_visible_scope` | 资料可见范围 |

---

### 18.13 通知设置 notification_setting

通知设置可以分全局和会话级。全局可以用独立表，会话级也可以放进 `conversation_setting`。

```sql
CREATE TABLE notification_setting (
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    scope_type           INTEGER NOT NULL,              -- 作用范围类型枚举
    conversation_id      TEXT,                          -- 会话 ID，单聊/群聊/系统会话的唯一标识
    mute_enabled         INTEGER DEFAULT 0,             -- 是否免打扰
    preview_enabled      INTEGER DEFAULT 1,             -- 是否显示通知预览
    sound_enabled        INTEGER DEFAULT 1,             -- 是否开启声音
    vibration_enabled    INTEGER DEFAULT 1,             -- 是否开启震动
    badge_enabled        INTEGER DEFAULT 1,             -- 是否显示角标
    do_not_disturb_start TEXT,                          -- 勿扰开始时间，例如 22:00
    do_not_disturb_end   TEXT,                          -- 勿扰结束时间，例如 08:00
    updated_at           INTEGER,                       -- 更新时间，Unix 毫秒时间戳
    PRIMARY KEY(user_id, scope_type, conversation_id)
);
```

`scope_type`：

| 值 | 含义 |
|---|---|
| 1 | 全局 |
| 2 | 单聊 |
| 3 | 群聊 |
| 4 | 公众号/服务号 |

---

### 18.14 黑名单 blacklist

```sql
CREATE TABLE blacklist (
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    blocked_user_id      TEXT NOT NULL,                 -- 被拉黑用户 ID
    reason               TEXT,                          -- 原因说明
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER,                       -- 更新时间，Unix 毫秒时间戳
    PRIMARY KEY(user_id, blocked_user_id)
);
```

---

### 18.15 单会话设置 conversation_setting

会话设置不建议全塞到 `conversation.extra_json`，常用字段可以独立出来。

```sql
CREATE TABLE conversation_setting (
    conversation_id      TEXT PRIMARY KEY,              -- 会话 ID，单聊/群聊/系统会话的唯一标识
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    is_pinned            INTEGER DEFAULT 0,             -- 是否置顶，0 否 1 是
    is_muted             INTEGER DEFAULT 0,             -- 是否免打扰，0 否 1 是
    is_archived          INTEGER DEFAULT 0,             -- 是否归档，0 否 1 是
    show_member_name     INTEGER DEFAULT 0,             -- 群聊是否显示成员昵称
    save_to_contacts     INTEGER DEFAULT 0,             -- 是否保存到通讯录
    input_draft_enabled  INTEGER DEFAULT 1,             -- 是否启用输入草稿
    typing_enabled       INTEGER DEFAULT 1,             -- 是否显示正在输入
    background_id        TEXT,                          -- 聊天背景 ID
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);

CREATE INDEX idx_conversation_setting_user ON conversation_setting(user_id, is_pinned, is_muted);
```

`conversation` 主表可以保留冗余字段 `is_pinned`、`is_muted`，用于会话列表快速排序；`conversation_setting` 存更完整的设置。

---

### 18.16 消息本地状态 message_local_state

有些状态只影响本机 UI，不应该同步给服务端。

例如：

- 语音是否已播放
- 长文本是否已展开
- 图片是否查看过原图
- 翻译结果是否展开
- 某条消息的动画是否播放过

```sql
CREATE TABLE message_local_state (
    message_id           TEXT PRIMARY KEY,              -- 消息 ID，本地全局唯一
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    voice_played         INTEGER DEFAULT 0,             -- 语音是否已播放
    original_image_seen  INTEGER DEFAULT 0,             -- 是否查看过原图
    text_expanded        INTEGER DEFAULT 0,             -- 长文本是否已展开
    translate_expanded   INTEGER DEFAULT 0,             -- 翻译结果是否已展开
    effect_played        INTEGER DEFAULT 0,             -- 特效是否已播放
    extra_json           TEXT,                          -- 扩展字段，存放暂未结构化的业务数据
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);
```

---

### 18.17 消息翻译缓存 message_translate

如果支持消息翻译，结果应该缓存，避免重复请求。

```sql
CREATE TABLE message_translate (
    message_id           TEXT NOT NULL,                 -- 消息 ID，本地全局唯一
    source_lang          TEXT,                          -- 源语言
    target_lang          TEXT NOT NULL,                 -- 目标语言
    translated_text      TEXT NOT NULL,                 -- 翻译后的文本
    provider             TEXT,                          -- 服务提供方
    created_at           INTEGER,                       -- 创建时间，Unix 毫秒时间戳
    updated_at           INTEGER,                       -- 更新时间，Unix 毫秒时间戳
    PRIMARY KEY(message_id, target_lang)
);
```

---

### 18.18 数据库迁移元数据 migration_meta

版本迁移建议必须有独立表。

```sql
CREATE TABLE migration_meta (
    key                  TEXT PRIMARY KEY,              -- 元数据 key
    value                TEXT,                          -- 元数据值
    updated_at           INTEGER                        -- 更新时间，Unix 毫秒时间戳
);
```

常见 key：

| key | 说明 |
|---|---|
| `schema_version` | 当前数据库结构版本 |
| `last_migration_id` | 最后执行的迁移 ID |
| `last_vacuum_at` | 最近一次压缩时间 |
| `last_integrity_check_at` | 最近一次完整性检查时间 |
| `fts_rebuild_version` | FTS 索引重建版本 |

---

### 18.19 数据库修复记录 database_repair_log

```sql
CREATE TABLE database_repair_log (
    repair_id            TEXT PRIMARY KEY,              -- 修复记录 ID
    user_id              TEXT NOT NULL,                 -- 当前登录账号或所属用户 ID，用于账号隔离
    database_name        TEXT NOT NULL,                 -- 数据库名称
    repair_type          INTEGER NOT NULL,              -- 修复类型枚举
    result               INTEGER NOT NULL,              -- 修复结果，0 失败 1 成功
    detail               TEXT,                          -- 修复详情
    started_at           INTEGER,                       -- 开始时间
    finished_at          INTEGER                        -- 结束时间
);
```

`repair_type`：

| 值 | 含义 |
|---|---|
| 1 | 完整性检查 |
| 2 | 主库恢复 |
| 3 | 搜索索引重建 |
| 4 | 媒体索引重建 |
| 5 | VACUUM/压缩 |

---

### 18.20 设计建议

这些扩展表可以按重要程度分批实现：

#### 第一阶段必须有

- `conversation_setting`
- `notification_setting`
- `blacklist`
- `migration_meta`
- `device_sync_state`

#### 第二阶段增强体验

- `favorite_item`
- `emoji_store`
- `message_pin`
- `top_notice`
- `chat_background`

#### 第三阶段高级能力

- `favorite_tag`
- `session_tag`
- `message_edit_history`
- `message_translate`
- `database_repair_log`

实际项目里，建议优先保证：

1. 会话设置和会话列表读取快。
2. 收藏、表情、置顶消息不要污染消息主表。
3. 本地 UI 状态不要同步到服务端。
4. 可重建的数据，例如搜索索引、媒体索引、翻译缓存，可以和核心消息数据分库或分表管理。
5. 隐私、黑名单、通知设置要支持多端同步，但本地仍需要缓存一份。

---

## 十九、移动端 IM 数据库设计原则

总结成 8 条：

1. **账号隔离**
2. **会话冗余**
3. **消息头内容分离**
4. **媒体文件落盘，元数据进库**
5. **搜索单独建索引库**
6. **撤回/删除优先状态化，不直接物理删除**
7. **同步基于 cursor/seq**
8. **整库加密 + 安全密钥管理**

---

## 二十、iOS/WCDB/SQLite 实现建议

### Swift 层模型建议

```swift
enum MessageType: Int {
    case text = 1
    case image = 2
    case voice = 3
    case video = 4
    case file = 5
    case contactCard = 6
    case location = 7
    case system = 8
    case revoked = 9
    case emoji = 10
    case quote = 11
    case card = 12
    case call = 13
}
```

```swift
enum MessageSendStatus: Int {
    case pending = 0
    case sending = 1
    case success = 2
    case failed = 3
}
```

```swift
enum ConversationType: Int {
    case single = 1
    case group = 2
    case system = 3
    case service = 4
}
```

---

## 二十一、消息入库事务示例

伪代码：

```swift
func insertIncomingMessage(_ message: Message) throws {
    try database.run(transaction: {
        try messageDAO.insert(message)
        try contentDAO.insertContentIfNeeded(message.content)
        try conversationDAO.updateLastMessage(
            conversationID: message.conversationID,
            lastMessageID: message.messageID,
            digest: message.digest,
            time: message.serverTime ?? message.localTime
        )
        try conversationDAO.increaseUnreadCountIfNeeded(message)
    })
}
```

核心原则：

- 消息写入
- 内容写入
- 会话摘要更新
- 未读数更新

这几个动作要在同一个事务中完成。

---

## 二十二、结论

如果讨论真实微信数据库：

- 微信使用 WCDB 是公开可确认的。
- WCDB 基于 SQLite 和 SQLCipher。
- 微信真实完整表结构没有官方公开。
- 网上大量表结构来自逆向或取证分析，不能当作官方设计文档。

如果是自研“微信级 IM 数据库”：

- 推荐使用账号隔离。
- 主库、搜索库、文件索引库分离。
- 消息采用“消息头表 + 内容分表”。
- 会话表冗余最后一条消息和未读数。
- 媒体文件落磁盘，数据库只存元数据。
- 撤回、删除、同步都应状态化设计。
- 大表分页使用游标，不要深 OFFSET。
- 加密、安全、迁移、修复能力要从一开始纳入设计。

