import SwiftUI

/// Корень вкладки «Тело»: список разделов, а не полотно данных.
/// Всё, что описывает тело, собрано здесь — включая параметры из профиля,
/// которые раньше лежали в настройках и логически туда не относились:
/// рост и уровень активности это про тело, а не про поведение приложения.
struct BodyView: View {
    var store: CalorieStore

    private var latest: BodyMeasurement? { store.latestMeasurement }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ProfileSettingsView(store: store)
                } label: {
                    Label("Профиль", systemImage: "person.crop.circle")
                }
                .accessibilityIdentifier("openProfile")
            } header: {
                Text("Пользователь")
            } footer: {
                Text("Параметры тела, уровень активности и норма белка.")
            }

            Section {
                NavigationLink {
                    MeasurementsView(store: store)
                } label: {
                    row("Замеры", systemImage: "figure.arms.open", detail: measurementsDetail)
                }
                .accessibilityIdentifier("openMeasurements")

                NavigationLink {
                    WeightDetailView(store: store)
                } label: {
                    row("Вес и динамика", systemImage: "scalemass", detail: weightDetail)
                }
                .accessibilityIdentifier("openWeight")
            } header: {
                Text("Антропометрия")
            } footer: {
                Text("Обхваты снимают раз в неделю-две, вес — каждый день. Поэтому они разведены по разным экранам.")
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Тело")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SettingsView(store: store)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityIdentifier("openSettings")
            }
        }
    }

    /// Системная строка: значок, название и текущее значение справа —
    /// чтобы состояние читалось не заходя внутрь.
    private func row(_ title: LocalizedStringKey, systemImage: String, detail: String?) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var measurementsDetail: String? {
        guard let latest else { return String(localized: "Нет замеров") }
        return latest.date.formatted(.dateTime.day().month(.abbreviated))
    }

    private var weightDetail: String? {
        guard let weight = store.latestWeight else { return String(localized: "Нет записей") }
        return String(format: "%.1f \(String(localized: "кг"))", weight.weightKg)
    }
}
