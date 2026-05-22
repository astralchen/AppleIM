import Testing
import Foundation

@testable import AppleIM

extension AppleIMTests {
    @Test func databaseMigrationReadinessDocumentsUnreleasedRebuildStrategy() throws {
        let source = try repositoryFileContents("AppleIM/Database/DatabaseSchema.swift")
        let technicalRequirements = try repositoryFileContents("ChatBridge_Technical_Development_Requirements.md")
        let schedule = try repositoryFileContents("ChatBridge_Development_Task_Schedule.md")

        #expect(source.contains("不维护历史迁移链"))
        #expect(technicalRequirements.contains("未上架阶段"))
        #expect(technicalRequirements.contains("生产发布后的迁移策略"))
        #expect(schedule.contains("生产发布前必须补迁移链"))
    }
}

private func repositoryFileContents(_ relativePath: String) throws -> String {
    let fileManager = FileManager.default
    let environment = ProcessInfo.processInfo.environment
    let testFileURL = URL(fileURLWithPath: #filePath)
    var candidateRoots: [URL] = []

    for key in ["SRCROOT", "PROJECT_DIR"] {
        if let path = environment[key], path.isEmpty == false {
            candidateRoots.append(URL(fileURLWithPath: path))
        }
    }
    if #filePath.hasPrefix("/") {
        candidateRoots.append(
            testFileURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        )
    }
    candidateRoots.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))

    let url = try #require(
        candidateRoots
            .map { $0.appendingPathComponent(relativePath) }
            .first { fileManager.fileExists(atPath: $0.path) }
    )
    return try String(contentsOf: url, encoding: .utf8)
}
