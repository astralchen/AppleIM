import UIKit

/// Demo 首页。
///
/// 首页自身也使用 `UICollectionViewDiffableDataSource`，让学习者看到 UIKit 项目里
/// 最常见的列表组织方式。这个页面只负责教学导航，真正的 planner 输出在详情页展示。
@MainActor
final class DemoHomeViewController: UIViewController {
    private typealias DataSource = UICollectionViewDiffableDataSource<DemoHomeSection, DemoHomeItem>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<DemoHomeSection, DemoHomeItem>

    private let scenarios = DemoScenarioFactory.scenarios()
    private var scenariosByID: [String: DemoScenario] = [:]
    private var collectionView: UICollectionView!
    private var dataSource: DataSource!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "DiffableSnapshotKit"
        view.backgroundColor = .systemGroupedBackground
        scenariosByID = Dictionary(uniqueKeysWithValues: scenarios.map { ($0.id, $0) })
        configureFeatureMenu()
        configureCollectionView()
        configureDataSource()
        applyInitialSnapshot()
    }

    private func configureFeatureMenu() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "功能",
            image: UIImage(systemName: "ellipsis.circle"),
            primaryAction: nil,
            menu: makeFeatureMenu()
        )
    }

    private func makeFeatureMenu() -> UIMenu {
        let scenarioActions = scenarios.map { scenario in
            UIAction(
                title: scenario.title,
                subtitle: scenario.summary,
                image: UIImage(systemName: "list.bullet.rectangle")
            ) { [weak self] _ in
                self?.openScenario(id: scenario.id)
            }
        }

        return UIMenu(
            title: "DiffableSnapshotKit 功能",
            image: UIImage(systemName: "square.stack.3d.up"),
            children: [
                UIAction(
                    title: "模拟聊天消息",
                    subtitle: "用菜单触发消息 append、prepend、reconfigure、reload 和 rebuild。",
                    image: UIImage(systemName: "message.badge")
                ) { [weak self] _ in
                    self?.openChatSimulation()
                },
                UIMenu(
                    title: "计划案例",
                    options: .displayInline,
                    children: scenarioActions
                )
            ]
        )
    }

    private func openChatSimulation() {
        navigationController?.pushViewController(ChatSimulationViewController(), animated: true)
    }

    private func openScenario(id scenarioID: String) {
        guard let scenario = scenariosByID[scenarioID] else {
            return
        }

        navigationController?.pushViewController(
            DemoScenarioViewController(scenario: scenario),
            animated: true
        )
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
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, DemoHomeItem> { cell, _, item in
            var content = UIListContentConfiguration.subtitleCell()
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.numberOfLines = 0

            switch item {
            case let .step(index, title, detail):
                content.text = "\(index). \(title)"
                content.secondaryText = detail
                content.image = UIImage(systemName: "number.circle.fill")
                cell.accessories = []
            case let .adapterOrder(text):
                content.text = text
                content.secondaryText = "未来 UIKit adapter 建议按这个顺序应用计划。"
                content.image = UIImage(systemName: "arrow.down.doc")
                cell.accessories = []
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

    private func applyInitialSnapshot() {
        var snapshot = Snapshot()
        snapshot.appendSections(DemoHomeSection.allCases)
        snapshot.appendItems([
            .step(1, "整理旧状态和新状态", "把 ViewState 中的 section 和 item ID 顺序整理成 DiffableSnapshotSection。"),
            .step(2, "判断同 ID 刷新方式", "Cell 类型不变用 reconfigure；Cell 类型变化用 reload。"),
            .step(3, "从右上角功能菜单触发功能", "模拟聊天消息可直接观察增量更新；计划案例可查看 planner 输出。"),
            .step(4, "生成计划并交给 UIKit adapter", "Package 只输出纯值计划，不直接调用 UICollectionViewDiffableDataSource。")
        ], toSection: .steps)
        snapshot.appendItems([
            .adapterOrder("删 item -> 删 section -> 加 section -> 加 item -> reloadItems -> reconfigureItems")
        ], toSection: .adapterOrder)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}
