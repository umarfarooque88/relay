import MemoryKit
import SwiftUI

/// The readout bound to the live model.
struct LivePanelView: View {
    let model: MemoryModel

    var body: some View {
        PanelView(snapshot: model.snapshot, history: model.history)
    }
}

/// The full readout that opens above the Dock bar. Everything Activity Monitor's memory
/// footer shows, arranged by what matters most: the pressure reading and its history first,
/// then how much memory is in use and what it is made of, then swap.
struct PanelView: View {
    let snapshot: MemorySnapshot?
    let history: PressureHistory

    static let width: CGFloat = 376

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pressure
            Hairline()
            usage
            Hairline()
            row(label: "Swap Used", bytes: snapshot?.swapUsed)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(width: Self.width)
    }

    // MARK: Pressure

    private var pressure: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Caption("Memory Pressure")
                Spacer()
                if let level = snapshot?.level {
                    HStack(spacing: 5) {
                        Circle().fill(level.color).frame(width: 7, height: 7)
                        Text(level.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            HStack(alignment: .bottom, spacing: 14) {
                Figure(
                    value: snapshot.map { "\(Int(($0.pressure * 100).rounded()))" } ?? "–",
                    unit: "%", size: 34)
                    .fixedSize()
                SparklineView(history: history)
                    .frame(height: 42)
            }
        }
    }

    // MARK: Usage

    private var usage: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Caption("Memory Used")
                HStack(alignment: .firstTextBaseline) {
                    let used = Self.split(snapshot?.used)
                    Figure(value: used.value, unit: used.unit, size: 24)
                    Spacer()
                    if let physical = snapshot?.physical {
                        Text("of \(Self.installed(physical))")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            CapacityBar(parts: parts, total: snapshot?.physical ?? 0)
                .frame(height: 8)

            // Two columns of equal width.
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 7) {
                    legend(parts[0])
                    legend(parts[2])
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 7) {
                    legend(parts[1])
                    legend(parts[3])
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// What physical memory is holding, in the order Activity Monitor lists it. Cached files
    /// are memory the system can hand back at once, so they are drawn as a quiet grey.
    private var parts: [Part] {
        [
            Part(label: "App Memory", bytes: snapshot?.app, color: .blue),
            Part(label: "Wired Memory", bytes: snapshot?.wired, color: .orange),
            Part(label: "Compressed", bytes: snapshot?.compressed, color: .indigo),
            Part(label: "Cached Files", bytes: snapshot?.cached, color: .primary.opacity(0.3)),
        ]
    }

    private func legend(_ part: Part) -> some View {
        HStack(spacing: 6) {
            Circle().fill(part.color).frame(width: 7, height: 7)
            row(label: part.label, bytes: part.bytes)
        }
    }

    private func row(label: String, bytes: UInt64?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(bytes.map(MemoryFormat.string) ?? "–")
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// Installed memory comes in whole gigabytes; "32 GB" reads better than "32.00 GB".
    private static func installed(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_073_741_824
        return gigabytes == gigabytes.rounded() ? String(format: "%.0f GB", gigabytes) : MemoryFormat.string(bytes)
    }

    /// "27.31 GB" as its number and its unit, so the unit can be set smaller.
    private static func split(_ bytes: UInt64?) -> (value: String, unit: String) {
        guard let bytes else { return ("–", "") }
        let text = MemoryFormat.string(bytes).split(separator: " ", maxSplits: 1)
        return (String(text.first ?? ""), text.count > 1 ? String(text[1]) : "")
    }
}

private struct Part {
    let label: String
    let bytes: UInt64?
    let color: Color
}

private struct Caption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

/// A prominent number with its unit set smaller beside it, as system widgets do.
private struct Figure: View {
    let value: String
    let unit: String
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.08) {
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .tracking(-size * 0.015)
            Text(unit)
                .font(.system(size: size * 0.52, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(height: 1)
    }
}

/// Physical memory as one bar, divided by what it holds; the unfilled remainder is free.
private struct CapacityBar: View {
    let parts: [Part]
    let total: UInt64

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 1.5
            HStack(spacing: gap) {
                ForEach(parts.indices, id: \.self) { index in
                    let share = total > 0 ? CGFloat(parts[index].bytes ?? 0) / CGFloat(total) : 0
                    Rectangle()
                        .fill(parts[index].color)
                        .frame(width: max(0, proxy.size.width * share - gap))
                }
                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .background(.primary.opacity(0.08))
            .clipShape(.capsule)
        }
        .accessibilityHidden(true)
    }
}
