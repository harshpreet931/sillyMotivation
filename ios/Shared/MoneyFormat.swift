import Foundation

/// Money formatting that matches the desktop app: western (1,234,567.89)
/// or Indian (12,34,567.89) digit grouping, plus compact forms for widgets.
enum MoneyFormat {
    /// "1,23,456.78" / "123,456.78"
    static func full(_ amount: Double, decimals: Int = 2, indian: Bool) -> String {
        let value = max(amount, 0)
        let formatted = String(format: "%.\(decimals)f", value)
        let parts = formatted.split(separator: ".", maxSplits: 1)
        let intPart = String(parts[0])
        let decPart = parts.count > 1 ? String(parts[1]) : ""

        let grouped = group(intPart, indian: indian)
        return decPart.isEmpty ? grouped : "\(grouped).\(decPart)"
    }

    /// Compact form for tight spaces: "2628", "84.5k", "8.5L", "1.2Cr", "LOTS"
    static func compact(_ amount: Double, indian: Bool) -> String {
        let v = max(amount, 0)

        func oneDecimal(_ x: Double) -> String {
            let s = String(format: "%.1f", x)
            return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }

        if v >= 1e12 { return "LOTS" }

        if indian {
            if v >= 9_995_000 { return "\(oneDecimal(v / 1e7))Cr" }
            if v >= 99_950 { return "\(oneDecimal(v / 1e5))L" }
            return String(format: "%.0f", v)
        }
        if v >= 999_500_000 { return "\(oneDecimal(v / 1e9))B" }
        if v >= 999_500 { return "\(oneDecimal(v / 1e6))M" }
        if v >= 99_950 { return String(format: "%.0fk", v / 1000) }
        if v >= 10_000 { return "\(oneDecimal(v / 1000))k" }
        return String(format: "%.0f", v)
    }

    /// Adaptive decimals so the visible number moves at a satisfying pace.
    static func adaptiveDecimals(perSecond: Double) -> Int {
        guard perSecond > 0, perSecond < 1 else { return 2 }
        return min(4, Int(ceil(-log10(perSecond))) + 1)
    }

    private static func group(_ digits: String, indian: Bool) -> String {
        let chars = Array(digits)
        let n = chars.count
        var out = ""
        for (i, c) in chars.enumerated() {
            if i > 0 {
                let fromRight = n - i
                let needsComma = indian
                    ? fromRight == 3 || (fromRight > 3 && (fromRight - 3) % 2 == 0)
                    : fromRight % 3 == 0
                if needsComma { out.append(",") }
            }
            out.append(c)
        }
        return out
    }
}
