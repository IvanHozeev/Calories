import SwiftUI

struct WeightView: View {
    @ObservedObject var store: CalorieStore
    @State private var showingAddWeight = false
    @State private var rangeDays = 30

    private static let rangeOptions = [7, 30, 90]

    private var recentWeightEntries: [WeightEntry] {
        store.weightHistory(lastDays: rangeDays)
    }

    private var recentCalorieDays: [DaySummary] {
        store.lastDays(rangeDays)
    }

    private var weightChange: Double? {
        guard let first = recentWeightEntries.first, let last = recentWeightEntries.last,
              recentWeightEntries.count > 1 else { return nil }
        return last.weightKg - first.weightKg
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Текущий вес")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let latest = store.latestWeight {
                            Text(String(format: "%.1f кг", latest.weightKg))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            Text("на " + latest.date.formatted(.dateTime.day().month(.wide)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let weightChange {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("За период")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%+.1f кг", weightChange))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(weightChange <= 0 ? .green : .red)
                        }
                    }
                }
                .padding(.vertical, 4)

                Button {
                    showingAddWeight = true
                } label: {
                    Label(store.hasWeighedToday ? "Обновить вес за сегодня" : "Записать вес", systemImage: "plus.circle.fill")
                }
            }

            Section {
                Picker("Период", selection: $rangeDays) {
                    ForEach(Self.rangeOptions, id: \.self) { days in
                        Text("\(days) дн.").tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            if !recentWeightEntries.isEmpty {
                Section {
                    WeightChartView(entries: recentWeightEntries)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Text("Пока нет записей веса за этот период")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                WeeklyChartView(days: recentCalorieDays)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Сравни динамику веса с калорийностью выше — если вес не двигается, а цель по калориям — дефицит, стоит перепроверить норму в профиле.")
            }

            if !store.weightEntries.isEmpty {
                Section("Все записи") {
                    ForEach(store.weightEntries.reversed()) { entry in
                        HStack {
                            Text(entry.date.formatted(.dateTime.day().month(.wide)))
                            Spacer()
                            Text(String(format: "%.1f кг", entry.weightKg))
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteWeight(entry)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Вес")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddWeight) {
            AddWeightView(store: store)
                .presentationDetents([.medium])
        }
    }
}
