import WidgetKit
import SwiftUI

/// One timeline entry = the earnings snapshot at one minute.
struct EarningsEntry: TimelineEntry {
    let date: Date
    let settings: SharedSettings
    let earnings: Earnings
    let fortune: String

    init(date: Date, settings: SharedSettings) {
        self.date = date
        self.settings = settings
        self.earnings = EarningsEngine.earnings(salary: settings.monthlySalary, at: date)
        self.fortune = Fortunes.filled(
            Fortunes.pick(at: date),
            perSecond: earnings.perSecond,
            symbol: settings.currencySymbol,
            indian: settings.indianGrouping,
            at: date
        )
    }
}

/// Provides one entry per minute for the next 2 hours, then asks for a new
/// timeline. Entries inside a timeline don't count against the refresh
/// budget — this is how the widget number stays fresh all day.
struct EarningsProvider: TimelineProvider {
    func placeholder(in context: Context) -> EarningsEntry {
        EarningsEntry(
            date: Date(),
            settings: SharedSettings(
                monthlySalary: 100_000,
                currencySymbol: "₹",
                currencyCode: "INR",
                indianGrouping: true,
                configured: true
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (EarningsEntry) -> Void) {
        let settings = SharedSettings.load()
        let snapshot = settings.configured
            ? EarningsEntry(date: Date(), settings: settings)
            : placeholder(in: context)
        completion(snapshot)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EarningsEntry>) -> Void) {
        let settings = SharedSettings.load()
        var entries: [EarningsEntry] = []

        // Align entries to minute boundaries.
        let calendar = Calendar.current
        let now = Date()
        let firstMinute = calendar.dateInterval(of: .minute, for: now)?.start ?? now

        for minuteOffset in 0..<120 {
            let entryDate = firstMinute.addingTimeInterval(Double(minuteOffset) * 60)
            entries.append(EarningsEntry(date: entryDate, settings: settings))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
