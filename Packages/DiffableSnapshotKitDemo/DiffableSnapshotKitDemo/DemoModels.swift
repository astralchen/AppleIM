import DiffableSnapshotKit

/// Demo 中用于表示聊天消息行的值类型。
///
/// 真实项目里这类类型通常来自 ViewState。`id` 是 diffable data source 的
/// item identifier，`cellKind` 表示 cell provider 后续会选择的 cell 类型。
struct DemoMessageRow: Equatable, Identifiable, Sendable {
    let id: String
    let text: String
    let cellKind: DemoMessageCellKind
}

/// Demo 中用于判断消息应该使用哪一种 cell 的枚举。
enum DemoMessageCellKind: String, Equatable, Sendable {
    case text = "文本 Cell"
    case revoked = "撤回提示 Cell"
}

/// Demo 中用于表示联系人行的值类型。
struct DemoContactRow: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
}

/// 一个可展示的教学案例。
struct DemoScenario: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let code: String
    let plan: DiffableSnapshotPlan<String, String>
}

/// Demo 数据工厂。
///
/// 所有案例都只做纯值计算，刻意不封装 UIKit adapter。学习者可以先理解 planner 的
/// 输入和输出，再把这些输出映射到自己的 `UICollectionViewDiffableDataSource`。
enum DemoScenarioFactory {
    static func scenarios() -> [DemoScenario] {
        [
            messageAppendAndRevoke(),
            contactSectionChange(),
            middleInsertionRebuild()
        ]
    }

    /// 演示聊天消息底部追加，以及同 ID 消息从普通文本变成撤回提示。
    private static func messageAppendAndRevoke() -> DemoScenario {
        let oldRows = [
            DemoMessageRow(id: "message_1", text: "你好", cellKind: .text),
            DemoMessageRow(id: "message_2", text: "这条消息稍后会撤回", cellKind: .text)
        ]
        let newRows = [
            DemoMessageRow(id: "message_1", text: "你好", cellKind: .text),
            DemoMessageRow(id: "message_2", text: "你撤回了一条消息", cellKind: .revoked),
            DemoMessageRow(id: "message_3", text: "新的底部消息", cellKind: .text)
        ]

        let refreshActions = DiffableChangedItemDetector.refreshActions(
            previousItems: oldRows,
            currentItems: newRows,
            id: \.id
        ) { oldRow, newRow in
            oldRow.cellKind == newRow.cellKind ? .reconfigure : .reload
        }

        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [
                .section("messages", oldRows.map(\.id))
            ],
            currentSections: [
                .section("messages", newRows.map(\.id))
            ],
            refreshActionsByItemID: refreshActions
        )

        return DemoScenario(
            id: "messageAppendAndRevoke",
            title: "消息追加 + 撤回",
            summary: "底部新增 message_3；message_2 的 ID 不变但 Cell 类型变化，所以进入 reload。",
            code: """
            let refreshActions = DiffableChangedItemDetector.refreshActions(
                previousItems: oldRows,
                currentItems: newRows,
                id: \\.id
            ) { oldRow, newRow in
                oldRow.cellKind == newRow.cellKind ? .reconfigure : .reload
            }

            let plan = DiffableSnapshotPlanner.plan(
                previousSections: [.section("messages", oldRows.map(\\.id))],
                currentSections: [.section("messages", newRows.map(\\.id))],
                refreshActionsByItemID: refreshActions
            )
            """,
            plan: plan
        )
    }

    /// 演示联系人 section 删除、新增，以及同 ID 内容刷新。
    private static func contactSectionChange() -> DemoScenario {
        let oldFriends = [
            DemoContactRow(id: "friend_1", title: "Sondra", subtitle: "在线"),
            DemoContactRow(id: "friend_2", title: "Alex", subtitle: "忙碌")
        ]
        let newFriends = [
            DemoContactRow(id: "friend_1", title: "Sondra", subtitle: "正在输入"),
            DemoContactRow(id: "friend_2", title: "Alex", subtitle: "忙碌")
        ]

        let refreshActions = DiffableChangedItemDetector.refreshActions(
            previousItems: oldFriends,
            currentItems: newFriends,
            id: \.id
        ) { _, _ in
            .reconfigure
        }

        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [
                .section("groups", ["group_1"]),
                .section("friends", oldFriends.map(\.id))
            ],
            currentSections: [
                .section("friends", newFriends.map(\.id)),
                .section("starred", ["friend_1"])
            ],
            refreshActionsByItemID: refreshActions
        )

        return DemoScenario(
            id: "contactSectionChange",
            title: "联系人 Section 变化",
            summary: "groups 被删除，starred 被新增；friend_1 内容变化但 Cell 类型不变，所以进入 reconfigure。",
            code: """
            let plan = DiffableSnapshotPlanner.plan(
                previousSections: [
                    .section("groups", ["group_1"]),
                    .section("friends", oldFriends.map(\\.id))
                ],
                currentSections: [
                    .section("friends", newFriends.map(\\.id)),
                    .section("starred", ["friend_1"])
                ],
                refreshActionsByItemID: refreshActions
            )
            """,
            plan: plan
        )
    }

    /// 演示中间插入无法安全表达为当前增量计划，需要 rebuild。
    private static func middleInsertionRebuild() -> DemoScenario {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [
                .section("messages", ["message_1", "message_3"])
            ],
            currentSections: [
                .section("messages", ["message_1", "message_2", "message_3"])
            ],
            refreshActionsByItemID: [:]
        )

        return DemoScenario(
            id: "middleInsertionRebuild",
            title: "中间插入触发 Rebuild",
            summary: "message_2 插入到既有 item 中间，不属于顶部 prepend 或底部 append，所以 planner 要求 rebuild。",
            code: """
            let plan = DiffableSnapshotPlanner.plan(
                previousSections: [.section("messages", ["message_1", "message_3"])],
                currentSections: [.section("messages", ["message_1", "message_2", "message_3"])],
                refreshActionsByItemID: [:]
            )
            """,
            plan: plan
        )
    }
}

/// Demo 首页的列表分区。
enum DemoHomeSection: Int, CaseIterable, Hashable, Sendable {
    case steps
    case adapterOrder

    var title: String {
        switch self {
        case .steps:
            return "使用步骤"
        case .adapterOrder:
            return "UIKit 接入顺序"
        }
    }
}

/// Demo 首页的列表条目。
enum DemoHomeItem: Hashable, Sendable {
    case step(Int, String, String)
    case adapterOrder(String)
}

/// Demo 详情页的列表分区。
enum DemoDetailSection: Int, CaseIterable, Hashable, Sendable {
    case summary
    case code
    case plan

    var title: String {
        switch self {
        case .summary:
            return "说明"
        case .code:
            return "关键代码"
        case .plan:
            return "Planner 输出"
        }
    }
}

/// Demo 详情页的列表条目。
enum DemoDetailItem: Hashable, Sendable {
    case summary(String)
    case code(String)
    case planField(id: String, title: String, value: String)
    case sectionHeader(String)
}

extension Array {
    /// 安全读取指定位置的元素。
    ///
    /// Demo 的 section header 会根据 `IndexPath.section` 回查当前 snapshot。
    /// UIKit 在快速刷新或边界情况下可能给出已经不再有效的位置，因此这里集中提供一个
    /// 安全下标，避免教学代码被越界保护逻辑打散。
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
