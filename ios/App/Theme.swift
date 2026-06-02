import SwiftUI

/// The "Money Printer Terminal" palette, identical to the desktop app.
enum Theme {
    static let bgDeep = Color(red: 0.024, green: 0.051, blue: 0.035)      // #060d09
    static let bgPanel = Color(red: 0.043, green: 0.082, blue: 0.063)     // #0b1510
    static let bgRaised = Color(red: 0.063, green: 0.122, blue: 0.090)    // #101f17
    static let money = Color(red: 0.290, green: 0.871, blue: 0.502)       // #4ade80
    static let moneyBright = Color(red: 0.525, green: 0.941, blue: 0.678) // #86f0ad
    static let moneyDim = Color(red: 0.173, green: 0.478, blue: 0.306)    // #2c7a4e
    static let gold = Color(red: 0.941, green: 0.773, blue: 0.282)        // #f0c548
    static let goldBright = Color(red: 1.0, green: 0.878, blue: 0.541)    // #ffe08a
    static let text = Color(red: 0.847, green: 0.918, blue: 0.867)        // #d8eadd
    static let textDim = Color(red: 0.435, green: 0.541, blue: 0.478)     // #6f8a7a

    static func display(_ size: CGFloat) -> Font {
        .custom("Anton-Regular", size: size)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
