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

                    MacrosCard(macros: store.macrosToday, proteinTarget: store.proteinTarget)
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

private struct MacrosCard: View {
    let macros: Macros
    let proteinTarget: Double?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                macroColumn(title: "Белки", value: macros.protein, color: .blue)
                Divider().frame(height: 36)
                macroColumn(title: "Жиры", value: macros.fat, color: .orange)
                Divider().frame(height: 36)
                macroColumn(title: "Углеводы", value: macros.carbs, color: .purple)
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
    }

    private func macroColumn(title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f г", value))
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
