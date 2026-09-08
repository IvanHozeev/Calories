import SwiftUI

/// Замеры: экран показывает, что из снятых обхватов следует, а сам ввод живёт
/// за плюсом в тулбаре. Пропорция обращений именно такая — мерить садишься
/// раз в неделю-две, а смотреть на выводы хочется каждый раз.
struct MeasurementsView: View {
    var store: CalorieStore

    @State private var showingEntry = false

    var body: some View {
        List {
            if let latest = store.latestMeasurement {
                let insights = BodyAnalysis.insights(measurement: latest, profile: store.profile)
                if insights.isEmpty {
                    Section { notEnoughYet } .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    resultsSection(insights, measuredOn: latest.date)
                }
                girthsSection(latest)
            } else {
                Section { emptyState } .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }

            if store.measurements.count > 1 {
                Section {
                    NavigationLink {
                        MeasurementHistoryView(store: store)
                    } label: {
                        HStack {
                            Text("История замеров")
                            Spacer()
                            Text(verbatim: "\(store.measurements.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("openMeasurementHistory")
                }
                .glassRow()
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Замеры")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("openMeasurementEntry")
            }
        }
        .fullScreenCover(isPresented: $showingEntry) {
            MeasurementEntrySheet(store: store, isPresented: $showingEntry)
        }
    }

    /// Обхваты и что с ними стало с прошлого раза.
    ///
    /// Не график: мерят раз в одну-две недели, и на трёх точках линия врёт больше,
    /// чем говорит. Столбик «изменение» на тех же трёх точках честен и читается
    /// сразу — он и отвечает на единственный вопрос, ради которого мерят.
    @ViewBuilder
    private func girthsSection(_ latest: BodyMeasurement) -> some View {
        let previous = store.previousMeasurement
        let rows = MeasurementSite.allCases.compactMap { site -> (MeasurementSite, Double, Double?)? in
            let now = latest.best(site)
            guard now > 0 else { return nil }
            let was = previous?.best(site) ?? 0
            return (site, now, was > 0 ? now - was : nil)
        }

        if !rows.isEmpty {
            Section {
                ForEach(rows, id: \.0) { site, now, delta in
                    HStack {
                        Text(site.title)
                        Spacer()
                        if let delta, abs(delta) >= 0.05 {
                            Text(verbatim: String(format: "%+.1f", delta))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(delta > 0 ? .green : .orange)
                                .monospacedDigit()
                        }
                        Text(verbatim: String(format: "%g \(String(localized: "см"))", now))
                            .font(.body.weight(.medium))
                            .monospacedDigit()
                    }
                    // Строка целиком — один элемент: и для голосового доступа
                    // осмысленнее, и подпись места перестаёт быть отдельным
                    // текстом, который спорит с такой же подписью на вводе.
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Обхваты")
            } footer: {
                Text(previous == nil
                     ? "Изменения появятся после второго замера."
                     : "Изменение — против прошлого сеанса. Пусто означает, что место не менялось: незаполненное переносится из прошлого замера как есть.")
            }
            .glassRow()
        }
    }

    private func resultsSection(_ insights: [BodyInsight], measuredOn date: Date) -> some View {
        Section {
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
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(insight.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        } header: {
            HStack {
                Text("Результаты")
                Spacer()
                Text(date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassRow()
    }

    // MARK: - Пусто

    /// Замеры есть, но их мало: почти каждый вывод требует пары обхватов,
    /// и по одному числу сказать нечего.
    private var notEnoughYet: some View {
        placeholder(
            icon: "ruler",
            title: "Пока нечего показать",
            text: "Большинство выводов считается по паре обхватов. Сними ещё несколько — талию, пояс, шею и запястье, они дают больше всего."
        )
    }

    private var emptyState: some View {
        placeholder(
            icon: "figure.arms.open",
            title: "Замеров пока нет",
            text: "Сними обхваты лентой — приложение посчитает пропорции и покажет, что растёт, а что отстаёт."
        )
    }

    private func placeholder(icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingEntry = true
            } label: {
                Label("Снять замеры", systemImage: "ruler")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }
}

/// Ввод замеров листом на весь экран.
///
/// Отдельный тип, потому что открывают его из двух мест: с экрана замеров и
/// прямо с «Сегодня», когда пришли по контролу из Пункта управления. Раньше
/// обвязка с «Готово» жила внутри экрана замеров, и второй вход её бы повторил.
struct MeasurementEntrySheet: View {
    var store: CalorieStore
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            MeasurementEntryView(store: store)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { isPresented = false }
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}
