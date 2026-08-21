import SwiftUI
import SwiftData

enum MealPeriod: String, CaseIterable {
    case breakfast = "Завтрак"
    case lunch = "Обед"
    case dinner = "Ужин"
    case snack = "Перекус"

    static func period(for date: Date) -> MealPeriod {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        default: return .snack
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: CalorieStore
    @State private var showingAdd = false
    @State private var showingAddWeight = false
    @State private var showingGoalEditor = false
    @State private var showingStreakInfo = false
    @State private var showingBankInfo = false
    @State private var editingEntry: FoodEntry? = nil
    @State private var goalText = ""

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(spacing: 24) {
                    ProgressRing(
                        consumed: store.consumedToday,
                        goal: store.adaptedTodayGoal,
                        macros: store.macrosToday,
                        proteinTarget: store.proteinTarget,
                        fatTarget: store.fatTarget,
                        carbsTarget: MacroTargets.carbsMinimum
                    )
                    .padding(.top, 12)
                    .onLongPressGesture {
                        guard store.plan?.cyclingEnabled != true else { return }
                        goalText = String(store.dailyGoal)
                        showingGoalEditor = true
                    }

                    if store.calorieBankBonus != 0 {
                        Button { showingBankInfo = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: store.calorieBankBonus > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .foregroundStyle(store.calorieBankBonus > 0 ? .green : .orange)
                                Text(store.calorieBankBonus > 0
                                     ? "+\(store.calorieBankBonus) ккал из недели"
                                     : "\(store.calorieBankBonus) ккал из недели")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingBankInfo) {
                            CalorieBankPopover(
                                bonus: store.calorieBankBonus,
                                baseGoal: store.todayGoal,
                                adaptedGoal: store.adaptedTodayGoal
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                    }

                    if store.profile == nil {
                        NavigationLink {
                            ProfileView(store: store)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                    .font(.footnote)
                                Text("Заполните профиль, чтобы рассчитать цель")
                                    .font(.caption)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    } else if !store.hasWeighedToday {
                        Button {
                            showingAddWeight = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "scalemass")
                                    .font(.footnote)
                                Text("Не забудь взвеситься сегодня")
                                    .font(.caption)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    if let plan = store.plan {
                        NavigationLink {
                            PlanView(store: store)
                        } label: {
                            PlanCard(
                                plan: plan,
                                currentWeight: store.latestWeight?.weightKg,
                                status: store.adherence?.status ?? .insufficientData
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    MacrosCard(
                        macros: store.macrosToday,
                        proteinTarget: store.proteinTarget,
                        fatTarget: store.fatTarget,
                        weightKg: store.weightKg
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Сегодня")
                                .font(.headline)
                            Spacer()
                        }

                        if store.todayEntries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Пока ничего не добавлено")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(store.groupedTodayEntries, id: \.period) { group in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(group.period.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 10)
                                        .padding(.bottom, 4)
                                    ForEach(group.entries) { entry in
                                        EntryRow(
                                            entry: entry,
                                            onDelete: { store.delete(entry: entry) },
                                            onEdit: { editingEntry = entry }
                                        )
                                        if entry.id != group.entries.last?.id {
                                            Divider().padding(.leading, 16)
                                        }
                                    }
                                }
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }

                }
                .padding(.horizontal)
                .padding(.bottom, 80)
                .containerRelativeFrame(.horizontal)
            }
            .refreshable { store.refresh() }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Сегодня")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingStreakInfo = true
                    } label: {
                        StreakBadge(streak: store.streak)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView(store: store)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddEntryView(store: store)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingAddWeight) {
                AddWeightView(store: store)
                    .presentationDetents([.medium])
            }
            .sheet(item: $editingEntry) { entry in
                EditEntrySheet(store: store, entry: entry)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingStreakInfo) {
                StreakInfoSheet(streak: store.streak, bestStreak: store.bestStreak, store: store)
                    .presentationDetents([.height(500)])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: store.consumedToday) { oldValue, newValue in
                let goal = store.adaptedTodayGoal
                if oldValue < goal && newValue >= goal {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            .alert("Дневная цель", isPresented: $showingGoalEditor) {
                TextField("Ккал в день", text: $goalText)
                    .keyboardType(.numberPad)
                Button("Отмена", role: .cancel) { }
                Button("Сохранить") {
                    if let value = Int(goalText), value > 0 {
                        store.dailyGoal = value
                    }
                }
            }
        }
    }
}

private struct PlanCard: View {
    let plan: Plan
    let currentWeight: Double?
    let status: PlanStatus

    private var statusInfo: (text: String, color: Color, icon: String) {
        switch status {
        case .insufficientData: return ("Собираем данные", .secondary, "clock")
        case .onTrack: return ("По графику", .green, "checkmark.circle.fill")
        case .ahead: return ("Опережаешь график", .blue, "arrow.up.circle.fill")
        case .behind: return ("Отстаёшь от графика", .orange, "exclamationmark.triangle.fill")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(plan.title, systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(plan.daysRemaining > 0 ? "\(plan.daysRemaining) дн. осталось" : "Срок истёк")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: plan.progress)
                .tint(.blue)

            HStack {
                Text(String(format: "%.1f → %.1f кг", plan.startWeightKg, plan.targetWeightKg))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let currentWeight {
                    Text(String(format: "сейчас %.1f кг", currentWeight))
                        .font(.caption.weight(.medium))
                }
            }

            Label(statusInfo.text, systemImage: statusInfo.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusInfo.color)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct StreakBadge: View {
    let streak: Int

    private var color: Color {
        if streak >= 100 { return Color(red: 1, green: 0.75, blue: 0) }
        if streak >= 30 { return .red }
        if streak >= 7 { return .orange }
        return streak > 0 ? .orange : .secondary
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
            Text("\(streak)")
                .font(.subheadline.bold())
                .monospacedDigit()
        }
        .foregroundStyle(color)
    }
}

private struct StreakInfoSheet: View {
    let streak: Int
    let bestStreak: Int
    let store: CalorieStore

    private var milestoneColor: Color {
        if streak >= 100 { return Color(red: 1, green: 0.75, blue: 0) }
        if streak >= 30 { return .red }
        if streak >= 7 { return .orange }
        return streak > 0 ? .orange : .secondary
    }

    private var streakLabel: String {
        switch streak % 10 {
        case 1 where streak % 100 != 11: return "день подряд"
        case 2...4 where !(streak % 100 >= 12 && streak % 100 <= 14): return "дня подряд"
        default: return "дней подряд"
        }
    }

    private let milestones: [(Int, String, String)] = [
        (7, "7 дней", "flame"),
        (14, "2 недели", "flame"),
        (30, "Месяц", "trophy"),
        (100, "100 дней", "star")
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(milestoneColor)
                    Text("\(streak)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(milestoneColor)
                        .monospacedDigit()
                }
                Text(streakLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if bestStreak > streak {
                    Label("Рекорд: \(bestStreak) дней", systemImage: "trophy.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .padding(.top, 2)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Последние 14 дней")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                miniCalendar
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                ForEach(milestones, id: \.0) { (days, label, icon) in
                    let reached = streak >= days || bestStreak >= days
                    VStack(spacing: 6) {
                        Image(systemName: "\(icon).fill")
                            .font(.title2)
                            .foregroundStyle(reached ? .orange : Color(.systemGray4))
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(reached ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()

            Spacer()
        }
    }

    private var miniCalendar: some View {
        HStack(spacing: 0) {
            ForEach(store.streakHistory, id: \.date) { day in
                let isToday = Calendar.current.isDateInToday(day.date)
                VStack(spacing: 4) {
                    Circle()
                        .fill(dotColor(for: day))
                        .frame(width: 20, height: 20)
                        .overlay(
                            isToday
                                ? Circle().stroke(Color.primary.opacity(0.5), lineWidth: 2)
                                : nil
                        )
                    Text(dayLetter(day.date))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func dotColor(for day: (date: Date, hasEntries: Bool, onGoal: Bool)) -> Color {
        if day.onGoal { return .green }
        if day.hasEntries { return .orange }
        return Color(.systemGray5)
    }

    private func dayLetter(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        return ["Вс","Пн","Вт","Ср","Чт","Пт","Сб"][weekday - 1]
    }
}

private struct CalorieBankPopover: View {
    let bonus: Int
    let baseGoal: Int
    let adaptedGoal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Недельный баланс")
                .font(.headline)
            Text(bonus > 0
                 ? "На этой неделе ты сэкономил калории — они распределены по оставшимся дням."
                 : "На этой неделе был перерасход — норма сегодня снижена.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                HStack {
                    Text("Базовая норма")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(baseGoal) ккал")
                }
                HStack {
                    Text("Из банка недели")
                        .foregroundStyle(bonus > 0 ? .green : .orange)
                    Spacer()
                    Text(bonus > 0 ? "+\(bonus)" : "\(bonus)")
                        .foregroundStyle(bonus > 0 ? .green : .orange)
                        .fontWeight(.medium)
                }
                Divider()
                HStack {
                    Text("Итого сегодня")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(adaptedGoal) ккал")
                        .fontWeight(.semibold)
                }
            }
            .font(.caption)
        }
        .padding()
        .frame(minWidth: 240)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    ContentView(store: CalorieStore(context: container.mainContext))
}
