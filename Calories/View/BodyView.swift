import SwiftUI

/// Вкладка «Тело»: замеры, симметрия и отчёт о телосложении.
/// Вес с графиками живёт на отдельном экране отсюда — он тоже про тело,
/// но меняется ежедневно, а обхваты снимают раз в неделю-две.
struct BodyView: View {
    var store: CalorieStore

    @State private var showingEntry = false
    @State private var editingMeasurement: BodyMeasurement?
    @State private var showingHistory = false

    private var latest: BodyMeasurement? { store.latestMeasurement }
    private var previous: BodyMeasurement? { store.previousMeasurement }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    WeightDetailView(store: store)
                } label: {
                    weightRow
                }
            }
            .glassRow()

            if let latest {
                measurementsSection(latest)
                symmetrySection(latest)
                insightsSection(latest)
                mccallumSection(latest)
            } else {
                Section {
                    emptyState
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addMeasurement")
            }
        }
        .sheet(isPresented: $showingEntry) {
            MeasurementEntryView(store: store)
        }
        .sheet(item: $editingMeasurement) { measurement in
            MeasurementEntryView(store: store, editing: measurement)
        }
    }

    // MARK: - Вес

    private var weightRow: some View {
        HStack {
            Image(systemName: "scalemass")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Вес и динамика")
                if let latest = store.latestWeight {
                    Text(String(format: "%.1f \(String(localized: "кг"))", latest.weightKg))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Нет записей")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Замеры

    private func measurementsSection(_ m: BodyMeasurement) -> some View {
        Section {
            ForEach(MeasurementSite.allCases) { site in
                valueRow(site, m)
            }
        } header: {
            HStack {
                Text("Замеры")
                Spacer()
                Text(m.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Button("Править этот замер") { editingMeasurement = m }
                .font(.footnote)
        }
        .glassRow()
    }

    @ViewBuilder
    private func valueRow(_ site: MeasurementSite, _ m: BodyMeasurement) -> some View {
        let current = m.best(site)
        if current > 0 {
            HStack {
                Text(site.title)
                Spacer()
                if let delta = delta(site) {
                    Text(String(format: "%+.1f", delta))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(delta > 0 ? .green : .orange)
                        .monospacedDigit()
                }
                Text(String(format: "%.1f", current))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
            }
        }
    }

    /// Изменение относительно предыдущего сеанса — ради этого замеры и хранятся историей.
    private func delta(_ site: MeasurementSite) -> Double? {
        guard let latest, let previous else { return nil }
        let now = latest.best(site)
        let before = previous.best(site)
        guard now > 0, before > 0, abs(now - before) >= 0.1 else { return nil }
        return now - before
    }

    // MARK: - Симметрия

    @ViewBuilder
    private func symmetrySection(_ m: BodyMeasurement) -> some View {
        let results = BodyAnalysis.symmetry(m)
        if !results.isEmpty {
            Section {
                ForEach(results) { result in
                    HStack {
                        Text(result.site.title)
                        Spacer()
                        Text(String(format: "%.1f / %.1f", result.left, result.right))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(String(format: "%.1f", result.difference))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(result.verdict.color)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("Симметрия")
            } footer: {
                Text("Слева/справа и расхождение. До 1 см — погрешность ленты, свыше 2 см стоит смотреть.")
            }
            .glassRow()
        }
    }

    // MARK: - Отчёт

    @ViewBuilder
    private func insightsSection(_ m: BodyMeasurement) -> some View {
        let insights = BodyAnalysis.insights(measurement: m, profile: store.profile)
        if !insights.isEmpty {
            Section("Отчёт") {
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(insight.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(insight.verdictLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(insight.verdict.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(insight.verdict.color.opacity(0.12), in: Capsule())
                        }
                        Text(insight.value)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(insight.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }
            }
            .glassRow()
        }
    }

    // MARK: - Идеалы МакКаллума

    @ViewBuilder
    private func mccallumSection(_ m: BodyMeasurement) -> some View {
        if let ideal = BodyAnalysis.mccallum(wristCm: m.best(.wrist)) {
            Section {
                idealRow("Грудь", m.chestCm, ideal.chest)
                idealRow("Талия", m.waistCm, ideal.waist, lowerIsBetter: true)
                idealRow("Бицепс", m.best(.biceps), ideal.arm)
                idealRow("Предплечье", m.best(.forearm), ideal.forearm)
                idealRow("Шея", m.neckCm, ideal.neck)
                idealRow("Бедро", m.best(.thigh), ideal.thigh)
                idealRow("Икра", m.best(.calf), ideal.calf)
            } header: {
                Text("Потолок по костяку")
            } footer: {
                Text(String(format: String(localized: "Формула МакКаллума от запястья %.1f см. Ориентир пропорций, а не цель любой ценой."), m.best(.wrist)))
            }
            .glassRow()
        }
    }

    @ViewBuilder
    private func idealRow(_ title: LocalizedStringKey, _ current: Double, _ target: Double, lowerIsBetter: Bool = false) -> some View {
        if current > 0 {
            let reached = lowerIsBetter ? current <= target : current >= target
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f / %.1f", current, target))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(reached ? .green : .primary)
            }
        }
    }

    // MARK: - Пусто

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.arms.open")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Замеров пока нет")
                .font(.headline)
            Text("Сними обхваты лентой — приложение посчитает симметрию, пропорции и покажет, что растёт, а что отстаёт.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingEntry = true
            } label: {
                Label("Первый замер", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }
}
