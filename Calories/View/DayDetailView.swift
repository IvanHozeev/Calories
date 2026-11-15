import SwiftUI

struct DayDetailView: View {
    var store: CalorieStore
    let date: Date
    @State private var showingAdd = false

    private var day: DaySummary {
        store.summary(for: date)
    }

    var body: some View {
        List {
            // Итог дня одной карточкой: кольцо, число, вердикт словом и три
            // макроса с нормой. Раньше — два числа и строка макросов без нормы.
            Section {
                DaySummaryCard(calories: day.totalCalories, goal: day.goal,
                               macros: day.totalMacros,
                               hasEntries: !day.entries.isEmpty,
                               proteinTarget: store.proteinTarget,
                               fatTarget: store.fatTarget,
                               carbsTarget: store.carbsTarget)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }

            // Пустую секцию не показываем вовсе: заголовок «Приёмы пищи»
            // с подписью «пока ничего не добавлено» под ним — два
            // предложения о том, что в этот день человек не ел, хотя об
            // этом уже сказали числа выше.
            // Приёмы пищи — теми же секциями, что и на «Сегодня».
            //
            // Здесь еда лежала одним плоским списком, без приёмов и без
            // времени: тот же день выглядел по-разному в зависимости от
            // того, с какой стороны на него смотрят — из дневника или из
            // истории.
            ForEach(MealPeriod.group(day.entries), id: \.period) { group in
                Section {
                    ForEach(group.entries) { entry in
                        NavigationLink {
                            EditEntrySheet(store: store, entry: entry, isEmbedded: true)
                        } label: {
                            EntryRow(entry: entry,
                                         micros: store.notableMicronutrients(for: entry),
                                         offersVitamins: store.offersVitamins(named: entry.composition.map(\.name)),
                                         partTraits: { store.foodNamed($0)?.traits ?? [] })
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(entry: entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Удалить")
                        }
                        // Повтор прошлого приёма — сюда же, где его видно.
                        // Люди едят одно и то же, и вчерашний обед чаще
                        // повторяют, чем собирают заново.
                        .swipeActions(edge: .leading) {
                            Button {
                                store.add(name: entry.name, calories: entry.calories,
                                          macros: entry.macros, grams: entry.grams,
                                          components: entry.components)
                            } label: {
                                Image(systemName: "plus.square.on.square")
                            }
                            .tint(.blue)
                            .accessibilityLabel("Повторить приём")
                        }
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(group.period.rawValue))
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(verbatim: MealPeriod.time(of: group.entries))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .textCase(nil)
                }
            }
        }
        .glassRow()
        .safeAreaInset(edge: .bottom) {
            // Добавить в этот день — кнопкой внизу, под большим пальцем, а не
            // только плюсом в шапке: в историю заходят, чтобы дописать забытое.
            Button {
                showingAdd = true
            } label: {
                Text("Добавить в этот день")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondaryAction)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("addToThisDay")
        }
        .screenTitle(day.date.formatted(.dateTime.day().month(.wide)),
                     eyebrow: day.date.formatted(.dateTime.weekday(.wide)),
                     trailingButtons: 1)
        // Дата с днём недели — в шапке, слева, двумя плотными строками. День
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Добавить")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddEntryView(store: store, initialDate: date,
                         onFinish: { showingAdd = false })
            .presentationDetents([.medium, .large])
            .presentationBackground(Color(.systemBackground))
        }
    }
}
