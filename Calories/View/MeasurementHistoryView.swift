import SwiftUI

/// Прошлые сеансы замеров.
///
/// Список нужен не ради истории как таковой: колёсико сохраняет сразу, и
/// промахнувшийся сеанс иначе остаётся в базе навсегда — а по последнему
/// считаются и процент жира, и FFMI, и он же наследуется в следующий.
/// Свайп по строке — единственный способ это исправить.
struct MeasurementHistoryView: View {
    var store: CalorieStore

    var body: some View {
        List {
            Section {
                ForEach(store.measurements) { measurement in
                    NavigationLink {
                        MeasurementSnapshotView(measurement: measurement)
                    } label: {
                        row(measurement)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteMeasurement(measurement)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            } footer: {
                Text("Каждый сеанс — полный снимок: незаполненное переносится из прошлого. Промахнулся колёсиком — удали сеанс свайпом, иначе он останется последним и по нему посчитаются выводы.")
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("История замеров")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ measurement: BodyMeasurement) -> some View {
        HStack {
            Text(measurement.date, format: .dateTime.day().month(.abbreviated).year())
            Spacer()
            if let profile = store.profile {
                Text(verbatim: String(format: "%.1f%%", profile.bodyFatPercentage(from: measurement)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Один сеанс целиком, только чтение: посмотреть, что было снято в тот день.
struct MeasurementSnapshotView: View {
    let measurement: BodyMeasurement

    private var rows: [(MeasurementSite, Double)] {
        MeasurementSite.allCases.compactMap { site in
            let value = measurement.best(site)
            return value > 0 ? (site, value) : nil
        }
    }

    var body: some View {
        List {
            if rows.isEmpty {
                Section {
                    Text("В этом сеансе ничего не снято")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(rows, id: \.0) { site, value in
                        HStack {
                            Text(site.title)
                            Spacer()
                            Text(verbatim: String(format: "%g \(String(localized: "см"))", value))
                                .font(.body.weight(.medium))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle(Text(measurement.date, format: .dateTime.day().month(.abbreviated).year()))
        .navigationBarTitleDisplayMode(.inline)
    }
}
