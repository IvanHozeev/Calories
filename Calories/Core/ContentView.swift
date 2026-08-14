import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject var store: CalorieStore
    @State private var showingAdd = false
    @State private var showingGoalEditor = false
    @State private var showingProfile = false
    @State private var goalText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ProgressRing(
                        progress: store.progress,
                        consumed: store.consumedToday,
                        goal: store.dailyGoal
                    )
                    .padding(.top, 12)
                    .onTapGesture {
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
                        .padding(.horizontal)
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
                        .padding(.horizontal)
                    }

                    if let plan = store.plan {
                        NavigationLink {
                            PlanView(store: store)
                        } label: {
                            PlanCard(
                                plan: plan,
                                currentWeight: store.latestWeight?.weightKg,
                                status: store.planAdherence()?.status ?? .insufficientData
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }

                    MacrosCard(
                        macros: store.macrosToday,
                        proteinTarget: store.proteinTarget,
                        weightKg: store.latestWeight?.weightKg ?? store.profile?.weightKg
                    )
                        .padding(.horizontal)

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
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Сегодня")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal)

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
                                    EntryRow(store: store, entry: entry)
                                    if entry.id != store.todayEntries.last?.id {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 80)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Сегодня")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView(store: store)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
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

    @State private var selectedMacro: MacroKind?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                macroColumn(.protein, value: macros.protein, color: .blue)
                Divider().frame(height: 36)
                macroColumn(.fat, value: macros.fat, color: .orange)
                Divider().frame(height: 36)
                macroColumn(.carbs, value: macros.carbs, color: .purple)
            }

            if let proteinTarget, proteinTarget > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Белок: \(Int(macros.protein)) из \(Int(proteinTarget)) г")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ProgressView(value: min(macros.protein / proteinTarget, 1.0))
                        .tint(.blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .popover(item: $selectedMacro) { kind in
            macroPopover(kind)
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

        return VStack(alignment: .leading, spacing: 12) {
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
            } else {
                Text(kind == .protein
                     ? "Чтобы увидеть цель, заполни профиль."
                     : "Чтобы увидеть цель, укажи вес — в профиле или на экране «Вес».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 220)
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
    @ObservedObject var store: CalorieStore
    let entry: FoodEntry

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
                withAnimation {
                    store.delete(entry: entry)
                }
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

#Preview {
    let container = try! ModelContainer(
        for: FoodEntry.self, FoodItem.self, WeightEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    ContentView(store: CalorieStore(context: container.mainContext))
}
