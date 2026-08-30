import SwiftUI

/// Замеры: один список полей, который заполняешь по мере того, как доходят руки.
///
/// Прежняя версия требовала открыть лист, заполнить всё разом и сохранить. На практике
/// так не меряют: снял грудь и бицепс, до икр добрался через день. Поэтому правка идёт
/// прямо здесь и сохраняется сразу, а пустые поля показывают серым, сколько там
/// ожидается по пропорциям от уже снятого.
struct MeasurementsView: View {
    var store: CalorieStore

    /// Черновик по ключу «место-сторона». Пустая строка — «не мерил», это не ноль.
    @State private var values: [String: String] = [:]
    @State private var expandedHint: String?
    @State private var loaded = false

    private let torso: [MeasurementSite] = [.neck, .shoulders, .chest, .waist, .belt, .pelvis, .glutes]
    private let arms: [MeasurementSite] = [.biceps, .forearm, .wrist]
    private let legs: [MeasurementSite] = [.thigh, .quad, .calf]

    private static func key(_ site: MeasurementSite, _ side: BodySide) -> String {
        "\(site.rawValue)-\(side.rawValue)"
    }

    /// Сеанс, который правим: сегодняшний, если он есть, иначе новый.
    /// Замеры одного дня — это один сеанс, а не запись на каждое поле.
    /// Именно функция, а не вычисляемое свойство: она создаёт запись, и прятать
    /// такой побочный эффект за обращением к свойству нельзя.
    private func todaysMeasurement() -> BodyMeasurement {
        if let latest = store.latestMeasurement,
           Calendar.current.isDateInToday(latest.date) {
            return latest
        }
        let fresh = BodyMeasurement(date: Date())
        store.addMeasurement(fresh)
        return fresh
    }

    private var estimates: [MeasurementSite: BodyAnalysis.Estimate] {
        guard let latest = store.latestMeasurement else { return [:] }
        return BodyAnalysis.estimates(for: latest)
    }

    var body: some View {
        List {
            sitesSection(torso, title: "Торс")
            sitesSection(arms, title: "Руки")
            sitesSection(legs, title: "Ноги")

            estimateExplainer
            insightsSection
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .navigationTitle("Замеры")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadOnce)
    }

    // MARK: - Ввод

    private func sitesSection(_ sites: [MeasurementSite], title: LocalizedStringKey) -> some View {
        Section {
            ForEach(sites) { site in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(site.title)
                        Button {
                            expandedHint = expandedHint == site.rawValue ? nil : site.rawValue
                        } label: {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()

                        if site.isPaired {
                            sideField(site, .left)
                            sideField(site, .right)
                        } else {
                            field(site, .right, width: 92)
                        }
                    }

                    if isOutOfRange(site) {
                        Text(String(format: String(localized: "Ожидается от %.0f до %.0f см"),
                                    site.plausibleRange.lowerBound, site.plausibleRange.upperBound))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("range-\(site.rawValue)")
                    } else if let estimate = estimates[site], isEmpty(site) {
                        Text(estimate.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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
        }
        .glassRow()
    }

    private func sideField(_ site: MeasurementSite, _ side: BodySide) -> some View {
        VStack(spacing: 2) {
            Text(side == .left ? "Л" : "П")
                .font(.caption2)
                .foregroundStyle(.secondary)
            field(site, side, width: 64)
        }
    }

    private func field(_ site: MeasurementSite, _ side: BodySide, width: CGFloat) -> some View {
        TextField("", text: Binding(
            get: { values[Self.key(site, side)] ?? "" },
            set: {
                values[Self.key(site, side)] = $0
                commit(site, side)
            }
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
        // Подсказка рисуется наложением, а не placeholder'ом: SwiftUI не обновляет
        // placeholder уже созданного поля, и оценка появлялась бы только при
        // повторном заходе на экран — ровно не тогда, когда она нужна.
        .overlay(alignment: .trailing) {
            if raw(site, side).isEmpty {
                Text(placeholder(site, side))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("hint-\(Self.key(site, side))")
            }
        }
    }

    /// Серая подсказка прямо в поле: видно ожидаемое значение, но это именно
    /// placeholder — в данные оно не попадёт, пока не наберёшь руками.
    private func placeholder(_ site: MeasurementSite, _ side: BodySide) -> String {
        // Вторая сторона той же мышцы — самый надёжный ориентир из всех: конечности
        // почти симметричны, и расхождение больше пары сантиметров само по себе новость.
        if site.isPaired {
            let other: BodySide = side == .left ? .right : .left
            let text = raw(site, other).replacingOccurrences(of: ",", with: ".")
            if let value = Double(text), site.isPlausible(value), value > 0 {
                return String(format: "%g", value)
            }
        }
        guard let estimate = estimates[site] else { return "—" }
        return String(format: "%.0f", estimate.value)
    }

    // MARK: - Состояние полей

    private func raw(_ site: MeasurementSite, _ side: BodySide) -> String {
        (values[Self.key(site, side)] ?? "").trimmingCharacters(in: .whitespaces)
    }

    private func isEmpty(_ site: MeasurementSite) -> Bool {
        (site.isPaired ? BodySide.allCases : [.right]).allSatisfy { raw(site, $0).isEmpty }
    }

    private func isInvalid(_ site: MeasurementSite, _ side: BodySide) -> Bool {
        let text = raw(site, side)
        guard !text.isEmpty else { return false }
        guard let parsed = Double(text.replacingOccurrences(of: ",", with: ".")) else { return true }
        return !site.isPlausible(parsed)
    }

    private func isOutOfRange(_ site: MeasurementSite) -> Bool {
        (site.isPaired ? BodySide.allCases : [.right]).contains { isInvalid(site, $0) }
    }

    // MARK: - Хранение

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        guard let latest = store.latestMeasurement,
              Calendar.current.isDateInToday(latest.date) else { return }
        for site in MeasurementSite.allCases {
            for side in site.isPaired ? BodySide.allCases : [BodySide.right] {
                let value = latest.value(site, side)
                if value > 0 { values[Self.key(site, side)] = String(format: "%g", value) }
            }
        }
    }

    /// Сохраняем сразу: экран без кнопки «Готово», уход назад не должен терять набранное.
    /// Неправдоподобное значение не пишем — поле уже подсвечено красным.
    private func commit(_ site: MeasurementSite, _ side: BodySide) {
        let text = raw(site, side)
        let parsed = text.isEmpty ? 0 : Double(text.replacingOccurrences(of: ",", with: ".")) ?? -1
        guard parsed >= 0, site.isPlausible(parsed) else { return }
        todaysMeasurement().setValue(parsed, for: site, side: side)
        store.saveMeasurementEdits()
    }

    // MARK: - Пояснение к подсказкам

    @ViewBuilder
    private var estimateExplainer: some View {
        if !estimates.isEmpty {
            Section {
                EmptyView()
            } footer: {
                Text("Серым показано, сколько примерно ожидается по пропорциям от уже снятого. Это ориентир, а не замер: у людей с одинаковым запястьем разброс достигает нескольких сантиметров. В данные попадает только то, что ты ввёл сам.")
            }
        }
    }

    // MARK: - Отчёт

    @ViewBuilder
    private var insightsSection: some View {
        if let latest = store.latestMeasurement {
            let insights = BodyAnalysis.insights(measurement: latest, profile: store.profile)
            if !insights.isEmpty {
                Section("Отчёт") {
                    ForEach(insights) { insight in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(insight.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(insight.verdictLabel)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(insight.verdict.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(insight.verdict.color.opacity(0.12), in: Capsule())
                            }
                            Text(insight.value)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(insight.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .glassRow()
            }
        }
    }
}
