import Darwin
import Testing

@testable import MemoryKit

@Test func formatsLikeActivityMonitor() {
    #expect(MemoryFormat.string(34_359_738_368) == "32.00 GB")
    #expect(MemoryFormat.string(3_315_335_168) == "3.09 GB")
    #expect(MemoryFormat.string(536_870_912) == "512.0 MB")
    #expect(MemoryFormat.string(2048) == "2 KB")
    #expect(MemoryFormat.string(0) == "0 bytes")
}

@Test func historyKeepsOnlyTheNewestReadings() {
    var history = PressureHistory(capacity: 3)
    for value in [0.1, 0.2, 0.3, 0.4] {
        history.append(.init(value: value, level: .normal))
    }
    #expect(history.points.map(\.value) == [0.2, 0.3, 0.4])

    history.replaceLast(.init(value: 0.9, level: .critical))
    #expect(history.points.map(\.value) == [0.2, 0.3, 0.9])
    #expect(history.points.last?.level == .critical)
}

@Test func sampleAgreesWithTheKernel() throws {
    let sampler = MemorySampler()
    let snapshot = try #require(sampler.sample())

    #expect(snapshot.physical == MemorySampler.sysctl("hw.memsize", UInt64(0)))
    #expect(snapshot.used >= snapshot.app + snapshot.wired + snapshot.compressed)
    #expect(snapshot.used <= snapshot.physical)
    #expect((0...1).contains(snapshot.pressure))

    // Cross-check App Memory against the independent sysctl page counters.
    let pageSize = try #require(counter("hw.pagesize"))
    let internalPages = try #require(counter("vm.page_pageable_internal_count"))
    let purgeable = try #require(counter("vm.page_purgeable_count"))
    let expected = Double((internalPages - purgeable) * pageSize)
    let tolerance = 512.0 * 1024 * 1024
    #expect(abs(Double(snapshot.app) - expected) < tolerance)
}

/// Reads an unsigned integer sysctl whose width (4 or 8 bytes) varies by counter.
private func counter(_ name: String) -> UInt64? {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return value
}

@Test func samplingIsCheapEnoughToRunContinuously() throws {
    let sampler = MemorySampler()
    let clock = ContinuousClock()
    let runs = 1000
    let elapsed = clock.measure {
        for _ in 0..<runs { _ = sampler.sample() }
    }
    let perSample = elapsed / runs
    print("MemorySampler.sample(): \(perSample) per call")
    #expect(perSample < .milliseconds(1))
}
