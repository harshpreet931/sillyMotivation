import Foundation

/// The silly motivational messages. `{x}` placeholders are filled with
/// amounts derived from the per-second earning rate.
enum Fortunes {
    static let templates: [String] = [
        "You earn {sleep} every single night just by sleeping. Literal dream job.",
        "Each blink earns you {blink}. Blink twice if you love money.",
        "That 10-minute bathroom break? {poop}. Sponsored by your employer. 🚽",
        "Reading this sentence just earned you {sec5}. You're welcome.",
        "Money printer goes brrrrr 🖨️ — and the printer is YOU.",
        "One hour of pretending to work = {hour}. Acting is lucrative.",
        "Your boss is literally paying you to read silly messages right now.",
        "Compound interest is for nerds. This is REAL-TIME income, baby.",
        "You: existing. Also you: getting paid {persec} every second for it.",
        "That meeting that could've been an email? Still earned you {meeting}. 📧",
        "Coffee break = {coffee} of sponsored hydration. Sip slower. ☕",
        "Every doomscroll session is technically a micro-payday. 📱",
        "Your phone has no idea it's displaying a money-making machine.",
        "Today alone you've already printed {today}. Look at you go.",
        "Somewhere, a spreadsheet just updated in your favor. Cha-ching.",
        "Existential dread? In THIS economy? You're earning through it.",
        "You make {hour} an hour. Even at 3 AM. ESPECIALLY at 3 AM.",
        "A salary is just a subscription your company pays for your existence.",
        "Don't call it Monday. Call it +{hour}-per-hour day.",
        "Procrastination station? More like compensation station. 🚂",
        "Naps are just unpaid-looking paid activities. 😴",
        "Inhale. Exhale. That breath was worth {blink}. Breathe more.",
        "Weekend? You mean two days of getting paid to not be there.",
    ]

    /// A deterministic-but-rotating pick (changes every few minutes), so the
    /// widget shows variety without needing randomness at render time.
    static func pick(at date: Date = Date()) -> String {
        let slot = Int(date.timeIntervalSince1970 / 300) // changes every 5 min
        return templates[slot % templates.count]
    }

    static func filled(_ template: String, perSecond: Double, symbol: String, indian: Bool, at date: Date = Date()) -> String {
        let midnight = Calendar.current.startOfDay(for: date)
        let secondsToday = date.timeIntervalSince(midnight)

        func fmt(_ v: Double) -> String {
            let decimals = v >= 100 ? 0 : (v >= 1 ? 2 : min(4, Int(ceil(-log10(max(v, 1e-9)))) + 1))
            return symbol + MoneyFormat.full(v, decimals: decimals, indian: indian)
        }

        return template
            .replacingOccurrences(of: "{sleep}", with: fmt(perSecond * 8 * 3600))
            .replacingOccurrences(of: "{blink}", with: fmt(perSecond * 0.3))
            .replacingOccurrences(of: "{poop}", with: fmt(perSecond * 600))
            .replacingOccurrences(of: "{sec5}", with: fmt(perSecond * 5))
            .replacingOccurrences(of: "{hour}", with: fmt(perSecond * 3600))
            .replacingOccurrences(of: "{persec}", with: fmt(perSecond))
            .replacingOccurrences(of: "{meeting}", with: fmt(perSecond * 3600))
            .replacingOccurrences(of: "{coffee}", with: fmt(perSecond * 900))
            .replacingOccurrences(of: "{today}", with: fmt(perSecond * secondsToday))
    }
}
