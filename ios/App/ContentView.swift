import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var settings = Self.initialSettings()
    @State private var showSettings = false

    /// `--demo` launch argument loads demo settings (used for screenshots/CI).
    private static func initialSettings() -> SharedSettings {
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            return SharedSettings(
                monthlySalary: 100_000,
                currencySymbol: "₹",
                currencyCode: "INR",
                indianGrouping: true,
                configured: true
            )
        }
        return SharedSettings.load()
    }

    var body: some View {
        ZStack {
            // Atmosphere: deep green with soft radial glows.
            Theme.bgPanel.ignoresSafeArea()
            RadialGradient(
                colors: [Theme.money.opacity(0.08), .clear],
                center: .top, startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Theme.gold.opacity(0.06), .clear],
                center: .bottom, startRadius: 0, endRadius: 380
            )
            .ignoresSafeArea()

            if settings.configured && settings.monthlySalary > 0 {
                CounterView(settings: settings, onEdit: { showSettings = true })
            } else {
                OnboardingView(onStart: { showSettings = true })
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: $settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: settings) { _, newValue in
            newValue.save()
            // Widgets should reflect new settings immediately.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// MARK: - First run

struct OnboardingView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            SunriseGlyph(size: 84, color: Theme.gold)

            VStack(spacing: 8) {
                Text("LET'S GET")
                    .font(Theme.display(44))
                    .foregroundStyle(Theme.gold)
                Text("SILLY RICH")
                    .font(Theme.display(44))
                    .foregroundStyle(Theme.gold)
            }
            .shadow(color: Theme.gold.opacity(0.35), radius: 22)

            Text("Tell the machine what you make.\nIt does the rest.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)

            Spacer()

            Button(action: onStart) {
                Text("START THE MONEY PRINTER")
                    .font(Theme.display(17))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.13, green: 0.10, blue: 0.02))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [Theme.goldBright, Theme.gold],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Theme.gold.opacity(0.35), radius: 18, y: 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Shared sunrise glyph

struct SunriseGlyph: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let unit = w / 44.0

            // rising coin (semicircle)
            var coin = Path()
            coin.addArc(
                center: CGPoint(x: 22 * unit, y: 27 * unit),
                radius: 11 * unit,
                startAngle: .degrees(180), endAngle: .degrees(0),
                clockwise: false
            )
            coin.closeSubpath()
            context.fill(coin, with: .color(color))

            // horizon
            let horizon = Path(
                roundedRect: CGRect(x: 5 * unit, y: 29 * unit, width: 34 * unit, height: 3 * unit),
                cornerRadius: 1.5 * unit
            )
            context.fill(horizon, with: .color(color))

            // rays
            for angle in [-48.0, 0.0, 48.0] {
                var ray = Path(
                    roundedRect: CGRect(x: 20.5 * unit, y: 6 * unit, width: 3 * unit, height: 7 * unit),
                    cornerRadius: 1.5 * unit
                )
                let pivot = CGPoint(x: 22 * unit, y: 27 * unit)
                let transform = CGAffineTransform(translationX: pivot.x, y: pivot.y)
                    .rotated(by: angle * .pi / 180)
                    .translatedBy(x: -pivot.x, y: -pivot.y)
                ray = ray.applying(transform)
                context.fill(ray, with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.45), radius: 10)
    }
}

#Preview {
    ContentView()
}
