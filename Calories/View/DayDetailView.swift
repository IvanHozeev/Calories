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
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Итого")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Text("\(day.totalCalories) ккал")
                            .font(.app(.title2, weight: .bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Цель")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Text("\(day.goal) ккал")
                            .font(.app(.title2, weight: .bold))
                    }
                }
                .padding(.vertical, 4)

                MacrosRow(macros: day.totalMacros)
                    .padding(.vertical, 8)
            }

            Section("Приёмы пищи") {
                if day.entries.isEmpty {
                    Text("Пока ничего не добавлено")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(day.entries) { entry in
                        NavigationLink {
                            EditEntrySheet(store: store, entry: entry, isEmbedded: true)
                        } label: {
                            EntryRow(entry: entry,
                                         micros: store.notableMicronutrients(for: entry))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(entry: entry)
                            } label: {
                                Image(systemName: "trash")
                            }
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
                        }
                    }
                }
            }
        }
        .glassRow()
        .navigationTitle(day.date.formatted(.dateTime.day().month(.wide)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .fullScreenCover(isPresented: $showingAdd) {
            AddEntryView(store: store, initialDate: date,
                         onFinish: { showingAdd = false })
        }
    }
}
