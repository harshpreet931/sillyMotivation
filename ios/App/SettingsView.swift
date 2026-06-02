import SwiftUI

struct SettingsView: View {
    @Binding var settings: SharedSettings
    @Environment(\.dismiss) private var dismiss

    @State private var salaryText: String = ""
    @State private var selectedCode: String = "INR"
    @State private var customSymbol: String = ""
    @State private var customCode: String = ""
    @State private var customIndian = false
    @State private var showError = false

    private var isCustom: Bool { selectedCode == "CUSTOM" }
    private var isFirstRun: Bool { !settings.configured }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgPanel.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        // headline
                        VStack(alignment: .leading, spacing: 10) {
                            Text(isFirstRun ? "LET'S GET\nSILLY RICH" : "ADJUST THE\nMACHINE")
                                .font(Theme.display(38))
                                .foregroundStyle(Theme.gold)
                                .shadow(color: Theme.gold.opacity(0.3), radius: 18)
                            Text(isFirstRun
                                 ? "Tell the machine what you make. It does the rest."
                                 : "Change your numbers. The printer adapts instantly.")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textDim)
                        }
                        .padding(.top, 16)

                        // salary
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("MONTHLY SALARY")
                            HStack(spacing: 10) {
                                Text(currentSymbol)
                                    .font(Theme.mono(22))
                                    .foregroundStyle(Theme.gold)
                                TextField("100000", text: $salaryText)
                                    .keyboardType(.decimalPad)
                                    .font(Theme.mono(26))
                                    .foregroundStyle(Theme.moneyBright)
                            }
                            .padding(16)
                            .background(fieldBackground)
                        }

                        // currency
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("CURRENCY")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                ForEach(CurrencyPreset.all) { preset in
                                    currencyChip(label: "\(preset.symbol) \(preset.code)", code: preset.code)
                                }
                                currencyChip(label: "✏️ other", code: "CUSTOM")
                            }
                        }

                        // custom currency
                        if isCustom {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    fieldLabel("SYMBOL")
                                    TextField("₿", text: $customSymbol)
                                        .font(Theme.mono(18))
                                        .foregroundStyle(Theme.text)
                                        .padding(12)
                                        .background(fieldBackground)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    fieldLabel("CODE")
                                    TextField("BTC", text: $customCode)
                                        .font(Theme.mono(18))
                                        .foregroundStyle(Theme.text)
                                        .textInputAutocapitalization(.characters)
                                        .padding(12)
                                        .background(fieldBackground)
                                }
                            }

                            Toggle(isOn: $customIndian) {
                                Text("Indian digit grouping (1,00,000)")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.textDim)
                            }
                            .tint(Theme.money)
                        }

                        if showError {
                            Text("Enter a salary above zero. The printer needs fuel. ⛽")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(red: 0.88, green: 0.40, blue: 0.31))
                                .frame(maxWidth: .infinity)
                        }

                        // save
                        Button(action: save) {
                            Text(isFirstRun ? "START THE MONEY PRINTER" : "UPDATE THE PRINTER")
                                .font(Theme.display(16))
                                .tracking(1.2)
                                .foregroundStyle(Color(red: 0.13, green: 0.10, blue: 0.02))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(
                                    LinearGradient(colors: [Theme.goldBright, Theme.gold], startPoint: .top, endPoint: .bottom)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: Theme.gold.opacity(0.3), radius: 14, y: 5)
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .toolbar {
                if !isFirstRun {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
        }
        .onAppear(perform: prefill)
    }

    // MARK: - pieces

    private var currentSymbol: String {
        if isCustom { return customSymbol.isEmpty ? "💵" : customSymbol }
        return CurrencyPreset.all.first(where: { $0.code == selectedCode })?.symbol ?? "₹"
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(2.2)
            .foregroundStyle(Theme.textDim)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.gold.opacity(0.14), lineWidth: 1)
            )
    }

    private func currencyChip(label: String, code: String) -> some View {
        let selected = selectedCode == code
        return Button {
            selectedCode = code
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Theme.goldBright : Theme.textDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? Theme.gold.opacity(0.16) : Color.black.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(selected ? Theme.gold : Theme.gold.opacity(0.14), lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - actions

    private func prefill() {
        if settings.monthlySalary > 0 {
            salaryText = settings.monthlySalary == settings.monthlySalary.rounded()
                ? String(format: "%.0f", settings.monthlySalary)
                : String(settings.monthlySalary)
        }
        if let preset = CurrencyPreset.all.first(where: { $0.code == settings.currencyCode }) {
            selectedCode = preset.code
        } else if settings.configured {
            selectedCode = "CUSTOM"
            customSymbol = settings.currencySymbol
            customCode = settings.currencyCode
            customIndian = settings.indianGrouping
        }
    }

    /// Locale-aware parsing: handles "1,00,000" (grouping), "1500,50" (EU
    /// decimal comma), and plain "1500.50".
    static func parseSalary(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }
        // Fallback for inputs the locale formatter rejects (e.g. nonstandard
        // grouping like "1,00,000" outside an Indian locale).
        return Double(trimmed.replacingOccurrences(of: ",", with: ""))
    }

    private func save() {
        guard let salary = Self.parseSalary(salaryText), salary > 0, salary.isFinite, salary < 1e15 else {
            showError = true
            return
        }

        var updated = settings
        updated.monthlySalary = salary
        updated.configured = true

        if isCustom {
            updated.currencySymbol = customSymbol.trimmingCharacters(in: .whitespaces).isEmpty ? "💵" : String(customSymbol.prefix(8))
            updated.currencyCode = customCode.trimmingCharacters(in: .whitespaces).isEmpty ? "???" : String(customCode.uppercased().prefix(8))
            updated.indianGrouping = customIndian
        } else if let preset = CurrencyPreset.all.first(where: { $0.code == selectedCode }) {
            updated.currencySymbol = preset.symbol
            updated.currencyCode = preset.code
            updated.indianGrouping = preset.indianGrouping
        }

        settings = updated
        dismiss()
    }
}

#Preview {
    SettingsView(settings: .constant(SharedSettings()))
}
