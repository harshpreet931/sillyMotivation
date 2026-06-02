import WidgetKit
import SwiftUI

// MARK: - Lock screen widgets (accessory families)

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SillyLockWidget", provider: EarningsProvider()) { entry in
            LockWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Money Printer (Lock Screen)")
        .description("Earnings at a glance, right on your lock screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EarningsEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularLockView(entry: entry)
        case .accessoryInline:
            InlineLockView(entry: entry)
        default:
            RectangularLockView(entry: entry)
        }
    }
}

/// Circular: progress ring around the compact amount.
struct CircularLockView: View {
    let entry: EarningsEntry

    var body: some View {
        // Note: .accessoryCircularCapacity only renders the currentValueLabel
        // (centered in the ring) — the `label` closure is never shown.
        if !entry.settings.configured {
            Gauge(value: 0) {
                EmptyView()
            } currentValueLabel: {
                Text("💸")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            Gauge(value: entry.earnings.monthProgress) {
                EmptyView()
            } currentValueLabel: {
                Text(MoneyFormat.compact(entry.earnings.earned, indian: entry.settings.indianGrouping))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }
}

/// Rectangular: amount + day + progress bar.
struct RectangularLockView: View {
    let entry: EarningsEntry

    var body: some View {
        if !entry.settings.configured {
            Text("Open Silly Motivation to start printing 💸")
                .font(.system(size: 12, weight: .medium))
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text("MONEY PRINTED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .opacity(0.7)
                    Spacer()
                    Text("D\(entry.earnings.dayOfMonth)/\(entry.earnings.daysInMonth)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .opacity(0.7)
                }

                Text("\(entry.settings.currencySymbol)\(MoneyFormat.full(entry.earnings.earned, decimals: 2, indian: entry.settings.indianGrouping))")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                ProgressView(
                    timerInterval: entry.earnings.monthStart...entry.earnings.monthEnd,
                    countsDown: false,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
                .progressViewStyle(.linear)
            }
        }
    }
}

/// Inline: one line above the clock.
struct InlineLockView: View {
    let entry: EarningsEntry

    var body: some View {
        if !entry.settings.configured {
            Text("💸 printer offline")
        } else {
            Text("\(entry.settings.currencySymbol)\(MoneyFormat.compact(entry.earnings.earned, indian: entry.settings.indianGrouping)) printed")
        }
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    LockWidget()
} timeline: {
    EarningsEntry(
        date: .now,
        settings: SharedSettings(monthlySalary: 100_000, currencySymbol: "₹", currencyCode: "INR", indianGrouping: true, configured: true)
    )
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockWidget()
} timeline: {
    EarningsEntry(
        date: .now,
        settings: SharedSettings(monthlySalary: 100_000, currencySymbol: "₹", currencyCode: "INR", indianGrouping: true, configured: true)
    )
}
