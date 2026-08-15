import SwiftUI

struct DayDetailView: View {
    @ObservedObject var store: CalorieStore
    let date: Date
    @State private var showingAdd = false
    @State private var editingEntry: FoodEntry? = nil

    private var day: DaySummary {
        store.summary(for: date)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Итого")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(day.totalCalories) ккал")
                            .font(.title2.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Цель")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(day.goal) ккал")
                            .font(.title2.bold())
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
                        EntryRow(entry: entry, onDelete: { store.delete(entry: entry) }, onEdit: { editingEntry = entry })
                    }
                }
            }
        }
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
        .sheet(isPresented: $showingAdd) {
            AddEntryView(store: store, initialDate: date)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingEntry) { entry in
            EditEntrySheet(store: store, entry: entry)
                .presentationDetents([.medium, .large])
        }
    }
}
