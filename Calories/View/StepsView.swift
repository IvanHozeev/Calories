import SwiftUI
import Charts
import HealthKit

enum StepPeriod: String, CaseIterable {
    case week = "7 дней"
    case month = "30 дней"
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
        store.goalStreak == 1 ? "день" : "дней"
    }

    func refresh() async {
        store.fetchAll()
    }
}

struct StepsView: View {
    var store: StepStore
    @State private var viewModel: StepsViewModel
    @State private var selectedGoal: Int = 10_000
    @State private var showingGoalEditor = false

    init(store: StepStore) {
        self.store = store
        _viewModel = State(initialValue: StepsViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !HKHealthStore.isHealthDataAvailable() {
                    unavailableView
                } else if !store.isAuthorized {
                    authView
                } else {
                    StepsContentView(viewModel: viewModel, store: store)
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
            ? String(format: "%.1f ми", viewModel.distanceKm * 0.621371)
            : String(format: "%.1f км", viewModel.distanceKm)
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
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refresh()
        }
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
            Text(remaining > 0 ? "\(remaining.formatted()) осталось" : "цель достигнута")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(remaining > 0 ? .blue : .green)
                .contentTransition(.numericText())
        }
    }

    private var todayCard: some View {
        VStack(spacing: 28) {
            RingView(progress: viewModel.ringProgress, colors: ringColors, labelID: store.stepsToday) {
                ringLabel
            }

            HStack(spacing: 0) {
                statCell(title: "Дистанция", value: distanceText, subtitle: "")
                Divider().frame(height: 40)
                statCell(title: "от цели", value: viewModel.goalPercentText, subtitle: "")
                Divider().frame(height: 40)
                statCell(title: "Цель", value: store.stepGoal.formatted(), subtitle: "")
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("История")
                    .font(.headline)
                Spacer()
                Picker("Период", selection: $viewModel.period) {
                    ForEach(StepPeriod.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
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
                .frame(height: 180)
                .drawingGroup()
                .animation(.easeInOut, value: viewModel.period)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var trendsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Обзор")
                .font(.headline)

            HStack(spacing: 0) {
                trendCell
                Divider().frame(height: 40)
                statCell(
                    title: "Стрик",
                    value: "\(store.goalStreak)",
                    subtitle: viewModel.goalStreakSubtitle
                )
                Divider().frame(height: 40)
                statCell(
                    title: "Неделя",
                    value: store.weeklyTotal > 0 ? store.weeklyTotal.formatted() : "—",
                    subtitle: "шагов"
                )
                Divider().frame(height: 40)
                statCell(
                    title: "Калории",
                    value: store.activeCaloriesToday > 0 ? "\(store.activeCaloriesToday)" : "—",
                    subtitle: "ккал актив."
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
            Text("vs пред. неделя")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            statCell(
                title: "Среднее",
                value: viewModel.average > 0 ? viewModel.average.formatted() : "—",
                subtitle: "шагов/день"
            )
            Divider().frame(height: 40)
            statCell(
                title: "Рекорд",
                value: viewModel.best.map { $0.steps.formatted() } ?? "—",
                subtitle: viewModel.best.map { $0.date.formatted(.dateTime.day().month(.abbreviated)) } ?? ""
            )
            Divider().frame(height: 40)
            statCell(
                title: "Дней с целью",
                value: "\(viewModel.daysOnGoal)",
                subtitle: "из \(viewModel.history.count)"
            )
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statCell(title: String, value: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
