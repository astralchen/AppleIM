/// 描述一个 diffable data source section 及其内部 item 的轻量输入模型。
///
/// 这个类型不依赖 UIKit，调用方只需要提供稳定的 section 标识和 item 标识。
/// 在 UIKit 接入层中，它可以由 `NSDiffableDataSourceSnapshot.sectionIdentifiers`
/// 与业务状态里的 item ID 顺序共同构造。
public struct DiffableSnapshotSection<SectionIdentifier, ItemIdentifier>: Equatable, Sendable
where SectionIdentifier: Hashable & Sendable, ItemIdentifier: Hashable & Sendable {
    /// section 的稳定标识。
    public let id: SectionIdentifier
    /// 当前 section 内 item 的稳定顺序。
    public let itemIDs: [ItemIdentifier]

    /// 创建一个 section 输入值。
    ///
    /// 使用这个初始化方法时，调用方需要显式写出参数名称，适合在生产代码中强调
    /// section 标识和 item 顺序的含义。
    ///
    /// Example:
    /// ```swift
    /// let section = DiffableSnapshotSection(
    ///     id: "messages",
    ///     itemIDs: ["message_1", "message_2"]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - id: section 的稳定标识。
    ///   - itemIDs: 当前 section 内 item 的稳定顺序。
    public init(id: SectionIdentifier, itemIDs: [ItemIdentifier]) {
        self.id = id
        self.itemIDs = itemIDs
    }

    /// 便捷工厂方法，便于测试和调用方用接近 snapshot 的语义构造输入。
    ///
    /// 这个方法主要用于让调用点更短，尤其适合直接传入 planner 的数组字面量。
    ///
    /// Example:
    /// ```swift
    /// let sections: [DiffableSnapshotSection<String, String>] = [
    ///     .section("messages", ["message_1", "message_2"]),
    ///     .section("contacts", ["contact_1"])
    /// ]
    /// ```
    ///
    /// - Parameters:
    ///   - id: section 的稳定标识。
    ///   - itemIDs: 当前 section 内 item 的稳定顺序。
    /// - Returns: 可传给 `DiffableSnapshotPlanner` 的 section 输入值。
    public static func section(
        _ id: SectionIdentifier,
        _ itemIDs: [ItemIdentifier]
    ) -> DiffableSnapshotSection<SectionIdentifier, ItemIdentifier> {
        DiffableSnapshotSection(id: id, itemIDs: itemIDs)
    }
}

/// 同一个 item 标识仍然存在时，需要执行的内容刷新动作。
public enum DiffableItemRefreshAction: Equatable, Sendable {
    /// 仅刷新同一种 cell 类型内部的内容配置。
    ///
    /// 适合文本、时间、进度、已读状态等变化。UIKit 中通常对应
    /// `NSDiffableDataSourceSnapshot.reconfigureItems(_:)`。
    case reconfigure

    /// 重新加载同一个 item，用于 cell 类型或 cell registration 可能变化的场景。
    ///
    /// 例如聊天消息被撤回后，消息 ID 不变，但普通消息 cell 需要替换成撤回提示 cell。
    /// 这类变化不能只做 reconfigure，因为 reconfigure 更偏向复用现有可见 cell 并更新配置；
    /// 如果 cell provider 需要重新选择不同 cell 类型，调用方应在 UIKit 接入层使用 reload。
    case reload
}

/// 整体 snapshot 必须重建的原因。
public enum DiffableSnapshotRebuildReason<SectionIdentifier>: Equatable, Sendable
where SectionIdentifier: Hashable & Sendable {
    /// 首次渲染没有旧 snapshot 可增量比较。
    case initialSnapshot
    /// section 的相对顺序发生变化。
    case sectionOrderChanged
    /// 某个 section 内既有 item 的相对顺序发生变化。
    case itemOrderChanged(sectionID: SectionIdentifier)
    /// 某个 section 内新增 item 出现在中间位置。
    case middleItemInsertion(sectionID: SectionIdentifier)
}

/// 一次整体 snapshot 更新的操作类型。
public enum DiffableSnapshotOperation<SectionIdentifier>: Equatable, Sendable
where SectionIdentifier: Hashable & Sendable {
    /// 无需更新 snapshot。
    case none
    /// 可以按计划执行增量更新。
    case incremental
    /// 不能安全增量更新，需要重建完整 snapshot。
    case rebuild(reason: DiffableSnapshotRebuildReason<SectionIdentifier>)
}

/// 单个 section 内 item 更新的操作类型。
public enum DiffableSectionOperation: Equatable, Sendable {
    /// 当前 section 无需更新。
    case none
    /// 当前 section 只有 reconfigure 刷新。
    case reconfigureOnly
    /// 当前 section 只有 reload 刷新。
    case reloadOnly
    /// 当前 section 同时包含结构变化或多种刷新动作。
    case incremental
}

/// 单个 section 内的 item 更新计划。
///
/// UIKit 接入层可以按照固定顺序应用这些数组：先删除 item，再插入 item，
/// 最后执行 reload 和 reconfigure。新增 item 不需要出现在刷新数组中，
/// 因为它们插入时会自然走 cell provider 创建或配置 cell。
public struct DiffableSectionPlan<SectionIdentifier, ItemIdentifier>: Equatable, Sendable
where SectionIdentifier: Hashable & Sendable, ItemIdentifier: Hashable & Sendable {
    /// 当前 section 的稳定标识。
    public let sectionID: SectionIdentifier
    /// 当前 section 的操作类型摘要。
    public let operation: DiffableSectionOperation
    /// 旧 snapshot 中存在、新 snapshot 中已经不存在的 item。
    public let deletedItemIDs: [ItemIdentifier]
    /// 新 snapshot 顶部插入的 item。
    public let prependedItemIDs: [ItemIdentifier]
    /// 新 snapshot 底部追加的 item。
    public let appendedItemIDs: [ItemIdentifier]
    /// 同 ID、同 cell 类型，只需要刷新内容配置的 item。
    public let reconfiguredItemIDs: [ItemIdentifier]
    /// 同 ID 但 cell 类型或 registration 可能变化，需要重新加载的 item。
    public let reloadedItemIDs: [ItemIdentifier]

    /// 创建一个 section 更新计划。
    ///
    /// 一般业务代码不需要直接创建这个类型，通常由 `DiffableSnapshotPlanner`
    /// 返回。直接初始化更适合测试自定义 adapter 时构造固定输入。
    ///
    /// Example:
    /// ```swift
    /// let plan = DiffableSectionPlan(
    ///     sectionID: "messages",
    ///     operation: .reloadOnly,
    ///     deletedItemIDs: [],
    ///     prependedItemIDs: [],
    ///     appendedItemIDs: [],
    ///     reconfiguredItemIDs: [],
    ///     reloadedItemIDs: ["message_2"]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - sectionID: 当前 section 的稳定标识。
    ///   - operation: 当前 section 的操作类型摘要。
    ///   - deletedItemIDs: 旧 snapshot 中存在、新 snapshot 中已经不存在的 item。
    ///   - prependedItemIDs: 新 snapshot 顶部插入的 item。
    ///   - appendedItemIDs: 新 snapshot 底部追加的 item。
    ///   - reconfiguredItemIDs: 同 ID、同 cell 类型，只需要刷新内容配置的 item。
    ///   - reloadedItemIDs: 同 ID 但 cell 类型或 registration 可能变化，需要重新加载的 item。
    public init(
        sectionID: SectionIdentifier,
        operation: DiffableSectionOperation,
        deletedItemIDs: [ItemIdentifier],
        prependedItemIDs: [ItemIdentifier],
        appendedItemIDs: [ItemIdentifier],
        reconfiguredItemIDs: [ItemIdentifier],
        reloadedItemIDs: [ItemIdentifier]
    ) {
        self.sectionID = sectionID
        self.operation = operation
        self.deletedItemIDs = deletedItemIDs
        self.prependedItemIDs = prependedItemIDs
        self.appendedItemIDs = appendedItemIDs
        self.reconfiguredItemIDs = reconfiguredItemIDs
        self.reloadedItemIDs = reloadedItemIDs
    }
}

/// 一次 diffable snapshot 更新的总计划。
///
/// 这个计划只描述“应该怎么更新”，不直接持有或调用 UIKit 对象。未来接入 UIKit 时，
/// 推荐应用顺序为：删 item、删 section、加 section、加 item、reload、reconfigure。
/// 这个顺序可以避免对已经删除的 item 执行刷新，也能确保新增 section 先存在再插入 item。
public struct DiffableSnapshotPlan<SectionIdentifier, ItemIdentifier>: Equatable, Sendable
where SectionIdentifier: Hashable & Sendable, ItemIdentifier: Hashable & Sendable {
    /// 整体 snapshot 的操作类型摘要。
    public let operation: DiffableSnapshotOperation<SectionIdentifier>
    /// 新 snapshot 中新增的 section。
    public let insertedSectionIDs: [SectionIdentifier]
    /// 旧 snapshot 中存在、新 snapshot 中已经不存在的 section。
    public let deletedSectionIDs: [SectionIdentifier]
    /// 新旧 snapshot 都存在、且 section 顺序未变化的 section。
    public let keptSectionIDs: [SectionIdentifier]
    /// 保留 section 内的 item 更新计划。
    public let sectionPlans: [DiffableSectionPlan<SectionIdentifier, ItemIdentifier>]

    /// 创建一个整体 snapshot 更新计划。
    ///
    /// 一般业务代码不需要直接创建这个类型，通常由 `DiffableSnapshotPlanner`
    /// 返回。直接初始化更适合测试 UIKit adapter 的应用顺序。
    ///
    /// Example:
    /// ```swift
    /// let snapshotPlan = DiffableSnapshotPlan(
    ///     operation: .incremental,
    ///     insertedSectionIDs: ["starred"],
    ///     deletedSectionIDs: ["groups"],
    ///     keptSectionIDs: ["friends"],
    ///     sectionPlans: []
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - operation: 整体 snapshot 的操作类型摘要。
    ///   - insertedSectionIDs: 新 snapshot 中新增的 section。
    ///   - deletedSectionIDs: 旧 snapshot 中存在、新 snapshot 中已经不存在的 section。
    ///   - keptSectionIDs: 新旧 snapshot 都存在、且 section 顺序未变化的 section。
    ///   - sectionPlans: 保留 section 内的 item 更新计划。
    public init(
        operation: DiffableSnapshotOperation<SectionIdentifier>,
        insertedSectionIDs: [SectionIdentifier],
        deletedSectionIDs: [SectionIdentifier],
        keptSectionIDs: [SectionIdentifier],
        sectionPlans: [DiffableSectionPlan<SectionIdentifier, ItemIdentifier>]
    ) {
        self.operation = operation
        self.insertedSectionIDs = insertedSectionIDs
        self.deletedSectionIDs = deletedSectionIDs
        self.keptSectionIDs = keptSectionIDs
        self.sectionPlans = sectionPlans
    }

    /// 查找指定 section 的 item 更新计划。
    ///
    /// 当调用方只关心某个 section 的变化时，可以用这个方法避免手动遍历
    /// `sectionPlans`。新增或删除 section 没有 item 级计划，因此会返回 `nil`。
    ///
    /// Example:
    /// ```swift
    /// if let messagePlan = snapshotPlan.sectionPlan(for: "messages") {
    ///     let itemsNeedingReload = messagePlan.reloadedItemIDs
    /// }
    /// ```
    ///
    /// - Parameter sectionID: 要查询的 section 标识。
    /// - Returns: 如果该 section 保留在新旧 snapshot 中，返回对应计划；否则返回 `nil`。
    public func sectionPlan(for sectionID: SectionIdentifier) -> DiffableSectionPlan<SectionIdentifier, ItemIdentifier>? {
        // sectionPlans 只保存“新旧都存在”的 section；新增或删除 section 没有 item 增量计划。
        sectionPlans.first { $0.sectionID == sectionID }
    }
}

/// 根据新旧 section/item 标识顺序生成 diffable snapshot 更新计划。
public enum DiffableSnapshotPlanner {
    /// 生成一次整体 snapshot 更新计划。
    ///
    /// 这个方法只做纯值计算，不读取 UIKit snapshot，也不会直接调用
    /// `apply(_:animatingDifferences:)`。调用方可以先根据业务 row 的值变化生成
    /// `refreshActionsByItemID`，再把 plan 转换成 UIKit snapshot 操作。
    ///
    /// Example:
    /// ```swift
    /// let plan = DiffableSnapshotPlanner.plan(
    ///     previousSections: [
    ///         .section("messages", ["message_1", "message_2"])
    ///     ],
    ///     currentSections: [
    ///         .section("messages", ["message_1", "message_2", "message_3"])
    ///     ],
    ///     refreshActionsByItemID: [
    ///         "message_2": .reload
    ///     ]
    /// )
    ///
    /// if case .incremental = plan.operation {
    ///     let messagePlan = plan.sectionPlan(for: "messages")
    ///     let appendedIDs = messagePlan?.appendedItemIDs ?? []
    ///     let reloadedIDs = messagePlan?.reloadedItemIDs ?? []
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - previousSections: 上一次已经渲染到 snapshot 的 section 与 item 顺序。
    ///   - currentSections: 本次需要渲染的 section 与 item 顺序。
    ///   - refreshActionsByItemID: 同 ID item 的刷新动作。只会应用到新旧 snapshot 都存在的 item。
    /// - Returns: 可供 UIKit 或其他 diffable 接入层消费的纯值更新计划。
    public static func plan<SectionIdentifier, ItemIdentifier>(
        previousSections: [DiffableSnapshotSection<SectionIdentifier, ItemIdentifier>],
        currentSections: [DiffableSnapshotSection<SectionIdentifier, ItemIdentifier>],
        refreshActionsByItemID: [ItemIdentifier: DiffableItemRefreshAction]
    ) -> DiffableSnapshotPlan<SectionIdentifier, ItemIdentifier>
    where SectionIdentifier: Hashable & Sendable, ItemIdentifier: Hashable & Sendable {
        // 没有旧 snapshot 时，调用方必须创建完整 section/item 树。
        // 这种情况下不存在可复用的旧 item，也就不能安全地产生 reload/reconfigure 计划。
        guard !previousSections.isEmpty else {
            return DiffableSnapshotPlan(
                operation: .rebuild(reason: .initialSnapshot),
                insertedSectionIDs: [],
                deletedSectionIDs: [],
                keptSectionIDs: [],
                sectionPlans: []
            )
        }

        // 先把输入 section 压平为 ID 序列和集合：
        // 序列用于检查稳定顺序，集合用于快速判断新增、删除和保留。
        let previousSectionIDs = previousSections.map(\.id)
        let currentSectionIDs = currentSections.map(\.id)
        let previousSectionSet = Set(previousSectionIDs)
        let currentSectionSet = Set(currentSectionIDs)

        // section 删除/新增属于安全结构变化，可以交给未来 UIKit adapter
        // 依次执行 deleteSections / appendSections 或 insertSections。
        let deletedSectionIDs = previousSectionIDs.filter { !currentSectionSet.contains($0) }
        let insertedSectionIDs = currentSectionIDs.filter { !previousSectionSet.contains($0) }
        let keptSectionIDs = currentSectionIDs.filter { previousSectionSet.contains($0) }

        // Diffable 可以处理 section 增删，但 section 的相对重排会影响大量 indexPath 和补充视图。
        // 为了让调用方得到确定结果，这里要求保留 section 的相对顺序不变；一旦重排就回退完整 snapshot。
        let previousKeptSectionIDs = previousSectionIDs.filter { currentSectionSet.contains($0) }
        guard previousKeptSectionIDs == keptSectionIDs else {
            return DiffableSnapshotPlan(
                operation: .rebuild(reason: .sectionOrderChanged),
                insertedSectionIDs: [],
                deletedSectionIDs: [],
                keptSectionIDs: [],
                sectionPlans: []
            )
        }

        // 后续要按 section ID 找旧 item 顺序；这里转成字典避免每个 section 都线性查找旧输入。
        let previousSectionsByID = Dictionary(uniqueKeysWithValues: previousSections.map { ($0.id, $0) })
        var sectionPlans: [DiffableSectionPlan<SectionIdentifier, ItemIdentifier>] = []

        // section 新增/删除本身就意味着 snapshot 需要应用一次增量；
        // 即使所有保留 section 内部都无变化，整体 operation 也不能返回 .none。
        var hasIncrementalChange = !insertedSectionIDs.isEmpty || !deletedSectionIDs.isEmpty

        for currentSection in currentSections where previousSectionSet.contains(currentSection.id) {
            // 循环只处理保留 section；新增 section 的 item 会随 section 一起进入完整 section 内容，
            // 删除 section 的 item 会随 section 删除，不需要单独生成 item 计划。
            guard let previousSection = previousSectionsByID[currentSection.id] else {
                continue
            }

            // 每个 section 独立判断 item 层变化，避免一个 section 的 prepend/append
            // 影响另一个 section 的 reload/reconfigure 计算。
            let sectionResult = makeSectionPlan(
                sectionID: currentSection.id,
                previousItemIDs: previousSection.itemIDs,
                currentItemIDs: currentSection.itemIDs,
                refreshActionsByItemID: refreshActionsByItemID
            )

            switch sectionResult {
            case let .plan(sectionPlan):
                // .none 的 section 也保留在 sectionPlans 里，方便调用方按 keptSectionIDs
                // 查询并确认某个 section 是否确实没有 item 层变化。
                if sectionPlan.operation != .none {
                    hasIncrementalChange = true
                }
                sectionPlans.append(sectionPlan)
            case let .rebuild(reason):
                // 任一保留 section 出现不支持的 item 结构变化，整体 snapshot 都需要 rebuild。
                // 这里不混合返回部分增量计划，避免调用方误以为可以只重建局部 section。
                return DiffableSnapshotPlan(
                    operation: .rebuild(reason: reason),
                    insertedSectionIDs: [],
                    deletedSectionIDs: [],
                    keptSectionIDs: [],
                    sectionPlans: []
                )
            }
        }

        // 只有 section 层、item 层都完全无变化时才返回 .none；
        // 否则统一返回 .incremental，并把具体操作留在 sectionPlans 和 section ID 数组中。
        return DiffableSnapshotPlan(
            operation: hasIncrementalChange ? .incremental : .none,
            insertedSectionIDs: insertedSectionIDs,
            deletedSectionIDs: deletedSectionIDs,
            keptSectionIDs: keptSectionIDs,
            sectionPlans: sectionPlans
        )
    }

    private enum SectionPlanningResult<SectionIdentifier, ItemIdentifier>
    where SectionIdentifier: Hashable & Sendable, ItemIdentifier: Hashable & Sendable {
        case plan(DiffableSectionPlan<SectionIdentifier, ItemIdentifier>)
        case rebuild(DiffableSnapshotRebuildReason<SectionIdentifier>)
    }

    private static func makeSectionPlan<SectionIdentifier, ItemIdentifier>(
        sectionID: SectionIdentifier,
        previousItemIDs: [ItemIdentifier],
        currentItemIDs: [ItemIdentifier],
        refreshActionsByItemID: [ItemIdentifier: DiffableItemRefreshAction]
    ) -> SectionPlanningResult<SectionIdentifier, ItemIdentifier>
    where SectionIdentifier: Hashable & Sendable, ItemIdentifier: Hashable & Sendable {
        // item 集合用于判断“是否仍存在”，item 数组用于保留业务顺序。
        // 不能只用集合做 diff，因为 UICollectionView 的展示顺序仍由 snapshot 数组决定。
        let previousItemSet = Set(previousItemIDs)
        let currentItemSet = Set(currentItemIDs)

        // surviving* 只保留新旧都存在的 item，用来判断“旧 item 的相对顺序”是否稳定。
        // 删除和新增不会影响这个比较；真正会触发 rebuild 的是既有 item 被重排。
        let survivingPreviousItemIDs = previousItemIDs.filter { currentItemSet.contains($0) }
        let survivingCurrentItemIDs = currentItemIDs.filter { previousItemSet.contains($0) }

        // 既有 item 的相对顺序变化时，不能用简单的 prepend/append/delete 表达。
        // 继续做局部增量容易让调用方遗漏 move 或得到错误动画，因此要求完整 rebuild。
        guard survivingPreviousItemIDs == survivingCurrentItemIDs else {
            return .rebuild(.itemOrderChanged(sectionID: sectionID))
        }

        // 删除项按旧顺序输出，方便 UIKit adapter 先 deleteItems，避免后续刷新命中已删除 item。
        let deletedItemIDs = previousItemIDs.filter { !currentItemSet.contains($0) }

        // prefix/suffix 分别表示新列表两端连续出现的“全新 item”。
        // 聊天历史加载是 prefix，发送/接收新消息是 suffix；两端同时变化也能表达。
        let prependedItemIDs = Array(currentItemIDs.prefix { !previousItemSet.contains($0) })
        let appendedItemIDs = Array(currentItemIDs.reversed().prefix { !previousItemSet.contains($0) }.reversed())

        // insertedItemIDs 是所有新增 item；edgeInsertedItemIDs 是两端可安全表达的新增 item。
        // 两者相等才说明没有中间插入。
        let insertedItemIDs = currentItemIDs.filter { !previousItemSet.contains($0) }
        let edgeInsertedItemIDs = prependedItemIDs + appendedItemIDs

        // 新 item 只允许出现在 section 两端：聊天历史 prepend 和最新消息 append 都属于这个模型。
        // 如果新 item 插在中间，UIKit 虽然能全量 diff，但本 planner 无法在不引入复杂 move/anchor
        // 语义的情况下保证顺序和滚动行为，故回退完整 snapshot。
        guard insertedItemIDs == edgeInsertedItemIDs else {
            return .rebuild(.middleItemInsertion(sectionID: sectionID))
        }

        var reconfiguredItemIDs: [ItemIdentifier] = []
        var reloadedItemIDs: [ItemIdentifier] = []

        // 只有旧 snapshot 和新 snapshot 都包含的 item 才允许刷新。
        // 这个集合同时过滤掉“刚新增”和“已删除”的 item，避免未来 UIKit adapter 调错 API。
        let refreshableItemSet = previousItemSet.intersection(currentItemSet)

        for itemID in currentItemIDs where refreshableItemSet.contains(itemID) {
            // 按 currentItemIDs 顺序输出刷新列表，让后续 adapter 的执行顺序稳定、可预测。
            guard let action = refreshActionsByItemID[itemID] else {
                continue
            }

            switch action {
            case .reconfigure:
                // 同一种 cell 类型内的内容变化进入 reconfigure，
                // 例如文本、时间、进度、已读状态等轻量更新。
                reconfiguredItemIDs.append(itemID)
            case .reload:
                // cell 类型或 registration 可能变化时进入 reload，
                // 例如普通消息变成撤回提示，必须让 cell provider 有机会重新选 cell。
                reloadedItemIDs.append(itemID)
            }
        }

        // 删除或新增的 item 不允许进入 refresh 数组：
        // 删除项已经不在新 snapshot 中，对它 reload/reconfigure 会触发 UIKit 前置条件失败；
        // 新增项插入时会走 cell provider，不需要再追加一次内容刷新。
        let operation = makeSectionOperation(
            deletedItemIDs: deletedItemIDs,
            prependedItemIDs: prependedItemIDs,
            appendedItemIDs: appendedItemIDs,
            reconfiguredItemIDs: reconfiguredItemIDs,
            reloadedItemIDs: reloadedItemIDs
        )

        // 这里返回的是纯计划，不直接操作 UIKit snapshot；
        // 调用方可以在未来 adapter 中按注释约定的顺序应用这些数组。
        return .plan(
            DiffableSectionPlan(
                sectionID: sectionID,
                operation: operation,
                deletedItemIDs: deletedItemIDs,
                prependedItemIDs: prependedItemIDs,
                appendedItemIDs: appendedItemIDs,
                reconfiguredItemIDs: reconfiguredItemIDs,
                reloadedItemIDs: reloadedItemIDs
            )
        )
    }

    private static func makeSectionOperation<ItemIdentifier>(
        deletedItemIDs: [ItemIdentifier],
        prependedItemIDs: [ItemIdentifier],
        appendedItemIDs: [ItemIdentifier],
        reconfiguredItemIDs: [ItemIdentifier],
        reloadedItemIDs: [ItemIdentifier]
    ) -> DiffableSectionOperation {
        // 结构变化包含删除、顶部插入、底部追加；这些操作会改变 item 树。
        let hasStructureChange = !deletedItemIDs.isEmpty || !prependedItemIDs.isEmpty || !appendedItemIDs.isEmpty
        // reconfigure/reload 是同 ID item 的内容或 cell 类型刷新，不改变 item 树。
        let hasReconfigure = !reconfiguredItemIDs.isEmpty
        let hasReload = !reloadedItemIDs.isEmpty

        // 完全没有结构变化和刷新动作时，外层 plan 才能把整体结果收敛为 .none。
        if !hasStructureChange && !hasReload && !hasReconfigure {
            return .none
        }

        // 单纯 reconfigure 是最轻量路径，未来 UIKit adapter 可直接调用 reconfigureItems。
        if !hasStructureChange && !hasReload && hasReconfigure {
            return .reconfigureOnly
        }

        // 单纯 reload 代表 cell 类型可能变化，未来 UIKit adapter 应调用 reloadItems。
        if !hasStructureChange && hasReload && !hasReconfigure {
            return .reloadOnly
        }

        // 只要混合了结构变化、reload、reconfigure 中的多种情况，
        // 就统一标记为 incremental，具体动作由各数组表达。
        return .incremental
    }
}

/// 帮助调用方从“旧值/新值”中计算同 ID item 的刷新动作。
public enum DiffableChangedItemDetector {
    /// 根据 item 值变化生成刷新动作字典。
    ///
    /// 这个方法只比较同一个稳定 ID 的新旧值。调用方通过 `action` 闭包决定
    /// 值变化应该走 `.reconfigure` 还是 `.reload`。
    ///
    /// Example:
    /// ```swift
    /// struct MessageRow: Equatable, Sendable {
    ///     let id: String
    ///     let text: String
    ///     let cellKind: String
    /// }
    ///
    /// let actions = DiffableChangedItemDetector.refreshActions(
    ///     previousItems: oldRows,
    ///     currentItems: newRows,
    ///     id: \.id
    /// ) { oldRow, newRow in
    ///     oldRow.cellKind == newRow.cellKind ? .reconfigure : .reload
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - previousItems: 上一次渲染时使用的 item 值。
    ///   - currentItems: 本次渲染时使用的 item 值。
    ///   - id: 从 item 值中提取稳定标识的 key path。
    ///   - action: 当同 ID item 值变化时，决定应执行 reconfigure 还是 reload 的闭包。
    /// - Returns: 只包含旧值和新值都存在且值发生变化的 item 刷新动作。
    public static func refreshActions<Item, ItemIdentifier>(
        previousItems: [Item],
        currentItems: [Item],
        id: KeyPath<Item, ItemIdentifier>,
        action: @Sendable (Item, Item) -> DiffableItemRefreshAction
    ) -> [ItemIdentifier: DiffableItemRefreshAction]
    where Item: Equatable & Sendable, ItemIdentifier: Hashable & Sendable {
        // 旧值按 ID 建索引，只比较同一个稳定 ID 的前后值。
        // 新增 item 不在旧字典里，会自然跳过；删除 item 不会被 currentItems 遍历到。
        let previousItemsByID = Dictionary(uniqueKeysWithValues: previousItems.map { ($0[keyPath: id], $0) })
        var actionsByID: [ItemIdentifier: DiffableItemRefreshAction] = [:]

        for currentItem in currentItems {
            let itemID = currentItem[keyPath: id]
            guard
                let previousItem = previousItemsByID[itemID],
                previousItem != currentItem
            else {
                // 找不到旧值说明是新增 item；值相等说明内容没有变化。
                // 两种情况都不需要生成 reload/reconfigure 动作。
                continue
            }

            // 具体走 reconfigure 还是 reload 交给调用方判断：
            // Package 不理解业务 cell 类型，只负责保存这个决策结果。
            actionsByID[itemID] = action(previousItem, currentItem)
        }

        return actionsByID
    }
}
