import SwiftUI

/// The live counter — unlike widgets, the foreground app can update
/// every frame, so this ticks just like the desktop popover.
struct CounterView: View {
    let settings: SharedSettings
    let onEdit: () -> Void

    @State private var fortuneIndex = Int.random(in: 0..<Fortunes.templates.count)
    private let fortuneTimer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // header
            HStack(spacing: 8) {
                SunriseGlyph(size: 20, color: Theme.gold)
                Text("SILLY MOTIVATION")
                    .font(Theme.display(15))
                    .tracking(3)
                    .foregroundStyle(Theme.gold)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)

            Spacer()

            // the live counter — updates every frame
            TimelineView(.animation) { context in
                let earnings = EarningsEngine.earnings(
                    salary: settings.monthlySalary,
                    at: context.date
                )
                let decimals = MoneyFormat.adaptiveDecimals(perSecond: earnings.perSecond) + 1

                VStack(spacing: 18) {
                    Text("YOU'VE PRINTED THIS MONTH")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(Theme.textDim)

                    // amount
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(settings.currencySymbol)
                            .font(Theme.mono(28))
                            .foregroundStyle(Theme.gold)
                        // Updates every frame via TimelineView — no transition needed,
                        // the raw per-frame change IS the animation.
                        Text(MoneyFormat.full(earnings.earned, decimals: decimals, indian: settings.indianGrouping))
                            .font(Theme.mono(40))
                            .foregroundStyle(Theme.moneyBright)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .shadow(color: Theme.money.opacity(0.45), radius: 16)
                    }
                    .padding(.horizontal, 20)

                    // rate
                    HStack(spacing: 5) {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.money)
                        Text("+\(settings.currencySymbol)\(MoneyFormat.full(earnings.perSecond, decimals: 4, indian: settings.indianGrouping))")
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.money)
                        Text("/ second, forever, even asleep")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textDim)
                    }

                    // month progress
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.black.opacity(0.45))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.moneyDim, Theme.money, Theme.gold],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(geo.size.width * earnings.monthProgress, 6))
                                    .shadow(color: Theme.money.opacity(0.5), radius: 6)
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text("DAY \(earnings.dayOfMonth) OF \(earnings.daysInMonth)")
                            Spacer()
                            Text("\(String(format: "%.1f", earnings.monthProgress * 100))% CONQUERED")
                                .foregroundStyle(Theme.gold)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textDim)
                    }
                    .padding(.horizontal, 32)
                }
            }

            Spacer()

            // silly message
            FortuneCard(
                settings: settings,
                fortuneIndex: fortuneIndex
            )
            .padding(.horizontal, 22)
            .onReceive(fortuneTimer) { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    fortuneIndex = (fortuneIndex + 1) % Fortunes.templates.count
                }
            }

            Spacer()
                .frame(height: 36)
        }
    }
}

struct FortuneCard: View {
    let settings: SharedSettings
    let fortuneIndex: Int

    var body: some View {
        let earnings = EarningsEngine.earnings(salary: settings.monthlySalary)
        let message = Fortunes.filled(
            Fortunes.templates[fortuneIndex],
            perSecond: earnings.perSecond,
            symbol: settings.currencySymbol,
            indian: settings.indianGrouping
        )

        VStack(spacing: 10) {
            Text("✦ ✦ ✦")
                .font(.system(size: 9))
                .tracking(6)
                .foregroundStyle(Theme.gold.opacity(0.55))

            Text(message)
                .font(.system(size: 15, design: .serif))
                .italic()
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .id(fortuneIndex)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.bgRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.gold.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
        )
    }
}

#Preview {
    ZStack {
        Theme.bgPanel.ignoresSafeArea()
        CounterView(
            settings: SharedSettings(
                monthlySalary: 100_000,
                currencySymbol: "₹",
                currencyCode: "INR",
                indianGrouping: true,
                configured: true
            ),
            onEdit: {}
        )
    }
}
