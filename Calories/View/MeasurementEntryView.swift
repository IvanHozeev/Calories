import SwiftUI

/// Ввод замеров: строка со значением, под ней колесо — как в параметрах тела.
/// Ввод только колесом, поэтому неправдоподобное значение физически невозможно
/// набрать: в списке лежит только то, что в границах.
///
/// Правка идёт на месте и сохраняется сразу, кнопки «Готово» нет по смыслу:
/// так не меряют — снял грудь и руки, до икр добрался через день.
/// Незаполненное показывается серой оценкой по пропорциям.
struct MeasurementEntryView: View {
    var store: CalorieStore

    /// Значения в сантиметрах по ключу «место-сторона». Ноль — «не мерил».
    @State private var values: [String: Double] = [:]
    /// Ключ строки с раскрытым колесом. Одно колесо за раз, как в параметрах тела.
    @State private var expanded: String?
    @State private var loaded = false

    private let torso: [MeasurementSite] = [.neck, .shoulders, .chest, .waist, .belt, .pelvis, .glutes]
    private let arms: [MeasurementSite] = [.biceps, .forearm, .wrist]
    private let legs: [MeasurementSite] = [.thigh, .quad, .calf]

    private static func key(_ site: MeasurementSite, _ side: BodySide) -> String {
        "\(site.rawValue)-\(side.rawValue)"
    }

    private func sides(_ site: MeasurementSite) -> [BodySide] {
        site.isPaired ? BodySide.allCases : [.right]
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
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Замеры")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadOnce)
    }

    // MARK: - Строки

    private func sitesSection(_ sites: [MeasurementSite], title: LocalizedStringKey) -> some View {
        Section {
            ForEach(sites) { site in
                row(site)
                if expanded == site.rawValue {
                    wheels(site)
                }
            }
        } header: {
            Text(title)
        }
        .glassRow()
    }

    /// Одна строка на место замера. Парные стороны стоят рядом двумя столбиками,
    /// а не двумя строками: одна мышца — одна строка, иначе список удваивается
    /// и читается как перечисление конечностей, а не мест замера.
    private func row(_ site: MeasurementSite) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.title)
                // Инструкция видна всегда: свёрнутая за кнопкой она не помогает
                // в тот момент, когда человек стоит с лентой.
                Text(site.howTo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(sides(site), id: \.self) { side in
                        VStack(spacing: 1) {
                            // Подпись стороны повторяет порядок колёс ниже,
                            // поэтому «41.5 / 44» не приходится расшифровывать.
                            if site.isPaired {
                                Text(side.title(site.gender))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            value(site, side)
                        }
                    }
                }
                if let source = sharedSource(site) {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded = expanded == site.rawValue ? nil : site.rawValue
            }
        }
    }

    /// Пояснение к серой оценке пишем один раз на строку: у обеих сторон
    /// источник один и тот же, и дублировать его в двух столбиках незачем.
    private func sharedSource(_ site: MeasurementSite) -> String? {
        let unmeasured = sides(site).filter { (values[Self.key(site, $0)] ?? 0) == 0 }
        guard !unmeasured.isEmpty else { return nil }
        let sources = Set(unmeasured.compactMap { suggestion(site, $0)?.source })
        return sources.count == 1 ? sources.first : nil
    }

    /// Справа либо снятое значение, либо серая оценка с пояснением, откуда она.
    @ViewBuilder
    private func value(_ site: MeasurementSite, _ side: BodySide) -> some View {
        let measured = values[Self.key(site, side)] ?? 0
        if measured > 0 {
            Text(String(format: "%g", measured))
                .font(.body.monospacedDigit())
                .accessibilityIdentifier("value-\(Self.key(site, side))")
        } else if let hint = suggestion(site, side) {
            // Округляем до целого: десятая доля в оценке обещала бы точность,
            // которой в ней нет.
            Text("≈ \(String(format: "%.0f", hint.value))")
                .font(.body.monospacedDigit())
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("hint-\(Self.key(site, side))")
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("value-\(Self.key(site, side))")
        }
    }

    /// Парные стороны — два колеса рядом, как футы и дюймы в профиле.
    @ViewBuilder
    private func wheels(_ site: MeasurementSite) -> some View {
        if site.isPaired {
            HStack(spacing: 0) {
                ForEach(sides(site), id: \.self) { side in
                    VStack(spacing: 0) {
                        Text(side.title(site.gender))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        wheel(site, side)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            wheel(site, .right)
        }
    }

    private func wheel(_ site: MeasurementSite, _ side: BodySide) -> some View {
        Picker(site.title, selection: Binding(
            get: { Int((values[Self.key(site, side)] ?? 0) * 10) },
            set: { tenths in
                values[Self.key(site, side)] = Double(tenths) / 10
                commit(site, side)
            }
        )) {
            // Нулевой пункт нужен, чтобы можно было снять ошибочный замер:
            // колесо иначе не даёт вернуться в состояние «не мерил».
            Text("—").tag(0)
            ForEach(site.pickerTenths, id: \.self) { tenths in
                Text(String(format: "%g", Double(tenths) / 10)).tag(tenths)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 160)
        .clipped()
        .accessibilityIdentifier("wheel-\(Self.key(site, side))")
    }

    // MARK: - Оценки

    /// Своя сторона важнее общей оценки по месту: конечности почти симметричны.
    private func suggestion(_ site: MeasurementSite, _ side: BodySide) -> BodyAnalysis.Estimate? {
        if site.isPaired {
            let other = values[Self.key(site, side == .left ? .right : .left)] ?? 0
            if other > 0 {
                return BodyAnalysis.Estimate(value: other, source: String(localized: "как другая сторона"))
            }
        }
        return estimates[site]
    }

    // MARK: - Хранение

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        guard let latest = store.latestMeasurement,
              Calendar.current.isDateInToday(latest.date) else { return }
        for site in MeasurementSite.allCases {
            for side in sides(site) {
                values[Self.key(site, side)] = latest.value(site, side)
            }
        }
    }

    /// Сеанс, который правим: сегодняшний, если он есть, иначе новый.
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

    /// Сохраняем сразу: экрана «Готово» нет, уход назад не должен терять набранное.
    private func commit(_ site: MeasurementSite, _ side: BodySide) {
        todaysMeasurement().setValue(values[Self.key(site, side)] ?? 0, for: site, side: side)
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

}
