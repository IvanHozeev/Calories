import SwiftUI
import Charts
import HealthKit

enum StepPeriod: String, CaseIterable {
    case week = "7 дней"
    case month = "30 дней"

    var localizedTitle: String {
        switch self {
        case .week: return String(localized: "7 дней")
        case .month: return String(localized: "30 дней")
        }
    }
}

@MainActor
@Observable
final class StepsViewModel {
    var period: StepPeriod = .week

    private let store: StepStore

    init(store: StepStore) {
        self.store = store
    }

    var history: [ActivityDay] {
        period == .week ? store.weekHistory : store.monthHistory
    }

    var average: Int {
        let nonZero = history.filter { $0.steps > 0 }
        return nonZero.isEmpty ? 0 : nonZero.reduce(0) { $0 + $1.steps } / nonZero.count
    }

    var best: ActivityDay? {
        history.max(by: { $0.steps < $1.steps })
    }

    var daysOnGoal: Int {
        history.filter { $0.steps >= store.stepGoal }.count
    }

    var trendPercent: Double? {
        guard store.prevWeekAverage > 0, average > 0 else { return nil }
        return Double(average - store.prevWeekAverage) / Double(store.prevWeekAverage) * 100
    }

    var ringProgress: Double {
        guard store.stepGoal > 0 else { return 0 }
        return min(Double(store.stepsToday) / Double(store.stepGoal), 1.0)
    }

    var stepGoalAchieved: Bool {
        store.stepsToday >= store.stepGoal
    }

    var distanceKm: Double { store.distanceTodayKm }

    var goalPercentText: String {
        let pct = store.stepGoal > 0 ? Int(Double(store.stepsToday) / Double(store.stepGoal) * 100) : 0
        return "\(min(pct, 100))%"
    }

    var goalStreakSubtitle: String {
        store.goalStreak == 1 ? String(localized: "день") : String(localized: "дней")
    }

    /// Растёт на каждое обновление — кольцо шагов делает оборот.
    var refreshTicket = 0

    func refresh() async {
        store.fetchAll()
        refreshTicket += 1
        // Ждём оборот: без спиннера конец обновления виден только по кольцу.
        try? await Task.sleep(for: .seconds(ProgressRing.refreshHold))
    }
}

struct StepsNavigationView: View {
    @AppStorage(AppAccent.defaultsKey) private var appAccent = AppAccent.system.rawValue
    var store: StepStore
    @State private var viewModel: StepsViewModel
    @State private var selectedGoal: Int = 10_000
    @State private var showingGoalEditor = false

    init(store: StepStore) {
        self.store = store
        _viewModel = State(initialValue: StepsViewModel(store: store))
    }

    var body: some View {
        Group {
            if !HKHealthStore.isHealthDataAvailable() {
                unavailableView
            } else if !store.isAuthorized {
                authView
            } else {
                StepsContentView(viewModel: viewModel, store: store, onEditGoal: {
                    // Цель и источники — строками на самом экране, а не меню
                    // «…» в углу: настройки, которые трогают раз в полгода,
                    // но искать их под значком без подписи было негде.
                    selectedGoal = max(1000, min(30_000, (store.stepGoal / 500) * 500))
                    showingGoalEditor = true
                })
                    .safeAreaInset(edge: .bottom) { noDataHint }
            }
        }
        // С датой над названием.
        //
        // Слот заголовка начинается вплотную за кнопкой «назад», и однострочное
        // «Шаги» прилипало к шеврону. Двигать заголовок отступом пришлось бы на
        // всех экранах разом ради одного — а у этого просто не было строки
        // контекста, хотя она тут к месту: кольцо и проценты на экране про
        // сегодня, а какое это сегодня, не сказано нигде.
        .screenTitle(String(localized: "Шаги"),
                     eyebrow: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)),
                     trailingButtons: 0)
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showingGoalEditor, onDismiss: {
            store.stepGoal = selectedGoal
        }) {
            GoalPickerSheet(goal: $selectedGoal)
        }
    }

    /// HealthKit намеренно не сообщает, дали ли доступ на чтение: запрос возвращает success
    /// и при отказе тоже. Поэтому отказавший пользователь видел обычный экран с нулями
    /// и никакого способа понять, что делать. Показываем подсказку, когда данных нет совсем.
    @ViewBuilder
    private var noDataHint: some View {
        if store.stepsToday == 0 && store.weekHistory.allSatisfy({ $0.steps == 0 }) {
            VStack(spacing: 8) {
                Text("Нет данных о шагах. Если ты не разрешил доступ, включи его в «Здоровье» → «Доступ» → Calories.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.app(.caption, weight: .semibold))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private var authView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.walk.circle")
                .font(.app(size: 64))
                .foregroundStyle((AppAccent(rawValue: appAccent) ?? .system)
                    .color(focus: AppAccent.storedFocusMacro))
            Text("Доступ к шагам")
                .font(.app(.title2, weight: .semibold))
            Text("Разреши доступ к данным о шагах из Здоровья, чтобы видеть активность.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                store.requestAuthorization()
            } label: {
                Text("Разрешить доступ")
            }
            .buttonStyle(.mainAction)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.app(size: 64))
                .foregroundStyle(.secondary)
            Text("Недоступно")
                .font(.app(.title2, weight: .semibold))
            Text("Данные о шагах недоступны на этом устройстве.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GoalPickerSheet: View {
    @Binding var goal: Int
    @Environment(\.dismiss) private var dismiss

    private let values = Array(stride(from: 1000, through: 30_000, by: 500))

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Цель по шагам")
                    .font(.app(.headline))
                
                Spacer()
                
                CheckmarkButton(action: {
                    dismiss()
                })
                .fontWeight(.semibold)
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 4)

            Picker("Цель", selection: $goal) {
                ForEach(values, id: \.self) { value in
                    Text(value.formatted()).tag(value)
                }
            }
            .pickerStyle(.wheel)
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
}

private struct StepsContentView: View {
    @AppStorage(AppAccent.defaultsKey) private var appAccent = AppAccent.system.rawValue
    @Bindable var viewModel: StepsViewModel
    var store: StepStore
    var onEditGoal: () -> Void = {}
    @AppStorage("use_imperial") private var useImperial = false

    /// Выбранный источник живёт в хранилище, а не в экране: по нему идут
    /// запросы, и менять его надо там, где их задают.
    private var sourceBinding: Binding<String?> {
        Binding(get: { store.preferredSourceID }, set: { store.preferredSourceID = $0 })
    }

    private var distanceText: String {
        guard viewModel.distanceKm > 0 else { return "—" }
        return useImperial
            ? String(format: "%.1f \(String(localized: "ми"))", viewModel.distanceKm * 0.621371)
            : String(format: "%.1f \(String(localized: "км"))", viewModel.distanceKm)
    }

    var body: some View {
        // Порядок — как в макете: сегодня, история, настройки. Раньше было
        // кольцо, график, обзор из четырёх ячеек и ещё одна плашка из трёх,
        // и главное — сколько осталось до цели — делило экран с рекордами.
        List {
            Section {
                todayCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            Section {
                chartCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            } header: {
                Text("История").listSectionTitle()
            }

            Section {
                Button(action: onEditGoal) {
                    HStack {
                        Label {
                            Text("Цель").foregroundStyle(Color.primary)
                        } icon: {
                            Image(systemName: "target").foregroundStyle(.tint)
                        }
                        Spacer()
                        Text(store.stepGoal.formatted())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stepGoal")

                // Выбор источника появляется только когда выбирать есть
                // из чего: у большинства шаги пишет один телефон, и пункт
                // с единственным вариантом был бы вопросом без смысла.
                if store.sources.count > 1 {
                    Picker(selection: sourceBinding) {
                        Text("Все источники").tag(String?.none)
                        ForEach(store.sources) { source in
                            Text(source.name).tag(String?.some(source.id))
                        }
                    } label: {
                        Label {
                            Text("Источники").foregroundStyle(Color.primary)
                        } icon: {
                            Image(systemName: "iphone.gen3").foregroundStyle(.tint)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("stepSource")
                }
            } footer: {
                Text("Приложение только читает шаги из «Здоровья» и ничего туда не пишет.")
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .contentMargins(.top, 4, for: .scrollContent)
        .refreshable {
            await viewModel.refresh()
        }
    }

    /// Потолок оси Y с запасом. Без него линия цели ложится ровно на верхнюю границу
    /// домена и подпись «10,000» срезается краем графика.
    private var chartUpperBound: Double {
        let maxSteps = viewModel.history.map(\.steps).max() ?? 0
        return Double(max(store.stepGoal, maxSteps)) * 1.15
    }

    /// Шаги красятся цветом акцента, выбранным в настройках: это единственное
    /// кольцо без своего смысла у цвета. Цель взята — зелёным кольца калорий,
    /// как «в норме» везде в приложении.
    /// Цвет кольца шагов — общий акцент приложения. У шагов он ничего не
    /// означает, поэтому пусть будет тем, который человек выбрал; при выборе
    /// «По макросу» цвет берётся уже разрешённым — его кладёт дневник.
    ///
    /// Не `static`: акцент читается через `@AppStorage`, иначе смена цвета
    /// проходит мимо — обычное чтение `UserDefaults` SwiftUI не отслеживает,
    /// и кольцо остаётся прежним до полной пересборки экрана.
    private var stepsColors: [Color] {
        let color = (AppAccent(rawValue: appAccent) ?? .system)
            .color(focus: AppAccent.storedFocusMacro)
        return [color, color]
    }

    /// Цвет полоски: цель взята — зелёный кольца калорий, как «в норме»
    /// везде в приложении; иначе акцент.
    private var barColor: Color {
        viewModel.stepGoalAchieved ? ProgressRing.kcalColors[0] : stepsColors[0]
    }

    /// Сегодня: число шагов, полоска до цели и три числа под ней.
    ///
    /// Кольцо ушло: оно занимало треть экрана ради одного числа, а ответ на
    /// «сколько осталось» — это полоска и цифра «Осталось».
    private var todayCard: some View {
        let remaining = max(store.stepGoal - store.stepsToday, 0)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.stepsToday.formatted())
                    .font(.app(size: 34, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("из \(store.stepGoal.formatted()) шагов")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(barColor.opacity(0.18))
                    Capsule().fill(barColor)
                        .frame(width: max(6, geometry.size.width * viewModel.ringProgress))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 8) {
                column(viewModel.stepGoalAchieved ? String(localized: "Цель") : String(localized: "Осталось"),
                       viewModel.stepGoalAchieved ? String(localized: "взята") : remaining.formatted())
                column(String(localized: "Расстояние"), distanceText)
                column(String(localized: "Активные"),
                       store.activeCaloriesToday > 0 ? "\(store.activeCaloriesToday) \(String(localized: "ккал"))" : "—")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stepsToday")
    }

    private func column(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.app(.headline, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Период — полосой во всю ширину карточки, а не узким сегментом
            // справа от заголовка: заголовок теперь над карточкой.
            Picker("Период", selection: $viewModel.period) {
                ForEach(StepPeriod.allCases, id: \.self) { p in
                    Text(verbatim: p.localizedTitle).tag(p)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.history.isEmpty {
                Text("Нет данных")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(viewModel.history) { day in
                    BarMark(
                        x: .value("Дата", day.date, unit: .day),
                        y: .value("Шаги", day.steps)
                    )
                    .foregroundStyle(day.steps >= store.stepGoal ? ProgressRing.kcalColors[0] : stepsColors[0])
                    .cornerRadius(4)

                    RuleMark(y: .value("Цель", store.stepGoal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .chartXAxis {
                    let stride = viewModel.period == .week ? 1 : 5
                    AxisMarks(values: .stride(by: .day, count: stride)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day(), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYScale(domain: 0...chartUpperBound)
                .frame(height: 180)
                .drawingGroup()
                .animation(.easeInOut, value: viewModel.period)
            }

            // Итог периода двумя числами под графиком: среднее и сколько дней
            // цель была взята.
            HStack {
                Text(String(format: String(localized: "В среднем %@ в день"),
                            viewModel.average > 0 ? viewModel.average.formatted() : "—"))
                Spacer(minLength: 8)
                Text(String(format: String(localized: "Цель взята %1$lld из %2$lld"),
                            viewModel.daysOnGoal, viewModel.history.count))
            }
            .font(.app(.caption))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
    }
}
