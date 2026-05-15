import DiffableSnapshotKit
import UIKit

/// 单个教学案例详情页。
///
/// 详情页把示例代码和 planner 输出放在同一个 UIKit list 中，方便学习者对照
/// “输入代码”和“计划结果”。
@MainActor
final class DemoScenarioViewController: UIViewController {
    private typealias DataSource = UICollectionViewDiffableDataSource<DemoDetailSection, DemoDetailItem>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<DemoDetailSection, DemoDetailItem>

    private let scenario: DemoScenario
    private var collectionView: UICollectionView!
    private var dataSource: DataSource!

    init(scenario: DemoScenario) {
        self.scenario = scenario
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = scenario.title
        view.backgroundColor = .systemGroupedBackground
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    private func configureCollectionView() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
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
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, DemoDetailItem> { cell, _, item in
            var content = UIListContentConfiguration.subtitleCell()
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            content.secondaryTextProperties.color = .secondaryLabel

            switch item {
            case let .summary(text):
                content.text = text
                content.secondaryText = nil
                content.image = UIImage(systemName: "info.circle")
            case let .code(code):
                content.text = code
                content.textProperties.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                content.secondaryText = "真实项目里把 oldRows/newRows 换成你的 ViewState rows。"
                content.image = UIImage(systemName: "chevron.left.forwardslash.chevron.right")
            case let .planField(_, title, value):
                content.text = title
                content.secondaryText = value
                content.image = UIImage(systemName: "doc.text")
            case let .sectionHeader(text):
                content.text = text
                content.secondaryText = nil
                content.image = UIImage(systemName: "rectangle.stack")
            }

            cell.contentConfiguration = content
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let section = self?.dataSource.snapshot().sectionIdentifiers[safe: indexPath.section] else {
                return
            }

            var content = UIListContentConfiguration.groupedHeader()
            content.text = section.title
            header.contentConfiguration = content
        }

        dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func applySnapshot() {
        var snapshot = Snapshot()
        snapshot.appendSections(DemoDetailSection.allCases)
        snapshot.appendItems([.summary(scenario.summary)], toSection: .summary)
        snapshot.appendItems([.code(scenario.code)], toSection: .code)
        snapshot.appendItems(planItems(from: scenario.plan), toSection: .plan)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func planItems(from plan: DiffableSnapshotPlan<String, String>) -> [DemoDetailItem] {
        var items: [DemoDetailItem] = [
            .planField(id: "plan.operation", title: "operation", value: "\(plan.operation)"),
            .planField(id: "plan.insertedSectionIDs", title: "insertedSectionIDs", value: plan.insertedSectionIDs.description),
            .planField(id: "plan.deletedSectionIDs", title: "deletedSectionIDs", value: plan.deletedSectionIDs.description),
            .planField(id: "plan.keptSectionIDs", title: "keptSectionIDs", value: plan.keptSectionIDs.description)
        ]

        for (index, sectionPlan) in plan.sectionPlans.enumerated() {
            let fieldIDPrefix = "section.\(index).\(sectionPlan.sectionID)"
            items.append(.sectionHeader("section: \(sectionPlan.sectionID)"))
            // `UICollectionViewDiffableDataSource` 要求 item identifier 在整个 snapshot 中唯一。
            // 根计划和每个 section plan 都有 `operation` 字段，title/value 可能完全相同；
            // 因此这里用稳定的字段路径作为身份标识，title/value 只负责展示。
            items.append(.planField(id: "\(fieldIDPrefix).operation", title: "operation", value: "\(sectionPlan.operation)"))
            items.append(.planField(id: "\(fieldIDPrefix).deletedItemIDs", title: "deletedItemIDs", value: sectionPlan.deletedItemIDs.description))
            items.append(.planField(id: "\(fieldIDPrefix).prependedItemIDs", title: "prependedItemIDs", value: sectionPlan.prependedItemIDs.description))
            items.append(.planField(id: "\(fieldIDPrefix).appendedItemIDs", title: "appendedItemIDs", value: sectionPlan.appendedItemIDs.description))
            items.append(.planField(id: "\(fieldIDPrefix).reloadedItemIDs", title: "reloadedItemIDs", value: sectionPlan.reloadedItemIDs.description))
            items.append(.planField(id: "\(fieldIDPrefix).reconfiguredItemIDs", title: "reconfiguredItemIDs", value: sectionPlan.reconfiguredItemIDs.description))
        }

        return items
    }
}
