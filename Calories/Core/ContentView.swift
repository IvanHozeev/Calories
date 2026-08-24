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
    var store: CalorieStore
    var stepStore: StepStore
    @State private var showingAdd = false
    @State private var showingAddWeight = false
    @State private var showingGoalEditor = false
    @State private var showingActivity = false
    @State private var showingSteps = false
    @State private var showingBankInfo = false
    @State private var showingPaywall = false
    @State private var showingPlan = false
    @State private var goalText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 24) {
                        ProgressRing(
                            consumed: store.consumedToday,
                            goal: store.adaptedTodayGoal,
                            macros: store.macrosToday,
                            proteinTarget: store.proteinTarget,
                            fatTarget: store.fatTarget,
                            carbsTarget: MacroTargets.carbsMinimum
                        )
                        .padding(.top)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                guard store.plan?.cyclingEnabled != true else { return }
                                goalText = String(store.dailyGoal)
                                showingGoalEditor = true
                            }
                        )

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
                                .background(.ultraThinMaterial, in: Capsule())
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
                        } else if !store.isPremium {
                            Button { showingPaywall = true } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.secondary)
                                    Text("Банк калорий")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        if store.profile == nil {
                            NavigationLink {
                                SettingsView(store: store)
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
                            Button { showingPlan = true } label: {
                                PlanSummaryRow(
                                    plan: plan,
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

                        StepsCard(store: stepStore) { showingSteps = true }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
                }
                .listSectionSeparator(.hidden)

                if store.todayEntries.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Пока ничего не добавлено")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                    }
                    .listSectionSeparator(.hidden)
                } else {
                    ForEach(store.groupedTodayEntries.reversed(), id: \.period) { group in
                        Section(LocalizedStringKey(group.period.rawValue)) {
                            ForEach(group.entries.reversed()) { entry in
                                NavigationLink(value: entry) {
                                    EntryRow(entry: entry)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        store.add(name: entry.name, calories: entry.calories, macros: entry.macros, grams: entry.grams)
                                    } label: {
                                        Image(systemName: "plus.square.on.square")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.delete(entry: entry)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollIndicators(.hidden)
            .refreshable { store.refresh() }
            .navigationDestination(for: FoodEntry.self) { entry in
                EditEntrySheet(store: store, entry: entry, isEmbedded: true)
            }
            .navigationDestination(isPresented: $showingPlan) {
                PlanView(store: store)
            }
            .navigationTitle("Сегодня")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingActivity = true } label: {
                        StreakBadge(streak: store.streak)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
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
                    .presentationDetents([.height(320)])
            }
            .navigationDestination(isPresented: $showingActivity) {
                ActivityView(store: store)
            }
            .navigationDestination(isPresented: $showingSteps) {
                StepsNavigationView(store: stepStore)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(store: store)
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

private struct StepsCard: View {
    var store: StepStore
    var onTap: () -> Void
    @AppStorage("use_imperial") private var useImperial = false

    private var progress: Double {
        guard store.stepGoal > 0 else { return 0 }
        return min(Double(store.stepsToday) / Double(store.stepGoal), 1.0)
    }

    private var distanceText: String? {
        guard store.distanceTodayKm > 0 else { return nil }
        return useImperial
            ? String(format: "%.1f \(String(localized: "ми"))", store.distanceTodayKm * 0.621371)
            : String(format: "%.1f \(String(localized: "км"))", store.distanceTodayKm)
    }

    var body: some View {
        if !store.isAuthorized {
            Button { store.requestAuthorization() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk.circle")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Подключить шаги")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .glassCard()
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onTap) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                progress >= 1 ? Color.green : Color.blue,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut, value: progress)
                        Image(systemName: "figure.walk")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(progress >= 1 ? .green : .blue)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.stepsToday.formatted())
                            .font(.headline)
                            .monospacedDigit()
                        Text("шагов из \(store.stepGoal.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let dist = distanceText {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(dist)
                                .font(.subheadline.weight(.medium))
                            Text("дистанция")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .glassCard()
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ActivityView: View {
    let store: CalorieStore

    private var loggedDays: [DaySummary] {
        store.historyDays.filter { !$0.entries.isEmpty }
    }

    private var milestoneColor: Color {
        if store.streak >= 100 { return Color(red: 1, green: 0.75, blue: 0) }
        if store.streak >= 30 { return .red }
        if store.streak >= 7 { return .orange }
        return store.streak > 0 ? .orange : .secondary
    }

    private var streakLabel: String {
        let s = store.streak
        switch s % 10 {
        case 1 where s % 100 != 11: return String(localized: "день подряд")
        case 2...4 where !(s % 100 >= 12 && s % 100 <= 14): return String(localized: "дня подряд")
        default: return s == 0 ? String(localized: "начни серию сегодня") : String(localized: "дней подряд")
        }
    }

    private var motivationalText: String {
        if store.streak >= 30 { return String(localized: "Продолжай в том же духе — ты уже пример для других!") }
        if store.streak >= 7 { return String(localized: "Продолжай в том же духе — ты в отличной форме!") }
        if store.streak > 0 { return String(localized: "Продолжай в том же духе — каждый день на счету!") }
        return String(localized: "Начни сегодня — первый шаг уже завтра станет серией!")
    }

    private let milestones: [(Int, String, String)] = [
        (7, "7 дней", "flame"),
        (14, "2 недели", "flame"),
        (30, "Месяц", "trophy"),
        (100, "100 дней", "star")
    ]

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        if store.streak > 0 {
                            Text("Ты придерживаешься плана уже")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(milestoneColor)
                            Text("\(store.streak)")
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(milestoneColor)
                                .monospacedDigit()
                        }
                        Text(streakLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if store.bestStreak > store.streak && store.bestStreak > 0 {
                            Label("Рекорд: \(store.bestStreak) дней", systemImage: "trophy.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    miniCalendar

                    Text(motivationalText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 0) {
                        ForEach(milestones, id: \.0) { (days, label, icon) in
                            let reached = store.streak >= days || store.bestStreak >= days
                            VStack(spacing: 6) {
                                Image(systemName: "\(icon).fill")
                                    .font(.title2)
                                    .foregroundStyle(reached ? .orange : Color(.systemGray4))
                                Text(LocalizedStringKey(label))
                                    .font(.caption2)
                                    .foregroundStyle(reached ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if !loggedDays.isEmpty {
                Section("История") {
                    ForEach(loggedDays) { day in
                        NavigationLink {
                            DayDetailView(store: store, date: day.date)
                        } label: {
                            DayRow(day: day)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Журнал")
        .navigationBarTitleDisplayMode(.large)
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
        return Calendar.current.veryShortWeekdaySymbols[weekday - 1]
    }
}

/// Компактное напоминание о плане на «Сегодня»: цель, статус и сколько осталось.
/// Разбор — темп, отклонение, график факт/план — живёт на вкладке «Прогресс»,
/// здесь нужен только повод туда зайти.
private struct PlanSummaryRow: View {
    let plan: Plan
    let status: PlanStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.icon)
                .font(.footnote)
                .foregroundStyle(status.color)
            Text(plan.title)
                .font(.caption.weight(.medium))
            Text(verbatim: String(format: "· %.1f \(String(localized: "кг"))", plan.targetWeightKg))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if plan.daysRemaining > 0 {
                Text("\(plan.daysRemaining) дн. осталось")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Срок истёк")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 10)
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
            if streak > 0 {
                Text("\(streak)")
                    .font(.subheadline.bold())
                    .monospacedDigit()
            }
        }
        .foregroundStyle(color)
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
        .padding(.horizontal)
        .padding(.vertical, 25)
        .frame(minWidth: 240)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    ContentView(store: CalorieStore(context: container.mainContext), stepStore: StepStore())
}
