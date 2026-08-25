import SwiftUI
import SwiftData

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
                    // Без горизонтальных отступов: карточки рисуют фон сами и должны
                    // вставать вровень со стеклянными ячейками списка ниже, у которых
                    // фон рисует listRowBackground во всю ширину строки.
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0))
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
                    ForEach(store.groupedTodayEntries, id: \.period) { group in
                        Section {
                            ForEach(group.entries) { entry in
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
                        } header: {
                            // Итог по приёму пищи прямо в заголовке — иначе, чтобы понять,
                            // во сколько обошёлся обед, приходится складывать строки глазами.
                            HStack {
                                Text(LocalizedStringKey(group.period.rawValue))
                                Spacer()
                                Text(verbatim: "\(group.entries.reduce(0) { $0 + $1.calories }) \(String(localized: "ккал"))")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .glassRow()
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
                            .font(.body.weight(.medium))
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

private struct PlanSummaryRow: View {
    let plan: Plan
    let status: PlanStatus

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // На accessibility-размерах четыре элемента в строку не помещаются и наезжают
        // друг на друга — переключаемся на колонку.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Image(systemName: status.icon)
                .font(.footnote)
                .foregroundStyle(status.color)
            Text(plan.title)
                .font(.caption.weight(.medium))
            Text(verbatim: String(format: "· %.1f \(String(localized: "кг"))", plan.targetWeightKg))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
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
