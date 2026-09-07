import SwiftUI

/// Вкладка «Прогресс» — рабочий экран: как я двигаюсь к цели.
/// План, динамика веса, калории за период и журнал взвешиваний. Всё статическое
/// (рост, возраст, активность, единицы) живёт в «Настройках» под шестерёнкой.
struct WeightDetailView: View {
    var store: CalorieStore
    @State private var showingAddWeight = false
    @State private var rangeDays = 30

    private static let rangeOptions = [7, 30, 90]

    private var recentWeightEntries: [WeightEntry] {
        store.weightHistory(lastDays: rangeDays)
    }

    private var recentCalorieDays: [DaySummary] {
        store.lastDays(rangeDays)
    }

    /// Изменение за период — по тренду на краях, а не по двум сырым числам:
    /// иначе солёный ужин в последний день превращается в «набрал килограмм».
    private var weightChange: Double? {
        guard let first = recentWeightEntries.first, let last = recentWeightEntries.last,
              recentWeightEntries.count > 1,
              let start = store.weightTrend(on: first.date),
              let end = store.weightTrend(on: last.date) else { return nil }
        return end - start
    }

    private var trendPoints: [WeightTrendPoint] {
        recentWeightEntries.map {
            WeightTrendPoint(date: $0.date, weightKg: store.weightTrend(on: $0.date) ?? $0.weightKg)
        }
    }

    var body: some View {
        List {
            
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Текущий вес")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Крупно — трендовый вес, потому что именно он показывает,
                        // куда человек идёт. Последнее взвешивание мельче под ним:
                        // видеть его надо, верить ему как направлению — нет.
                        if let trend = store.weightKg, let latest = store.latestWeight {
                            Text(String(format: "%.1f \(String(localized: "кг"))", trend))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            Text(verbatim: String(format: String(localized: "тренд · последнее %.1f кг, %@"),
                                                  latest.weightKg,
                                                  latest.date.formatted(.dateTime.day().month(.wide))))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let weightChange {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("За период")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%+.1f \(String(localized: "кг"))", weightChange))
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
            .glassRow()

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
            .glassRow()

            if !recentWeightEntries.isEmpty {
                Section {
                    WeightChartView(entries: recentWeightEntries, trend: trendPoints)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                .glassRow()
            } else {
                Section {
                    Text("Пока нет записей веса за этот период")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .glassRow()
            }

            Section {
                WeeklyChartView(days: recentCalorieDays)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Сравни динамику веса с калорийностью выше — если вес не двигается, а цель по калориям — дефицит, стоит перепроверить норму в профиле.")
            }
            .glassRow()

            if !store.weightEntries.isEmpty {
                Section("Все записи") {
                    ForEach(store.weightEntries.reversed()) { entry in
                        HStack {
                            Text(entry.date.formatted(.dateTime.day().month(.wide)))
                            Spacer()
                            Text(String(format: "%.1f \(String(localized: "кг"))", entry.weightKg))
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteWeight(entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                .glassRow()
            }
        }
        .navigationTitle("Вес и динамика")
        .scrollIndicators(.hidden)
        // Плюса в тулбаре нет намеренно: на экране уже есть кнопка «Записать вес»,
        // и делала она ровно то же самое. Две кнопки под одно действие заставляют
        // выбирать там, где выбора нет.
        .sheet(isPresented: $showingAddWeight) {
            AddWeightView(store: store)
                .presentationDetents([.medium])
        }
    }
}
