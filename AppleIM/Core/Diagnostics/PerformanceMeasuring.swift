//
//  PerformanceMeasuring.swift
//  AppleIM
//
//  性能诊断计时
//

import Foundation

/// 一段性能诊断计时。
nonisolated struct PerformanceSpan: Sendable {
    /// 诊断名称，仅用于日志和测试识别。
    let name: String
    /// 基于系统启动时间的起点。
    let startUptime: TimeInterval
}

/// 性能诊断计时接口。
nonisolated protocol PerformanceMeasuring: Sendable {
    /// 当前系统启动时间。
    func currentUptime() -> TimeInterval
    /// 开始一段诊断计时。
    func start(_ name: String) -> PerformanceSpan
    /// 计算经过的毫秒数字符串。
    func elapsedMilliseconds(since span: PerformanceSpan) -> String
}

/// 系统性能诊断计时器。
nonisolated struct SystemPerformanceMeasurer: PerformanceMeasuring {
    static let shared = SystemPerformanceMeasurer()

    func currentUptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func start(_ name: String) -> PerformanceSpan {
        PerformanceSpan(name: name, startUptime: currentUptime())
    }

    func elapsedMilliseconds(since span: PerformanceSpan) -> String {
        PerformanceFormatting.elapsedMilliseconds(
            from: span.startUptime,
            to: currentUptime()
        )
    }
}

/// 性能诊断格式化。
nonisolated enum PerformanceFormatting {
    static func elapsedMilliseconds(from startUptime: TimeInterval, to endUptime: TimeInterval) -> String {
        let milliseconds = (endUptime - startUptime) * 1_000
        return String(format: "%.1fms", milliseconds)
    }
}
