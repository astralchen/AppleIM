//
//  PerformanceMeasuringTests.swift
//  AppleIMTests
//
//  性能诊断计时测试
//

import Foundation
import Testing
@testable import AppleIM

struct PerformanceMeasuringTests {
    @Test
    func performanceFormattingFormatsElapsedMilliseconds() {
        let elapsed = PerformanceFormatting.elapsedMilliseconds(
            from: 10,
            to: 10.125
        )

        #expect(elapsed == "125.0ms")
    }

    @Test
    func fixedPerformanceMeasurerReturnsDeterministicElapsedText() {
        let measurer = FixedPerformanceMeasurer(startUptime: 20, endUptime: 20.25)
        let span = measurer.start("chat.render")

        #expect(span.name == "chat.render")
        #expect(measurer.elapsedMilliseconds(since: span) == "250.0ms")
    }
}

private struct FixedPerformanceMeasurer: PerformanceMeasuring {
    let startUptime: TimeInterval
    let endUptime: TimeInterval

    func currentUptime() -> TimeInterval {
        endUptime
    }

    func start(_ name: String) -> PerformanceSpan {
        PerformanceSpan(name: name, startUptime: startUptime)
    }

    func elapsedMilliseconds(since span: PerformanceSpan) -> String {
        PerformanceFormatting.elapsedMilliseconds(from: span.startUptime, to: endUptime)
    }
}
