import DiffableSnapshotKit
import UIKit

/// 聊天消息增量更新模拟页。
///
/// 这个页面使用真实的 `UICollectionViewDiffableDataSource`，把
/// `DiffableSnapshotPlanner` 输出转换成 UIKit snapshot 操作。所有模拟动作都通过右上角
/// `模拟` 菜单触发，方便观察 append、prepend、reconfigure、reload 和 rebuild 的区别。
@MainActor
final class ChatSimulationViewController: UIViewController {
    private typealias SectionID = String
    private typealias ItemID = String
    private typealias DataSource = UICollectionViewDiffableDataSource<SectionID, ItemID>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<SectionID, ItemID>

    private let sectionID = "messages"
    private var rows: [ChatSimulationRow] = []
    private var rowsByID: [ItemID: ChatSimulationRow] = [:]
    private var nextMessageIndex = 4
    private var nextHistoryIndex = 1
    private var collectionView: UICollectionView!
    private var dataSource: DataSource!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "模拟聊天消息"
        view.backgroundColor = .systemGroupedBackground
        configureSimulationMenu()
        configureCollectionView()
        configureDataSource()
        applyInitialMessages()
    }

    private func configureSimulationMenu() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "模拟",
            image: UIImage(systemName: "ellipsis.circle"),
            primaryAction: nil,
            menu: makeSimulationMenu()
        )
    }

    private func makeSimulationMenu() -> UIMenu {
        UIMenu(
            title: "消息更新动作",
            image: UIImage(systemName: "message.badge"),
            children: [
                UIAction(title: "接收新消息", image: UIImage(systemName: "arrow.down.message")) { [weak self] _ in
                    self?.appendIncomingMessage()
                },
                UIAction(title: "发送新消息", image: UIImage(systemName: "paperplane")) { [weak self] _ in
                    self?.appendOutgoingMessage()
                },
                UIAction(title: "加载历史消息", image: UIImage(systemName: "clock.arrow.circlepath")) { [weak self] _ in
                    self?.prependHistoryMessage()
                },
                UIAction(title: "更新已读状态", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                    self?.markLastOutgoingMessageRead()
                },
                UIAction(title: "撤回最后一条普通消息", image: UIImage(systemName: "arrow.uturn.backward.circle")) { [weak self] _ in
                    self?.revokeLastNormalMessage()
                },
                UIAction(title: "中间插入测试", image: UIImage(systemName: "exclamationmark.triangle")) { [weak self] _ in
                    self?.insertMiddleMessageForRebuild()
                }
            ]
        )
    }

    private func configureCollectionView() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.showsSeparators = true
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        view.addSubview(collectionView)
        self.collectionView = collectionView

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ItemID> { [weak self] cell, _, itemID in
            guard let row = self?.rowsByID[itemID] else {
                return
            }

            var content = UIListContentConfiguration.subtitleCell()
            content.text = row.text
            content.secondaryText = row.detailText
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.numberOfLines = 0
            content.image = UIImage(systemName: row.imageName)

            if row.cellKind == .revoked {
                content.textProperties.color = .secondaryLabel
                content.textProperties.font = .italicSystemFont(ofSize: 16)
            }

            cell.contentConfiguration = content
        }

        dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, itemID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemID)
        }
    }

    private func applyInitialMessages() {
        let initialRows = [
            ChatSimulationRow(id: "message_1", text: "你好，这是第一条消息", sender: .other, status: .received, cellKind: .normal),
            ChatSimulationRow(id: "message_2", text: "这条消息稍后可以被撤回", sender: .me, status: .sent, cellKind: .normal),
            ChatSimulationRow(id: "message_3", text: "右上角菜单可以触发增量更新", sender: .other, status: .received, cellKind: .normal)
        ]

        rows = initialRows
        rebuildRowsByID()

        var snapshot = Snapshot()
        snapshot.appendSections([sectionID])
        snapshot.appendItems(initialRows.map(\.id), toSection: sectionID)
        dataSource.apply(snapshot, animatingDifferences: false)
        navigationItem.prompt = "初始完整 snapshot"
    }

    private func appendIncomingMessage() {
        let newRow = ChatSimulationRow(
            id: "message_\(nextMessageIndex)",
            text: "收到一条新消息 \(nextMessageIndex)",
            sender: .other,
            status: .received,
            cellKind: .normal
        )
        nextMessageIndex += 1
        applyRows(rows + [newRow])
    }

    private func appendOutgoingMessage() {
        let newRow = ChatSimulationRow(
            id: "message_\(nextMessageIndex)",
            text: "我发送了一条新消息 \(nextMessageIndex)",
            sender: .me,
            status: .sent,
            cellKind: .normal
        )
        nextMessageIndex += 1
        applyRows(rows + [newRow])
    }

    private func prependHistoryMessage() {
        let newRow = ChatSimulationRow(
            id: "history_\(nextHistoryIndex)",
            text: "更早的历史消息 \(nextHistoryIndex)",
            sender: nextHistoryIndex.isMultiple(of: 2) ? .me : .other,
            status: .received,
            cellKind: .normal
        )
        nextHistoryIndex += 1
        applyRows([newRow] + rows)
    }

    private func markLastOutgoingMessageRead() {
        guard let index = rows.lastIndex(where: { $0.sender == .me && $0.cellKind == .normal }) else {
            return
        }

        var newRows = rows
        let oldRow = newRows[index]
        newRows[index] = ChatSimulationRow(
            id: oldRow.id,
            text: oldRow.text,
            sender: oldRow.sender,
            status: .read,
            cellKind: oldRow.cellKind
        )
        applyRows(newRows)
    }

    private func revokeLastNormalMessage() {
        guard let index = rows.lastIndex(where: { $0.cellKind == .normal }) else {
            return
        }

        var newRows = rows
        let oldRow = newRows[index]
        newRows[index] = ChatSimulationRow(
            id: oldRow.id,
            text: "\(oldRow.sender.displayName)撤回了一条消息",
            sender: oldRow.sender,
            status: oldRow.status,
            cellKind: .revoked
        )
        applyRows(newRows)
    }

    private func insertMiddleMessageForRebuild() {
        guard rows.count > 1 else {
            return
        }

        let newRow = ChatSimulationRow(
            id: "middle_\(nextMessageIndex)",
            text: "这条消息插入到中间，会触发 rebuild",
            sender: .other,
            status: .received,
            cellKind: .normal
        )
        nextMessageIndex += 1

        var newRows = rows
        newRows.insert(newRow, at: 1)
        applyRows(newRows)
    }

    /// 根据新的消息数组生成并应用 diffable snapshot 更新计划。
    ///
    /// 这个方法是 Demo 里最接近真实业务接入的位置：实际项目中通常会在
    /// `ViewModel` 输出新的消息 `ViewState` 后，把旧状态和新状态交给
    /// `DiffableSnapshotPlanner`，再由 UIKit adapter 执行返回的计划。
    ///
    /// 使用示例：
    ///
    /// ```swift
    /// let nextRows = rows + [newMessageRow]
    /// applyRows(nextRows)
    /// ```
    ///
    /// 上面的追加场景会生成 `.incremental` 计划；如果只是消息已读状态变化，会进入
    /// `.reconfigure`；如果普通消息变成撤回提示消息，会进入 `.reload`。
    private func applyRows(_ newRows: [ChatSimulationRow]) {
        // 同一个 item ID 的旧值和新值都存在时，才需要判断刷新方式。
        // 新增 item 会在插入时通过 cell provider 完整配置，不需要 reconfigure/reload；
        // 删除 item 已经不在 snapshot 中，继续刷新会违反 UIKit diffable 的前置条件。
        let refreshActions = DiffableChangedItemDetector.refreshActions(
            previousItems: rows,
            currentItems: newRows,
            id: \.id
        ) { oldRow, newRow in
            // Cell 类型不变时只刷新内容即可，使用 reconfigure 可以保留 cell 实例并减少布局成本。
            // Cell 类型变化时必须 reload，例如“普通消息 Cell”变成“撤回提示 Cell”时，
            // UIKit 需要重新走 cell registration / cell provider，才能换成正确展示形态。
            oldRow.cellKind == newRow.cellKind ? .reconfigure : .reload
        }

        // Planner 只接收稳定标识符顺序，不持有 UIKit 对象，因此可以作为纯值逻辑测试。
        // 这里的 section 固定为 messages；真实项目可以把联系人、消息日期分组等 section
        // 一并传入，planner 会独立计算每个 section 的 item 增量。
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [
                .section(sectionID, rows.map(\.id))
            ],
            currentSections: [
                .section(sectionID, newRows.map(\.id))
            ],
            refreshActionsByItemID: refreshActions
        )

        rows = newRows
        rebuildRowsByID()
        apply(plan: plan, currentRows: newRows)
        navigationItem.prompt = "上次操作: \(plan.operation.displayText)"
    }

    /// 把 `DiffableSnapshotPlanner` 的纯值计划转换为 UIKit snapshot 操作。
    ///
    /// `DiffableSnapshotKit` 刻意不直接依赖 UIKit；这样 planner 可以复用于 UIKit、
    /// SwiftUI 包装控制器、命令行测试或其他项目。接入 UIKit 时，只需要在这一层把
    /// `DiffableSectionPlan` 翻译成 `NSDiffableDataSourceSnapshot` 的增删改调用。
    ///
    /// 使用示例：
    ///
    /// ```swift
    /// let plan = DiffableSnapshotPlanner.plan(
    ///     previousSections: oldSections,
    ///     currentSections: newSections,
    ///     refreshActionsByItemID: refreshActions
    /// )
    /// apply(plan: plan, currentRows: newRows)
    /// ```
    ///
    /// 推荐应用顺序是：删 item、删 section、加 section、加 item、reload、reconfigure。
    /// 当前 Demo 只有一个固定 section，所以这里只演示 item 级别的增删改；未来封装通用
    /// UIKit adapter 时，应把 section 增删也放进同一顺序中。
    private func apply(
        plan: DiffableSnapshotPlan<SectionID, ItemID>,
        currentRows: [ChatSimulationRow]
    ) {
        switch plan.operation {
        case .none:
            return
        case .rebuild:
            // section 顺序变化、item 中间插入或既有 item 重排时，增量操作很容易和
            // UIKit 内部 diff 冲突。planner 在这些场景返回 rebuild，让 adapter 直接用
            // 新状态重建 snapshot，优先保证 UI 正确性。
            var snapshot = Snapshot()
            snapshot.appendSections([sectionID])
            snapshot.appendItems(currentRows.map(\.id), toSection: sectionID)
            dataSource.apply(snapshot, animatingDifferences: true)
        case .incremental:
            var snapshot = dataSource.snapshot()

            for sectionPlan in plan.sectionPlans {
                // 先删除已经消失的 item，避免后续 reload/reconfigure 命中不存在的标识符。
                snapshot.deleteItems(sectionPlan.deletedItemIDs)

                if !sectionPlan.prependedItemIDs.isEmpty {
                    // 顶部插入是聊天加载历史消息的常见路径。只要既有 item 顺序没变，
                    // 就可以安全地插到第一个当前 item 前面，不需要 rebuild。
                    let currentItems = snapshot.itemIdentifiers(inSection: sectionPlan.sectionID)
                    if let firstItem = currentItems.first {
                        snapshot.insertItems(sectionPlan.prependedItemIDs, beforeItem: firstItem)
                    } else {
                        snapshot.appendItems(sectionPlan.prependedItemIDs, toSection: sectionPlan.sectionID)
                    }
                }

                if !sectionPlan.appendedItemIDs.isEmpty {
                    // 底部追加对应收发新消息。新增 item 不需要额外刷新，因为 append 后
                    // data source 会为它创建或配置 cell。
                    snapshot.appendItems(sectionPlan.appendedItemIDs, toSection: sectionPlan.sectionID)
                }

                // reload 放在 reconfigure 前面：reload 代表 cell 类型可能变化，需要完整重建；
                // reconfigure 只更新内容，适合已读状态、昵称、时间等轻量变化。
                snapshot.reloadItems(sectionPlan.reloadedItemIDs)
                snapshot.reconfigureItems(sectionPlan.reconfiguredItemIDs)
            }

            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }

    private func rebuildRowsByID() {
        rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }
}

/// 模拟聊天消息行。
private struct ChatSimulationRow: Equatable, Identifiable, Sendable {
    let id: String
    let text: String
    let sender: ChatSimulationSender
    let status: ChatSimulationStatus
    let cellKind: ChatSimulationCellKind

    var detailText: String {
        "\(sender.displayName) · \(status.displayName) · \(cellKind.displayName)"
    }

    var imageName: String {
        switch (sender, cellKind) {
        case (_, .revoked):
            return "arrow.uturn.backward.circle"
        case (.me, .normal):
            return "person.crop.circle.fill"
        case (.other, .normal):
            return "bubble.left.fill"
        }
    }
}

private enum ChatSimulationSender: Equatable, Sendable {
    case me
    case other

    var displayName: String {
        switch self {
        case .me:
            return "我"
        case .other:
            return "对方"
        }
    }
}

private enum ChatSimulationStatus: Equatable, Sendable {
    case sent
    case received
    case read

    var displayName: String {
        switch self {
        case .sent:
            return "已发送"
        case .received:
            return "已接收"
        case .read:
            return "已读"
        }
    }
}

private enum ChatSimulationCellKind: Equatable, Sendable {
    case normal
    case revoked

    var displayName: String {
        switch self {
        case .normal:
            return "普通消息 Cell"
        case .revoked:
            return "撤回提示 Cell"
        }
    }
}

private extension DiffableSnapshotOperation where SectionIdentifier == String {
    var displayText: String {
        switch self {
        case .none:
            return "none"
        case .incremental:
            return "incremental"
        case let .rebuild(reason):
            return "rebuild(\(reason))"
        }
    }
}
