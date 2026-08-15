import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject var store: CalorieStore
    @State private var showingAdd = false
    @State private var showingAddWeight = false
    @State private var showingGoalEditor = false
    @State private var showingStreakInfo = false
    @State private var editingEntry: FoodEntry? = nil
    @State private var goalText = ""

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(spacing: 24) {
                    ProgressRing(
                        consumed: store.consumedToday,
                        goal: store.todayGoal,
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

                    if store.profile == nil {
                        NavigationLink {
                            ProfileView(store: store)
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                Text("Заполните профиль, чтобы рассчитать цель по калориям и белку")
                                    .font(.footnote)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .foregroundStyle(.blue)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    } else if !store.hasWeighedToday {
                        Button {
                            showingAddWeight = true
                        } label: {
                            HStack {
                                Image(systemName: "scalemass")
                                Text("Не забудь взвеситься сегодня")
                                    .font(.footnote)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .foregroundStyle(.orange)
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        weightKg: store.weightKg,
                        suggestion: store.macroSuggestion
                    )

                    HStack(spacing: 12) {
                        StatCard(
                            title: "Осталось",
                            value: "\(store.remaining)",
                            icon: "flame.fill",
                            color: store.remaining >= 0 ? .green : .red
                        )
                        StatCard(
                            title: "Приёмов пищи",
                            value: "\(store.todayEntries.count)",
                            icon: "fork.knife",
                            color: .blue
                        )
                    }

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
                            VStack(spacing: 0) {
                                ForEach(store.todayEntries) { entry in
                                    EntryRow(
                                        entry: entry,
                                        onDelete: { store.delete(entry: entry) },
                                        onEdit: { editingEntry = entry }
                                    )
                                    if entry.id != store.todayEntries.last?.id {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }

                }
                .padding(.horizontal)
                .padding(.bottom, 80)
                .containerRelativeFrame(.horizontal)
            }
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
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                            Text("\(store.streak)")
                                .font(.subheadline.bold())
                                .monospacedDigit()
                        }
                        .foregroundStyle(store.streak > 0 ? .orange : .secondary)
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
                        Image(systemName: "plus.circle.fill")
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
                StreakInfoSheet(streak: store.streak, bestStreak: store.bestStreak)
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.visible)
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
                Label("План", systemImage: "sparkles")
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

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct StreakInfoSheet: View {
    let streak: Int
    let bestStreak: Int

    private func label(_ n: Int) -> String {
        switch n % 10 {
        case 1 where n % 100 != 11: return "День"
        case 2...4 where !(n % 100 >= 12 && n % 100 <= 14): return "Дня"
        default: return "Дней"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(streak > 0 ? .orange : .secondary)
                Text("\(streak)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(streak > 0 ? .orange : .primary)
                    .monospacedDigit()
            }

            Text(streak > 0 ? "\(label(streak)) подряд" : "Начни сегодня")
                .font(.title3)
                .foregroundStyle(.secondary)

            if bestStreak > streak {
                Label("Рекорд: \(bestStreak) \(label(bestStreak))", systemImage: "trophy.fill")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            }

            Divider()
                .padding(.horizontal, 32)

            VStack(spacing: 8) {
                Text("Чем выше стрик — тем лучше результат.")
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)

                Text("Если ты каждый день вмещаешься в норму, ты точно движешься к цели. Выйди за лимит — стрик обнулится.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    ContentView(store: CalorieStore(context: container.mainContext))
}
