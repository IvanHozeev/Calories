import SwiftUI

struct DayDetailView: View {
    @ObservedObject var store: CalorieStore
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
                        NavigationLink {
                            EditEntrySheet(store: store, entry: entry, isEmbedded: true)
                        } label: {
                            EntryRow(entry: entry)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(entry: entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
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
    }
}
