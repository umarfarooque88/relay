/// Kernel memory pressure level, as reported by `kern.memorystatus_vm_pressure_level`.
public enum PressureLevel: Int32, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4
}

/// One reading of system memory, using the same breakdown as Activity Monitor.
public struct MemorySnapshot: Sendable, Equatable {
    public var physical: UInt64
    public var used: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var swapUsed: UInt64
    /// 0 (no pressure) ... 1 (no memory available).
    public var pressure: Double
    public var level: PressureLevel

    public init(
        physical: UInt64, used: UInt64, app: UInt64, wired: UInt64, compressed: UInt64,
        cached: UInt64, swapUsed: UInt64, pressure: Double, level: PressureLevel
    ) {
        self.physical = physical
        self.used = used
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.pressure = pressure
        self.level = level
    }
}

/// Fixed-length rolling record of pressure readings for the graph.
public struct PressureHistory: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public var value: Double
        public var level: PressureLevel

        public init(value: Double, level: PressureLevel) {
            self.value = value
            self.level = level
        }
    }

    public let capacity: Int
    public private(set) var points: [Point] = []

    public init(capacity: Int) {
        precondition(capacity > 1)
        self.capacity = capacity
        points.reserveCapacity(capacity + 1)
    }

    public mutating func append(_ point: Point) {
        points.append(point)
        if points.count > capacity {
            points.removeFirst(points.count - capacity)
        }
    }

    /// Overwrites the newest reading without advancing the graph.
    public mutating func replaceLast(_ point: Point) {
        if points.isEmpty {
            points.append(point)
        } else {
            points[points.count - 1] = point
        }
    }
}
