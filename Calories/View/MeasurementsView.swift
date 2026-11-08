import SwiftUI

/// Замеры: экран показывает, что из снятых обхватов следует, а сам ввод живёт
/// за плюсом в тулбаре. Пропорция обращений именно такая — мерить садишься
/// раз в неделю-две, а смотреть на выводы хочется каждый раз.
struct MeasurementsView: View {
    var store: CalorieStore

    @State private var showingEntry = false
    /// Какое место показывает график. Талия — то, ради чего берут ленту чаще
    /// всего, и начинать разумно с неё.
    @State private var chartSite: MeasurementSite = .waist
    /// Вывод, объяснение которого сейчас показывают листом.
    @State private var shownInsight: BodyInsight?

    var body: some View {
        List {
            if let latest = store.latestMeasurement {
                let insights = BodyAnalysis.insights(measurement: latest, profile: store.profile)
                if insights.isEmpty {
                    Section { notEnoughYet } .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    resultsSection(insights, measuredOn: latest.date)
                }
                dynamicsSection
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
        .screenTitle(String(localized: "Замеры"), trailingButtons: 2)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEntry = true
                } label: {
                    // Линейка, а не плюс: на этом экране добавляют не запись
                    // вообще, а снятые лентой обхваты — и иконка называет
                    // именно это.
                    Image(systemName: "ruler")
                }
                .accessibilityLabel("Снять замеры")
                .accessibilityIdentifier("openMeasurementEntry")
            }
        }
        .fullScreenCover(isPresented: $showingEntry) {
            MeasurementEntrySheet(store: store, isPresented: $showingEntry)
        }
        .sheet(item: $shownInsight) { insight in
            insightSheet(insight)
        }
    }

    /// Объяснение вывода — отдельным листом.
    ///
    /// Высота фиксирована, длинный текст прокручивается внутри: мерить абзац
    /// заранее нечем — шрифт в приложении выбирает человек, и под Nunito те
    /// же слова занимают не столько же места, сколько под системным.
    private func insightSheet(_ insight: BodyInsight) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(insight.title)
                        .font(.app(.headline))
                    Spacer()
                    Text(insight.verdictLabel)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(insight.verdict.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(insight.verdict.color.opacity(0.12), in: Capsule())
                }
                Text(insight.value)
                    .font(.app(size: 34, weight: .bold))
                    .monospacedDigit()
                Text(insight.explanation)
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    /// Как место менялось от сеанса к сеансу.
    ///
    /// Место выбирается списком, а не вкладками: мест тринадцать, и сегментами
    /// они в шапку не помещаются.
    @ViewBuilder
    private var dynamicsSection: some View {
        let sites = chartableSites
        if !sites.isEmpty {
            let shown = sites.contains(chartSite) ? chartSite : sites[0]
            Section {
                Picker("Место", selection: Binding(
                    get: { shown },
                    set: { chartSite = $0 }
                )) {
                    ForEach(sites) { site in
                        Text(site.title).tag(site)
                    }
                }
                .accessibilityIdentifier("chartSite")
                MeasurementChart(points: chartPoints(shown))
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            } header: {
                Text("Динамика")
            } footer: {
                Text("Место появляется здесь с третьего сеанса: по двум точкам линию можно провести через что угодно.")
            }
            .glassRow()
        }
    }

    /// Места, которые снимали достаточно раз, чтобы линия что-то значила.
    private var chartableSites: [MeasurementSite] {
        MeasurementSite.allCases.filter { site in
            store.measurements.count { $0.best(site) > 0 } >= MeasurementChart.minimumSessions
        }
    }

    private func chartPoints(_ site: MeasurementSite) -> [MeasurementChart.Point] {
        store.measurements
            .filter { $0.best(site) > 0 }
            .map { MeasurementChart.Point(date: $0.date, value: $0.best(site)) }
            .sorted { $0.date < $1.date }
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
                                .font(.app(.caption, weight: .semibold))
                                .foregroundStyle(delta > 0 ? .green : .orange)
                                .monospacedDigit()
                        }
                        Text(verbatim: String(format: "%g \(String(localized: "см"))", now))
                            .font(.app(.body, weight: .medium))
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

    /// Выводы: число и вердикт в строке, объяснение — листом по тапу.
    ///
    /// Шесть выводов, у каждого абзац в три строки, — и экран становится
    /// лекцией: чтобы дойти от первого числа до последнего, приходится
    /// пролистать то, что прочитали один раз и запомнили.
    ///
    /// Раскрытием прямо в строке это не решается: абзац приходит в список,
    /// который под ним едет, и как ни разводи анимации, соседние строки
    /// прыгают. Лист ничего не двигает — он просто приезжает поверх.
    private func resultsSection(_ insights: [BodyInsight], measuredOn date: Date) -> some View {
        Section {
            ForEach(insights) { insight in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(insight.title)
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(insight.verdictLabel)
                            .font(.app(.caption2, weight: .semibold))
                            .foregroundStyle(insight.verdict.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(insight.verdict.color.opacity(0.12), in: Capsule())
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(insight.value)
                            .font(.app(size: 20, weight: .bold))
                            .monospacedDigit()
                        Spacer()
                        // «i», а не шеврон: шеврон ведёт вглубь, а здесь
                        // подробности о самой строке и возврат в то же место.
                        Image(systemName: "info.circle")
                            .font(.app(.footnote))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                // Тап ловится всей строкой, а не только текстом.
                .tappableRow { shownInsight = insight }
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("Показать объяснение"))
            }
        } header: {
            HStack {
                Text("Результаты")
                Spacer()
                Text(date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.app(.caption))
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
                .font(.app(size: 52))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.app(.headline))
            Text(text)
                .font(.app(.footnote))
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
