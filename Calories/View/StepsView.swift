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

    var history: [StepDay] {
        period == .week ? store.weekHistory : store.monthHistory
    }

    var average: Int {
        let nonZero = history.filter { $0.steps > 0 }
        return nonZero.isEmpty ? 0 : nonZero.reduce(0) { $0 + $1.steps } / nonZero.count
    }

    var best: StepDay? {
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
                StepsContentView(viewModel: viewModel, store: store)
                    .safeAreaInset(edge: .bottom) { noDataHint }
            }
        }
        .navigationTitle("Шаги")
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let snapped = max(1000, min(30_000, (store.stepGoal / 500) * 500))
                    selectedGoal = snapped
                    showingGoalEditor = true
                } label: {
                    Image(systemName: "target")
                }
            }
        }
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption.weight(.semibold))
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
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            Text("Доступ к шагам")
                .font(.title2.weight(.semibold))
            Text("Разреши доступ к данным о шагах из Здоровья, чтобы видеть активность.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Разрешить доступ") {
                store.requestAuthorization()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Недоступно")
                .font(.title2.weight(.semibold))
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
                    .font(.headline)
                
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
    @Bindable var viewModel: StepsViewModel
    var store: StepStore
    @State private var ringRestingY: CGFloat?
    @State private var ringPull: CGFloat = 0
    @AppStorage("use_imperial") private var useImperial = false

    private var distanceText: String {
        guard viewModel.distanceKm > 0 else { return "—" }
        return useImperial
            ? String(format: "%.1f \(String(localized: "ми"))", viewModel.distanceKm * 0.621371)
            : String(format: "%.1f \(String(localized: "км"))", viewModel.distanceKm)
    }

    var body: some View {
        List {
            VStack(spacing: 16) {
                todayCard
                chartCard
                trendsCard
                statsCard
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
        }
        .glassRow()
        .listStyle(.insetGrouped)
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

    /// Шаги — голубым, как кольцо шагов в виджете; цель взята — зелёным
    /// кольца калорий. Оранжево-красный читался как перебор, а не как успех.
    private static let stepsColors = [Color(hex: 0x5AC8FF), Color(hex: 0x2F7BFF)]

    private var ringColors: [Color] {
        viewModel.stepGoalAchieved ? ProgressRing.kcalColors : Self.stepsColors
    }

    private var ringLabel: some View {
        let remaining = store.stepGoal - store.stepsToday
        return VStack(spacing: 2) {
            Text(store.stepsToday.formatted())
                .font(.system(size: 42, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("из \(store.stepGoal.formatted()) шагов")
                .font(.caption)
                .foregroundStyle(.secondary)
            if remaining > 0 {
                Text("\(remaining.formatted()) осталось")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            } else {
                Text("цель достигнута")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ProgressRing.kcalColors[0])
                    .contentTransition(.numericText())
            }
        }
    }

    /// Кольцо прямо на фоне, как на «Сегодня», а показатели под ним — стеклянной
    /// плашкой в стиле макросов. Кольцо в карточке было единственным таким
    /// во всём приложении.
    private var todayCard: some View {
        VStack(spacing: 24) {
            RingView(progress: viewModel.ringProgress, colors: ringColors, labelID: store.stepsToday,
                     spinTicket: viewModel.refreshTicket, pullAngle: Double(ringPull) * 1.4) {
                ringLabel
            }
            // Насколько список стянут вниз: кольцо поворачивается за пальцем.
            // Покой — первое положение, которое увидели.
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onChange(of: geometry.frame(in: .global).minY, initial: true) { _, y in
                            guard let resting = ringRestingY else {
                                ringRestingY = y
                                return
                            }
                            ringPull = max(0, y - resting)
                        }
                }
            }

            HStack(spacing: 0) {
                statCell(title: String(localized: "Дистанция"), value: distanceText, subtitle: "")
                statCell(title: String(localized: "от цели"), value: viewModel.goalPercentText, subtitle: "")
                statCell(title: String(localized: "Цель"), value: store.stepGoal.formatted(), subtitle: "")
            }
            .padding(.vertical, 12)
            .glassCard()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("История")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Период", selection: $viewModel.period) {
                    ForEach(StepPeriod.allCases, id: \.self) { p in
                        Text(verbatim: p.localizedTitle).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

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
                    .foregroundStyle(day.steps >= store.stepGoal ? ProgressRing.kcalColors[0] : Self.stepsColors[0])
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
        }
        .padding()
        .glassCard()
    }

    private var trendsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Обзор")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 0) {
                trendCell
                statCell(
                    title: String(localized: "Стрик"),
                    value: "\(store.goalStreak)",
                    subtitle: viewModel.goalStreakSubtitle
                )
                statCell(
                    title: String(localized: "Неделя"),
                    value: store.weeklyTotal > 0 ? store.weeklyTotal.formatted() : "—",
                    subtitle: String(localized: "шагов")
                )
                statCell(
                    title: String(localized: "Калории"),
                    value: store.activeCaloriesToday > 0 ? "\(store.activeCaloriesToday)" : "—",
                    subtitle: String(localized: "ккал актив.")
                )
            }
        }
        .padding()
        .glassCard()
    }

    private var trendCell: some View {
        VStack(spacing: 4) {
            if let trend = viewModel.trendPercent {
                HStack(spacing: 2) {
                    Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.bold))
                    Text(String(format: "%.0f%%", abs(trend)))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(trend >= 0 ? ProgressRing.kcalColors[0] : .orange)
            } else {
                Text("—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: String(localized: "vs пред. неделя"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            statCell(
                title: String(localized: "Среднее"),
                value: viewModel.average > 0 ? viewModel.average.formatted() : "—",
                subtitle: String(localized: "шагов/день")
            )
            statCell(
                title: String(localized: "Рекорд"),
                value: viewModel.best.map { $0.steps.formatted() } ?? "—",
                subtitle: viewModel.best.map { $0.date.formatted(.dateTime.day().month(.abbreviated)) } ?? ""
            )
            statCell(
                title: String(localized: "Дней с целью"),
                value: "\(viewModel.daysOnGoal)",
                subtitle: String(format: String(localized: "из %lld"), viewModel.history.count)
            )
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private func statCell(title: String, value: String, subtitle: String) -> some View {
        // Как колонки плашки макросов: подпись мелко, число — без крика,
        // без разделителей между ячейками.
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                // Ячеек в ряду до четырёх, и длинные подписи вроде «vs пред. неделя»
                // обрезались многоточием вместо переноса.
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
