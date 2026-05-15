import Testing
@testable import DiffableSnapshotKit

@Suite("DiffableSnapshotKit 规划器")
struct DiffableSnapshotKitTests {
    @Test func 首次渲染返回重建计划() {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [],
            currentSections: [.section("messages", ["m1"])],
            refreshActionsByItemID: [:]
        )

        #expect(plan.operation == .rebuild(reason: .initialSnapshot))
        #expect(plan.sectionPlans.isEmpty)
    }

    @Test func section新增和删除生成增量计划() throws {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [
                .section("groups", ["g1"]),
                .section("friends", ["f1"])
            ],
            currentSections: [
                .section("friends", ["f1"]),
                .section("starred", ["s1"])
            ],
            refreshActionsByItemID: [:]
        )

        #expect(plan.operation == .incremental)
        #expect(plan.insertedSectionIDs == ["starred"])
        #expect(plan.deletedSectionIDs == ["groups"])

        let friendsPlan = try #require(plan.sectionPlan(for: "friends"))
        #expect(friendsPlan.operation == .none)
    }

    @Test func section顺序变化返回重建计划() {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [
                .section("groups", ["g1"]),
                .section("friends", ["f1"])
            ],
            currentSections: [
                .section("friends", ["f1"]),
                .section("groups", ["g1"])
            ],
            refreshActionsByItemID: [:]
        )

        #expect(plan.operation == .rebuild(reason: .sectionOrderChanged))
    }

    @Test func 顶部插入和底部追加生成同一个section增量计划() throws {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [.section("messages", ["m2", "m3"])],
            currentSections: [.section("messages", ["m1", "m2", "m3", "m4"])],
            refreshActionsByItemID: [:]
        )

        let sectionPlan = try #require(plan.sectionPlan(for: "messages"))
        #expect(plan.operation == .incremental)
        #expect(sectionPlan.operation == .incremental)
        #expect(sectionPlan.prependedItemIDs == ["m1"])
        #expect(sectionPlan.appendedItemIDs == ["m4"])
    }

    @Test func item中间插入返回重建计划() {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [.section("messages", ["m1", "m3"])],
            currentSections: [.section("messages", ["m1", "m2", "m3"])],
            refreshActionsByItemID: [:]
        )

        #expect(plan.operation == .rebuild(reason: .middleItemInsertion(sectionID: "messages")))
    }

    @Test func 既有item顺序变化返回重建计划() {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [.section("messages", ["m1", "m2", "m3"])],
            currentSections: [.section("messages", ["m2", "m1", "m3"])],
            refreshActionsByItemID: [:]
        )

        #expect(plan.operation == .rebuild(reason: .itemOrderChanged(sectionID: "messages")))
    }

    @Test func 同ID内容变化返回reconfigure() throws {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [.section("messages", ["m1", "m2"])],
            currentSections: [.section("messages", ["m1", "m2"])],
            refreshActionsByItemID: ["m2": .reconfigure]
        )

        let sectionPlan = try #require(plan.sectionPlan(for: "messages"))
        #expect(plan.operation == .incremental)
        #expect(sectionPlan.operation == .reconfigureOnly)
        #expect(sectionPlan.reconfiguredItemIDs == ["m2"])
        #expect(sectionPlan.reloadedItemIDs.isEmpty)
    }

    @Test func 同IDCell类型变化返回reload() throws {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [.section("messages", ["m1", "m2"])],
            currentSections: [.section("messages", ["m1", "m2"])],
            refreshActionsByItemID: ["m2": .reload]
        )

        let sectionPlan = try #require(plan.sectionPlan(for: "messages"))
        #expect(plan.operation == .incremental)
        #expect(sectionPlan.operation == .reloadOnly)
        #expect(sectionPlan.reloadedItemIDs == ["m2"])
        #expect(sectionPlan.reconfiguredItemIDs.isEmpty)
    }

    @Test func 新增和删除item不会进入刷新列表() throws {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [.section("messages", ["m1", "m2"])],
            currentSections: [.section("messages", ["m2", "m3"])],
            refreshActionsByItemID: [
                "m1": .reload,
                "m2": .reconfigure,
                "m3": .reconfigure
            ]
        )

        let sectionPlan = try #require(plan.sectionPlan(for: "messages"))
        #expect(sectionPlan.deletedItemIDs == ["m1"])
        #expect(sectionPlan.appendedItemIDs == ["m3"])
        #expect(sectionPlan.reconfiguredItemIDs == ["m2"])
        #expect(sectionPlan.reloadedItemIDs.isEmpty)
    }

    @Test func 多section同时变化时各自计划独立() throws {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [
                .section("messages", ["m1", "m2"]),
                .section("contacts", ["c1"])
            ],
            currentSections: [
                .section("messages", ["m0", "m1", "m2"]),
                .section("contacts", ["c1", "c2"])
            ],
            refreshActionsByItemID: [
                "m2": .reload,
                "c1": .reconfigure
            ]
        )

        let messagePlan = try #require(plan.sectionPlan(for: "messages"))
        let contactPlan = try #require(plan.sectionPlan(for: "contacts"))
        #expect(messagePlan.prependedItemIDs == ["m0"])
        #expect(messagePlan.reloadedItemIDs == ["m2"])
        #expect(contactPlan.appendedItemIDs == ["c2"])
        #expect(contactPlan.reconfiguredItemIDs == ["c1"])
    }

    @Test func changedItemDetector可把值变化映射为刷新类型() {
        struct Row: Equatable, Sendable {
            let id: String
            let text: String
            let kind: String
        }

        let previousRows = [
            Row(id: "m1", text: "hello", kind: "text"),
            Row(id: "m2", text: "old", kind: "text")
        ]
        let currentRows = [
            Row(id: "m1", text: "hello", kind: "text"),
            Row(id: "m2", text: "已撤回", kind: "revoked")
        ]

        let actions = DiffableChangedItemDetector.refreshActions(
            previousItems: previousRows,
            currentItems: currentRows,
            id: \.id
        ) { previous, current in
            previous.kind == current.kind ? .reconfigure : .reload
        }

        #expect(actions == ["m2": .reload])
    }

    @Test func 公开计划类型满足Sendable并可跨并发边界传递() async {
        let plan = DiffableSnapshotPlanner.plan(
            previousSections: [.section("messages", ["m1"])],
            currentSections: [.section("messages", ["m1"])],
            refreshActionsByItemID: ["m1": .reconfigure]
        )

        let task = Task.detached { @Sendable in
            plan.operation
        }

        #expect(await task.value == .incremental)
    }
}
