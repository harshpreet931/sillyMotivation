import Foundation

/// User settings, shared between the app and the widget extension
/// through an App Group container.
struct SharedSettings: Codable, Equatable {
    var monthlySalary: Double = 0
    var currencySymbol: String = "₹"
    var currencyCode: String = "INR"
    var indianGrouping: Bool = true
    var configured: Bool = false

    static let appGroupID = "group.com.sillymotivation.app"
    private static let storageKey = "silly-settings"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func load() -> SharedSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(SharedSettings.self, from: data)
        else {
            return SharedSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults.set(data, forKey: Self.storageKey)
    }
}

/// Common currency presets, mirroring the desktop app.
struct CurrencyPreset: Identifiable, Equatable {
    let symbol: String
    let code: String
    let indianGrouping: Bool

    var id: String { code }

    static let all: [CurrencyPreset] = [
        CurrencyPreset(symbol: "₹", code: "INR", indianGrouping: true),
        CurrencyPreset(symbol: "$", code: "USD", indianGrouping: false),
        CurrencyPreset(symbol: "€", code: "EUR", indianGrouping: false),
        CurrencyPreset(symbol: "£", code: "GBP", indianGrouping: false),
        CurrencyPreset(symbol: "¥", code: "JPY", indianGrouping: false),
        CurrencyPreset(symbol: "د.إ", code: "AED", indianGrouping: false),
        CurrencyPreset(symbol: "S$", code: "SGD", indianGrouping: false),
    ]
}
