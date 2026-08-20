import SwiftUI
import Charts
import HealthKit

struct StepsView: View {
    @ObservedObject var store: StepStore
    @State private var period: StepPeriod = .week
    @State private var showingGoalEditor = false
    @State private var goalText = ""

    enum StepPeriod: String, CaseIterable {
        case week = "7 дней"
        case month = "30 дней"
    }

    private var history: [StepDay] {
        period == .week ? store.weekHistory : store.monthHistory
    }

    private var average: Int {
        let nonZero = history.filter { $0.steps > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.reduce(0) { $0 + $1.steps } / nonZero.count
    }

    private var best: StepDay? {
        history.max(by: { $0.steps < $1.steps })
    }

    private var daysOnGoal: Int {
        history.filter { $0.steps >= store.stepGoal }.count
    }

    private var weeklyTotal: Int {
        store.weekHistory.reduce(0) { $0 + $1.steps }
    }

    private var prevWeekAverage: Int {
        let month = store.monthHistory
        guard month.count >= 14 else { return 0 }
        let prevWeek = Array(month.dropLast(7).suffix(7))
        let nonZero = prevWeek.filter { $0.steps > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.reduce(0) { $0 + $1.steps } / nonZero.count
    }

    private var trendPercent: Double? {
        guard prevWeekAverage > 0, average > 0 else { return nil }
        return Double(average - prevWeekAverage) / Double(prevWeekAverage) * 100
    }

    private var goalStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sorted = store.monthHistory.sorted { $0.date > $1.date }
        var streak = 0
        var expected = today
        for day in sorted {
            let dayStart = calendar.startOfDay(for: day.date)
            guard dayStart == expected else { break }
            let steps = dayStart == today ? store.stepsToday : day.steps
            if steps >= store.stepGoal {
                streak += 1
                expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
            } else {
                break
            }
        }
        return streak
    }

    var body: some View {
        NavigationStack {
            Group {
                if !HKHealthStore.isHealthDataAvailable() {
                    unavailableView
                } else if !store.isAuthorized {
                    authView
                } else {
                    mainContent
                }
            }
            .navigationTitle("Шаги")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        goalText = "\(store.stepGoal)"
                        showingGoalEditor = true
                    } label: {
                        Image(systemName: "target")
                    }
                }
            }
            .alert("Цель по шагам", isPresented: $showingGoalEditor) {
                TextField("Шаги", text: $goalText)
                    .keyboardType(.numberPad)
                Button("Отмена", role: .cancel) {}
                Button("Сохранить") {
                    if let value = Int(goalText), value > 0 {
                        store.stepGoal = value
                    }
                }
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                todayCard
                chartCard
                trendsCard
                statsCard
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private var todayCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.12), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: min(Double(store.stepsToday) / Double(store.stepGoal), 1.0))
                    .stroke(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.9), value: store.stepsToday)

                VStack(spacing: 4) {
                    Text(store.stepsToday.formatted())
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("шагов")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)

            HStack(spacing: 32) {
                VStack(spacing: 2) {
                    Text(store.distanceTodayKm > 0 ? String(format: "%.1f км", store.distanceTodayKm) : "—")
                        .font(.title3.weight(.semibold))
                    Text("Дистанция")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    let pct = store.stepGoal > 0 ? Int(Double(store.stepsToday) / Double(store.stepGoal) * 100) : 0
                    Text("\(min(pct, 100))%")
                        .font(.title3.weight(.semibold))
                    Text("от цели")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    Text(store.stepGoal.formatted())
                        .font(.title3.weight(.semibold))
                    Text("Цель")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("История")
                    .font(.headline)
                Spacer()
                Picker("Период", selection: $period) {
                    ForEach(StepPeriod.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if history.isEmpty {
                Text("Нет данных")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(history) { day in
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
                    let stride = period == .week ? 1 : 5
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
                .animation(.easeInOut, value: period)
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
                    value: "\(goalStreak)",
                    subtitle: goalStreak == 1 ? "день" : "дней"
                )
                Divider().frame(height: 40)
                statCell(
                    title: "Неделя",
                    value: weeklyTotal > 0 ? weeklyTotal.formatted() : "—",
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
            if let trend = trendPercent {
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
                value: average > 0 ? average.formatted() : "—",
                subtitle: "шагов/день"
            )
            Divider().frame(height: 40)
            statCell(
                title: "Рекорд",
                value: best.map { $0.steps.formatted() } ?? "—",
                subtitle: best.map { $0.date.formatted(.dateTime.day().month(.abbreviated)) } ?? ""
            )
            Divider().frame(height: 40)
            statCell(
                title: "Дней с целью",
                value: "\(daysOnGoal)",
                subtitle: "из \(history.count)"
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
        .padding(32)
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
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
