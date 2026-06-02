import WidgetKit
import SwiftUI

// MARK: - Home screen widget (small + medium)

struct HomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SillyHomeWidget", provider: EarningsProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(for: .widget) { WTheme.background }
        }
        .configurationDisplayName("Money Printer")
        .description("Your salary, printing itself in real time.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EarningsEntry

    var body: some View {
        if !entry.settings.configured {
            UnconfiguredView()
        } else {
            switch family {
            case .systemMedium:
                MediumWidgetView(entry: entry)
            default:
                SmallWidgetView(entry: entry)
            }
        }
    }
}

struct UnconfiguredView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("💸")
                .font(.system(size: 32))
            Text("Open the app to start the money printer")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WTheme.textDim)
                .multilineTextAlignment(.center)
        }
        .padding(8)
    }
}

// MARK: - Small

struct SmallWidgetView: View {
    let entry: EarningsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PRINTED THIS MONTH")
                .font(.system(size: 8, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(WTheme.textDim)

            // amount (updates every minute via timeline entries)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(entry.settings.currencySymbol)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(WTheme.gold)
                Text(MoneyFormat.full(entry.earnings.earned, decimals: 0, indian: entry.settings.indianGrouping))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(WTheme.moneyBright)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // live month progress (system keeps this moving between entries)
            ProgressView(
                timerInterval: entry.earnings.monthStart...entry.earnings.monthEnd,
                countsDown: false,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.linear)
            .tint(WTheme.money)

            HStack {
                Text("DAY \(entry.earnings.dayOfMonth)/\(entry.earnings.daysInMonth)")
                Spacer()
                Text("+\(entry.settings.currencySymbol)\(MoneyFormat.full(entry.earnings.perSecond, decimals: 3, indian: false))/s")
                    .foregroundStyle(WTheme.money)
            }
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(WTheme.textDim)
        }
    }
}

// MARK: - Medium

struct MediumWidgetView: View {
    let entry: EarningsEntry

    var body: some View {
        HStack(spacing: 16) {
            // left: the numbers
            VStack(alignment: .leading, spacing: 6) {
                Text("PRINTED THIS MONTH")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(WTheme.textDim)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(entry.settings.currencySymbol)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(WTheme.gold)
                    Text(MoneyFormat.full(entry.earnings.earned, decimals: 2, indian: entry.settings.indianGrouping))
                        .font(.system(size: 27, weight: .bold, design: .monospaced))
                        .foregroundStyle(WTheme.moneyBright)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 7))
                    Text("+\(entry.settings.currencySymbol)\(MoneyFormat.full(entry.earnings.perSecond, decimals: 4, indian: false)) every second")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(WTheme.money)

                Spacer(minLength: 0)

                ProgressView(
                    timerInterval: entry.earnings.monthStart...entry.earnings.monthEnd,
                    countsDown: false,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
                .progressViewStyle(.linear)
                .tint(WTheme.money)

                Text("DAY \(entry.earnings.dayOfMonth) OF \(entry.earnings.daysInMonth) · \(String(format: "%.1f", entry.earnings.monthProgress * 100))% CONQUERED")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(WTheme.textDim)
            }

            // right: the silly message
            VStack(spacing: 6) {
                Text("✦ ✦ ✦")
                    .font(.system(size: 7))
                    .tracking(4)
                    .foregroundStyle(WTheme.gold.opacity(0.6))
                Text(entry.fortune)
                    .font(.system(size: 11, design: .serif))
                    .italic()
                    .foregroundStyle(WTheme.text)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 120)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(WTheme.gold.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    HomeWidget()
} timeline: {
    EarningsEntry(
        date: .now,
        settings: SharedSettings(monthlySalary: 100_000, currencySymbol: "₹", currencyCode: "INR", indianGrouping: true, configured: true)
    )
}

#Preview("Medium", as: .systemMedium) {
    HomeWidget()
} timeline: {
    EarningsEntry(
        date: .now,
        settings: SharedSettings(monthlySalary: 100_000, currencySymbol: "₹", currencyCode: "INR", indianGrouping: true, configured: true)
    )
}
