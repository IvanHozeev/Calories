import SwiftUI

/// Ввод одного сеанса замеров. Форма строится из MeasurementSite, а не из захардкоженного
/// списка полей: добавить новое место замера — значит дописать один case в перечисление.
struct MeasurementEntryView: View {
    var store: CalorieStore
    /// Если передан — правим существующий сеанс, иначе создаём новый.
    var editing: BodyMeasurement?

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    /// Текстовые значения по ключу «место-сторона»: пустое поле должно оставаться пустым,
    /// а не превращаться в ноль, поэтому храним строки, а не Double.
    @State private var values: [String: String] = [:]
    @State private var expandedHint: String?

    init(store: CalorieStore, editing: BodyMeasurement? = nil) {
        self.store = store
        self.editing = editing
        _date = State(initialValue: editing?.date ?? Date())

        var initial: [String: String] = [:]
        if let editing {
            for site in MeasurementSite.allCases {
                for side in site.isPaired ? BodySide.allCases : [.right] {
                    let value = editing.value(site, side)
                    if value > 0 {
                        initial[Self.key(site, side)] = String(format: "%g", value)
                    }
                }
            }
        }
        _values = State(initialValue: initial)
    }

    private static func key(_ site: MeasurementSite, _ side: BodySide) -> String {
        "\(site.rawValue)-\(side.rawValue)"
    }

    private func number(_ site: MeasurementSite, _ side: BodySide) -> Double {
        let raw = values[Self.key(site, side)] ?? ""
        return Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var hasAnything: Bool {
        values.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Поле заполнено, но число вне правдоподобия либо вообще не число.
    private func isInvalid(_ site: MeasurementSite, _ side: BodySide) -> Bool {
        let raw = (values[Self.key(site, side)] ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return false }
        guard let parsed = Double(raw.replacingOccurrences(of: ",", with: ".")) else { return true }
        return !site.isPlausible(parsed)
    }

    private var invalidSites: [MeasurementSite] {
        MeasurementSite.allCases.filter { site in
            (site.isPaired ? BodySide.allCases : [.right]).contains { isInvalid(site, $0) }
        }
    }

    private let torso: [MeasurementSite] = [.neck, .shoulders, .chest, .waist, .belt, .pelvis, .glutes]
    private let arms: [MeasurementSite] = [.biceps, .forearm, .wrist]
    private let legs: [MeasurementSite] = [.thigh, .quad, .calf]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Дата", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                sitesSection(torso, title: "Торс")
                sitesSection(arms, title: "Руки")
                sitesSection(legs, title: "Ноги")
            }
            .glassRow()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? "Новый замер" : "Замер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .accessibilityIdentifier("saveMeasurement")
                        .fontWeight(.semibold)
                        .disabled(!hasAnything || !invalidSites.isEmpty)
                }
            }
        }
    }

    private func sitesSection(_ sites: [MeasurementSite], title: LocalizedStringKey) -> some View {
        Section {
            ForEach(sites) { site in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(site.title)
                        Button {
                            expandedHint = expandedHint == site.rawValue ? nil : site.rawValue
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()

                        if site.isPaired {
                            sideField(site, .left)
                            sideField(site, .right)
                        } else {
                            field(site, .right, width: 90)
                        }
                    }

                    if site.isPaired ? BodySide.allCases.contains(where: { isInvalid(site, $0) })
                                     : isInvalid(site, .right) {
                        Text(String(format: String(localized: "Ожидается от %.0f до %.0f см"),
                                    site.plausibleRange.lowerBound, site.plausibleRange.upperBound))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("range-\(site.rawValue)")
                    }

                    // Инструкция по умолчанию свёрнута: тринадцать пояснений подряд
                    // превращают форму в стену текста.
                    if expandedHint == site.rawValue {
                        Text(site.howTo)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(title)
        } footer: {
            if sites.contains(where: \.isPaired) {
                Text("Левая и правая стороны — отдельно, по ним считается симметрия.")
            }
        }
    }

    private func sideField(_ site: MeasurementSite, _ side: BodySide) -> some View {
        VStack(spacing: 2) {
            Text(side == .left ? "Л" : "П")
                .font(.caption2)
                .foregroundStyle(.secondary)
            field(site, side, width: 62)
        }
    }

    private func field(_ site: MeasurementSite, _ side: BodySide, width: CGFloat) -> some View {
        TextField("—", text: Binding(
            get: { values[Self.key(site, side)] ?? "" },
            set: { values[Self.key(site, side)] = $0 }
        ))
        .keyboardType(.decimalPad)
        .accessibilityIdentifier("field-\(Self.key(site, side))")
        .multilineTextAlignment(.trailing)
        .font(.body.monospacedDigit())
        .frame(width: width)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isInvalid(site, side) ? Color.red.opacity(0.15) : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private func save() {
        let target = editing ?? BodyMeasurement(date: date)
        target.date = date
        for site in MeasurementSite.allCases {
            for side in site.isPaired ? BodySide.allCases : [BodySide.right] {
                let value = number(site, side)
                guard site.isPlausible(value) else { continue }
                target.setValue(value, for: site, side: side)
            }
        }
        if editing == nil {
            store.addMeasurement(target)
        } else {
            store.saveMeasurementEdits()
        }
        dismiss()
    }
}
