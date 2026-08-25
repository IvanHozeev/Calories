import SwiftUI

/// Вкладка «Прогресс» — рабочий экран: как я двигаюсь к цели.
/// План, динамика веса, калории за период и журнал взвешиваний. Всё статическое
/// (рост, возраст, активность, единицы) живёт в «Настройках» под шестерёнкой.
struct ProgressDashboardView: View {
    var store: CalorieStore
    @State private var showingAddWeight = false
    @State private var showingPlan = false
    @State private var showingPaywall = false
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
                ProfilePlanCard(
                    store: store,
                    onOpenPlan: { showingPlan = true },
                    onShowPaywall: { showingPaywall = true }
                )
                // Карточка рисует фон сама, поэтому строке отступы не нужны вовсе:
                // системные отступы insetGrouped накладывались поверх и делали карточку
                // уже соседних секций, где фон рисует listRowBackground во всю строку.
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Текущий вес")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let latest = store.latestWeight {
                            Text(String(format: "%.1f \(String(localized: "кг"))", latest.weightKg))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            Text(verbatim: String(format: String(localized: "на %@"), latest.date.formatted(.dateTime.day().month(.wide))))
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
                    WeightChartView(entries: recentWeightEntries)
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
        .navigationTitle("Прогресс")
        // Ширину задаём отступом всего списка, а не отдельных строк: стеклянный фон
        // ячейки рисует listRowBackground во всю строку и на listRowInsets не
        // реагирует, поэтому карточки и ячейки сужаются только вместе со списком.
        // Свой фон списка гасим и красим полную ширину сами — иначе в отступах
        // просвечивает белый фон окна и по краям экрана идёт светлая полоса.
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 16)
        .background(Color(.systemGroupedBackground))
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddWeight = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ProfileSettingsView(store: store)
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
            // Шестерёнка остаётся последней: UI-тест ищет настройки по крайней
            // правой кнопке, да и по привычке ей место с краю.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView(store: store)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .navigationDestination(isPresented: $showingPlan) {
            PlanView(store: store)
        }
        .sheet(isPresented: $showingAddWeight) {
            AddWeightView(store: store)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(store: store, focus: .plan)
        }
    }
}
