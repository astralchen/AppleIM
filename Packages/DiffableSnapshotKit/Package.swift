// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DiffableSnapshotKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "DiffableSnapshotKit",
            targets: ["DiffableSnapshotKit"]
        )
    ],
    targets: [
        .target(
            name: "DiffableSnapshotKit",
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "DiffableSnapshotKitTests",
            dependencies: ["DiffableSnapshotKit"],
            swiftSettings: strictSwiftSettings
        )
    ],
    swiftLanguageModes: [.v6]
)

/// 本地包需要在独立迁移到其他工程后仍保持 Swift 6 严格并发约束。
///
/// `StrictConcurrency` 明确要求完整并发检查；其余 upcoming feature 与 Swift 6
/// 更严格的类型推断、actor 隔离和导入可见性保持一致，提前暴露未来编译问题。
let strictSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("GlobalConcurrency"),
    .enableUpcomingFeature("IsolatedDefaultValues"),
    .enableUpcomingFeature("RegionBasedIsolation"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]
