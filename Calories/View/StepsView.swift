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

    func refresh() async {
        store.fetchAll()
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
        .navigationBarTitleDisplayMode(.large)
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

    private var ringColors: [Color] {
        viewModel.stepGoalAchieved ? [.orange, .red] : [.blue, .cyan]
    }

    private var ringLabel: some View {
        let remaining = store.stepGoal - store.stepsToday
        return VStack(spacing: 2) {
            Text(store.stepsToday.formatted())
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("из \(store.stepGoal.formatted()) шагов")
                .font(.caption)
                .foregroundStyle(.secondary)
            if remaining > 0 {
                Text("\(remaining.formatted()) осталось")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .contentTransition(.numericText())
            } else {
                Text("цель достигнута")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .contentTransition(.numericText())
            }
        }
    }

    /// Кольцо и три показателя — единый блок. Раньше кольцо висело на фоне экрана,
    /// а под ним лежала отдельная серая плашка: получалась карточка внутри карточки.
    private var todayCard: some View {
        VStack(spacing: 24) {
            RingView(progress: viewModel.ringProgress, colors: ringColors, labelID: store.stepsToday) {
                ringLabel
            }

            Divider()

            HStack(spacing: 0) {
                statCell(title: String(localized: "Дистанция"), value: distanceText, subtitle: "")
                Divider().frame(height: 40)
                statCell(title: String(localized: "от цели"), value: viewModel.goalPercentText, subtitle: "")
                Divider().frame(height: 40)
                statCell(title: String(localized: "Цель"), value: store.stepGoal.formatted(), subtitle: "")
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("История")
                    .font(.headline)
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
                    .foregroundStyle(day.steps >= store.stepGoal ? Color.green : Color.blue)
                    .cornerRadius(4)

                    RuleMark(y: .value("Цель", store.stepGoal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.orange.opacity(0.7))
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
                .font(.headline)

            HStack(spacing: 0) {
                trendCell
                Divider().frame(height: 40)
                statCell(
                    title: String(localized: "Стрик"),
                    value: "\(store.goalStreak)",
                    subtitle: viewModel.goalStreakSubtitle
                )
                Divider().frame(height: 40)
                statCell(
                    title: String(localized: "Неделя"),
                    value: store.weeklyTotal > 0 ? store.weeklyTotal.formatted() : "—",
                    subtitle: String(localized: "шагов")
                )
                Divider().frame(height: 40)
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
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(trend >= 0 ? .green : .red)
            } else {
                Text("—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: String(localized: "vs пред. неделя"))
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Divider().frame(height: 40)
            statCell(
                title: String(localized: "Рекорд"),
                value: viewModel.best.map { $0.steps.formatted() } ?? "—",
                subtitle: viewModel.best.map { $0.date.formatted(.dateTime.day().month(.abbreviated)) } ?? ""
            )
            Divider().frame(height: 40)
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
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
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
