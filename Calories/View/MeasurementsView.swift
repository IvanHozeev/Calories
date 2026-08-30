import SwiftUI

/// Замеры: экран показывает, что из снятых обхватов следует, а сам ввод живёт
/// за линейкой в тулбаре. Пропорция обращений именно такая — мерить садишься
/// раз в неделю-две, а смотреть на выводы хочется каждый раз.
struct MeasurementsView: View {
    var store: CalorieStore

    @State private var showingEntry = false

    var body: some View {
        List {
            if let latest = store.latestMeasurement {
                let insights = BodyAnalysis.insights(measurement: latest, profile: store.profile)
                if insights.isEmpty {
                    Section { notEnoughYet } .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    resultsSection(insights, measuredOn: latest.date)
                }
            } else {
                Section { emptyState } .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Замеры")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEntry = true
                } label: {
                    Image(systemName: "ruler")
                }
                .accessibilityIdentifier("openMeasurementEntry")
            }
        }
        .fullScreenCover(isPresented: $showingEntry) {
            NavigationStack {
                MeasurementEntryView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Готово") { showingEntry = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
        }
    }

    private func resultsSection(_ insights: [BodyInsight], measuredOn date: Date) -> some View {
        Section {
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
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(insight.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        } header: {
            HStack {
                Text("Результаты")
                Spacer()
                Text(date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassRow()
    }

    // MARK: - Пусто

    /// Замеры есть, но их мало: почти каждый вывод требует пары обхватов,
    /// и по одному числу сказать нечего.
    private var notEnoughYet: some View {
        placeholder(
            icon: "ruler",
            title: "Пока нечего показать",
            text: "Большинство выводов считается по паре обхватов. Сними ещё несколько — талию, пояс, шею и запястье, они дают больше всего."
        )
    }

    private var emptyState: some View {
        placeholder(
            icon: "figure.arms.open",
            title: "Замеров пока нет",
            text: "Сними обхваты лентой — приложение посчитает пропорции и покажет, что растёт, а что отстаёт."
        )
    }

    private func placeholder(icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingEntry = true
            } label: {
                Label("Снять замеры", systemImage: "ruler")
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
