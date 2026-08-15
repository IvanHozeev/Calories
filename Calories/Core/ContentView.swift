import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject var store: CalorieStore
    @State private var showingAdd = false
    @State private var showingGoalEditor = false
    @State private var showingProfile = false
    @State private var showingStreakInfo = false
    @State private var goalText = ""

    private var weightKg: Double? {
        store.latestWeight?.weightKg ?? store.profile?.weightKg
    }

    private var fatTarget: Double? {
        weightKg.map { $0 * 0.8 }
    }

    // Что приоритетнее добрать на оставшиеся калории:
    // белок → жиры → углеводы. Показываем только первый незакрытый.
    private var macroSuggestion: String? {
        let remaining = store.remaining
        guard remaining > 0, store.profile != nil else { return nil }

        let m = store.macrosToday
        let carbsTarget: Double = 130

        if let pt = store.proteinTarget, pt > 0, m.protein < pt {
            let canEat = Int(min(Double(remaining) / 4.0, pt - m.protein))
            guard canEat > 0 else { return nil }
            return "Добери ещё \(canEat) г белка"
        }
        if let ft = fatTarget, ft > 0, m.fat < ft {
            let canEat = Int(min(Double(remaining) / 9.0, ft - m.fat))
            guard canEat > 0 else { return nil }
            return "Добери ещё \(canEat) г жиров"
        }
        if m.carbs < carbsTarget {
            let canEat = Int(min(Double(remaining) / 4.0, carbsTarget - m.carbs))
            guard canEat > 0 else { return nil }
            return "Добери ещё \(canEat) г углеводов"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(spacing: 24) {
                    ProgressRing(
                        consumed: store.consumedToday,
                        goal: store.todayGoal,
                        macros: store.macrosToday,
                        proteinTarget: store.proteinTarget,
                        fatTarget: fatTarget,
                        carbsTarget: 130
                    )
                    .padding(.top, 12)
                    .onLongPressGesture {
                        guard store.plan?.cyclingEnabled != true else { return }
                        goalText = String(store.dailyGoal)
                        showingGoalEditor = true
                    }

                    if store.profile == nil {
                        Button {
                            showingProfile = true
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
                    } else if !store.hasWeighedToday {
                        NavigationLink {
                            WeightView(store: store)
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
                        weightKg: store.latestWeight?.weightKg ?? store.profile?.weightKg,
                        suggestion: macroSuggestion
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
                                    EntryRow(entry: entry) { store.delete(entry: entry) }
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
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Сегодня")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ProfileView(store: store)
                    } label: {
                        Image(systemName: "person")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        WeightView(store: store)
                    } label: {
                        Image(systemName: "scalemass")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
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

private enum MacroKind: String, Identifiable {
    case protein, fat, carbs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: return "Белки"
        case .fat: return "Жиры"
        case .carbs: return "Углеводы"
        }
    }
}

private struct MacrosCard: View {
    let macros: Macros
    let proteinTarget: Double?
    let weightKg: Double?
    let suggestion: String?

    @State private var selectedMacro: MacroKind?
    @State private var visibleSuggestion: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                macroColumn(.protein, value: macros.protein, color: .blue)
                    .popover(isPresented: Binding(
                        get: { selectedMacro == .protein },
                        set: { if !$0 { selectedMacro = nil } }
                    )) { macroPopover(.protein) }
                Divider().frame(height: 36)
                macroColumn(.fat, value: macros.fat, color: .orange)
                    .popover(isPresented: Binding(
                        get: { selectedMacro == .fat },
                        set: { if !$0 { selectedMacro = nil } }
                    )) { macroPopover(.fat) }
                Divider().frame(height: 36)
                macroColumn(.carbs, value: macros.carbs, color: .purple)
                    .popover(isPresented: Binding(
                        get: { selectedMacro == .carbs },
                        set: { if !$0 { selectedMacro = nil } }
                    )) { macroPopover(.carbs) }
            }

            if let proteinTarget, proteinTarget > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Белок: \(Int(macros.protein.rounded())) из \(Int(proteinTarget.rounded())) г")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ProgressView(value: min(macros.protein / proteinTarget, 1.0))
                        .tint(.blue)
                }
            }

            if let s = visibleSuggestion {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(s)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        // Нет .animation на всём VStack — иначе SwiftUI замеряет идеальный
        // (unconstrained) размер при анимации и временно расширяет контент ScrollView.
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { visibleSuggestion = suggestion }
        .onChange(of: suggestion) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                visibleSuggestion = newValue
            }
        }
    }

    private func value(for kind: MacroKind) -> Double {
        switch kind {
        case .protein: return macros.protein
        case .fat: return macros.fat
        case .carbs: return macros.carbs
        }
    }

    private func macroColumn(_ kind: MacroKind, value: Double, color: Color) -> some View {
        Button {
            selectedMacro = kind
        } label: {
            VStack(spacing: 4) {
                Text(String(format: "%.0f г", value))
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Text(kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Принятый минимум для гормонального здоровья (тестостерон, эстроген, кожа, волосы) — ниже
    /// этого порога исследования фиксируют падение половых гормонов.
    private static let fatMinPerKg = 0.8
    /// RDA (Institute of Medicine) — минимум глюкозы для работы мозга, не зависит от веса.
    private static let carbsMinAbsolute = 130.0

    private func target(for kind: MacroKind) -> Double? {
        switch kind {
        case .protein: return proteinTarget
        case .fat: return weightKg.map { $0 * Self.fatMinPerKg }
        case .carbs: return Self.carbsMinAbsolute
        }
    }

    private func note(for kind: MacroKind) -> String {
        switch kind {
        case .protein: return "Из профиля — норма белка на кг веса под твою цель."
        case .fat: return "≥0.8 г/кг — принятый минимум для гормонального здоровья."
        case .carbs: return "130 г/день — RDA, минимум глюкозы для работы мозга, не зависит от веса."
        }
    }

    private func macroPopover(_ kind: MacroKind) -> some View {
        let total = value(for: kind)
        let target = target(for: kind)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(kind.title)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Факт")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let weightKg, weightKg > 0 {
                        Text(String(format: "%.2f г/кг", total / weightKg))
                            .font(.title2.bold())
                        Text(String(format: "%.0f г при весе %.1f кг", total, weightKg))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(format: "%.0f г", total))
                            .font(.title2.bold())
                    }
                }

                Divider()

                if let target {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Цель" + (kind == .carbs ? " (минимум)" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if kind != .carbs, let weightKg, weightKg > 0 {
                            Text(String(format: "%.2f г/кг", target / weightKg))
                                .font(.title3.bold())
                            Text(String(format: "≈ %.0f г", target))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(format: "%.0f г", target))
                                .font(.title3.bold())
                        }
                    }

                    Text(note(for: kind))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(kind == .protein
                         ? "Чтобы увидеть цель, заполни профиль."
                         : "Чтобы увидеть цель, укажи вес — в профиле или на экране «Вес».")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
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

private struct EntryRow: View {
    let entry: FoodEntry
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                Text("Б\(Int(entry.macros.protein)) Ж\(Int(entry.macros.fat)) У\(Int(entry.macros.carbs)) · " + entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(entry.calories) ккал")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Button {
                withAnimation { onDelete() }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
        }
        .padding()
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
