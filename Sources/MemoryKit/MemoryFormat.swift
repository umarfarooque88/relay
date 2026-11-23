import Foundation

public enum MemoryFormat {
    /// Formats bytes the way Activity Monitor does: binary units, "32.00 GB".
    public static func string(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        let kb = 1024.0
        let mb = kb * 1024
        let gb = mb * 1024
        if value >= gb { return String(format: "%.2f GB", value / gb) }
        if value >= mb { return String(format: "%.1f MB", value / mb) }
        if value >= kb { return String(format: "%.0f KB", value / kb) }
        return "\(bytes) bytes"
    }
}
