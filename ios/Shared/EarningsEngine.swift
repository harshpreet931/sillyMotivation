import Foundation

/// A snapshot of how much money has been printed so far this month.
struct Earnings {
    let earned: Double
    let perSecond: Double
    let monthTotal: Double
    let monthProgress: Double
    let monthStart: Date
    let monthEnd: Date
    let dayOfMonth: Int
    let daysInMonth: Int
}

/// The same math as the desktop app:
/// earned = salary × (elapsed seconds this month / total seconds this month)
enum EarningsEngine {
    static func earnings(salary: Double, at date: Date = Date(), calendar: Calendar = .current) -> Earnings {
        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            return Earnings(
                earned: 0, perSecond: 0, monthTotal: salary, monthProgress: 0,
                monthStart: date, monthEnd: date, dayOfMonth: 1, daysInMonth: 30
            )
        }

        let totalSeconds = interval.end.timeIntervalSince(interval.start)
        let elapsedSeconds = min(max(date.timeIntervalSince(interval.start), 0), totalSeconds)
        let progress = totalSeconds > 0 ? elapsedSeconds / totalSeconds : 0

        let day = calendar.component(.day, from: date)
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 30

        return Earnings(
            earned: salary * progress,
            perSecond: totalSeconds > 0 ? salary / totalSeconds : 0,
            monthTotal: salary,
            monthProgress: progress,
            monthStart: interval.start,
            monthEnd: interval.end,
            dayOfMonth: day,
            daysInMonth: days
        )
    }
}
