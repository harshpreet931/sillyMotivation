import SwiftUI

/// Widget-local copy of the app palette (widget extensions are separate bundles).
enum WTheme {
    static let bgPanel = Color(red: 0.043, green: 0.082, blue: 0.063)
    static let bgDeep = Color(red: 0.024, green: 0.051, blue: 0.035)
    static let money = Color(red: 0.290, green: 0.871, blue: 0.502)
    static let moneyBright = Color(red: 0.525, green: 0.941, blue: 0.678)
    static let moneyDim = Color(red: 0.173, green: 0.478, blue: 0.306)
    static let gold = Color(red: 0.941, green: 0.773, blue: 0.282)
    static let goldBright = Color(red: 1.0, green: 0.878, blue: 0.541)
    static let text = Color(red: 0.847, green: 0.918, blue: 0.867)
    static let textDim = Color(red: 0.435, green: 0.541, blue: 0.478)

    static var background: some View {
        ZStack {
            bgPanel
            RadialGradient(
                colors: [money.opacity(0.10), .clear],
                center: .top, startRadius: 0, endRadius: 200
            )
            RadialGradient(
                colors: [gold.opacity(0.07), .clear],
                center: .bottom, startRadius: 0, endRadius: 180
            )
        }
    }
}
