import Foundation
import MemoryKit
import Observation

/// Samples the kernel on a fixed cadence and publishes the latest reading.
@MainActor
@Observable
final class MemoryModel {
    /// Activity Monitor's fastest setting is 1 s; one read costs a few microseconds.
    static let interval: TimeInterval = 0.5
    static let historyLength = 180

    private(set) var snapshot: MemorySnapshot?
    private(set) var history = PressureHistory(capacity: MemoryModel.historyLength)

    /// Called after every new reading, for views that are not SwiftUI.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let sampler = MemorySampler()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pressureEvents: DispatchSourceMemoryPressure?

    func start() {
        guard timer == nil else { return }
        refresh(advancingGraph: true)

        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(advancingGraph: true) }
        }
        timer.tolerance = 0.02
        // .common keeps the readout live while a panel is dragged or a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // The kernel pushes level changes; show them immediately instead of at the next tick.
        let events = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)
        events.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.refresh(advancingGraph: false) }
        }
        events.resume()
        pressureEvents = events
    }

    private func refresh(advancingGraph: Bool) {
        let reading = sampler.sample()
        snapshot = reading
        defer { onChange?() }
        guard let reading else { return }
        let point = PressureHistory.Point(value: reading.pressure, level: reading.level)
        if advancingGraph {
            history.append(point)
        } else {
            history.replaceLast(point)
        }
    }
}
