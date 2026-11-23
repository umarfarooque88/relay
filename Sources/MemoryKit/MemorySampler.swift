import Darwin

/// Reads live memory statistics straight from the kernel.
///
/// The breakdown follows Activity Monitor:
///   Memory Used  = physical − free pages (not counting speculative) − external (file-backed) pages
///   App Memory   = internal (anonymous) pages − purgeable pages
///   Wired Memory = wired pages
///   Compressed   = pages occupied by the compressor
///   Cached Files = external pages + purgeable pages
///   Swap Used    = vm.swapusage
/// Memory Used is deliberately not App + Wired + Compressed: Activity Monitor's figure is
/// larger by the purgeable pages plus the memory the VM system does not manage
/// (checked against Activity Monitor on macOS 26.6).
/// Pressure is 1 − kern.memorystatus_level / 100, the same figure the
/// `memory_pressure` tool prints as "System-wide memory free percentage".
public struct MemorySampler: Sendable {
    private let host: host_t
    private let pageSize: UInt64
    public let physical: UInt64

    public init() {
        host = mach_host_self()
        var size: vm_size_t = 0
        host_page_size(host, &size)
        pageSize = UInt64(size)
        physical = Self.sysctl("hw.memsize", UInt64(0)) ?? 0
    }

    /// Returns nil if the kernel refuses any of the reads; nothing is estimated.
    public func sample() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS,
            let freePercent = Self.sysctl("kern.memorystatus_level", Int32(0)),
            let rawLevel = Self.sysctl("kern.memorystatus_vm_pressure_level", Int32(0)),
            let level = PressureLevel(rawValue: rawLevel),
            let swap = Self.sysctl("vm.swapusage", xsw_usage())
        else { return nil }

        let purgeable = UInt64(stats.purgeable_count)
        let internalPages = UInt64(stats.internal_page_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0
        // free_count includes the speculative pages, which are also counted as external.
        let unusedPages =
            UInt64(stats.free_count) - min(UInt64(stats.speculative_count), UInt64(stats.free_count))
            + UInt64(stats.external_page_count)
        let unused = unusedPages * pageSize

        return MemorySnapshot(
            physical: physical,
            used: physical > unused ? physical - unused : 0,
            app: appPages * pageSize,
            wired: UInt64(stats.wire_count) * pageSize,
            compressed: UInt64(stats.compressor_page_count) * pageSize,
            cached: (UInt64(stats.external_page_count) + purgeable) * pageSize,
            swapUsed: swap.xsu_used,
            pressure: min(max(1 - Double(freePercent) / 100, 0), 1),
            level: level
        )
    }

    static func sysctl<T: BitwiseCopyable>(_ name: String, _ initial: T) -> T? {
        var value = initial
        var size = MemoryLayout<T>.size
        let status = withUnsafeMutableBytes(of: &value) {
            sysctlbyname(name, $0.baseAddress, &size, nil, 0)
        }
        guard status == 0, size == MemoryLayout<T>.size else { return nil }
        return value
    }
}
