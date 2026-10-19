import SwiftUI
import Charts

/// Как расписание выглядит в жизни: план против факта.
///
/// Расписание до сих пор было обещанием без обратной связи — приложение
/// говорило «завтрак в 8:00» и никогда не сверялось с тем, что человек ест в
/// половине десятого. Здесь видно обе стороны сразу: засечка плана и облако
/// точек — дни, как они были прожиты.
///
/// Показываем только накопленное, без советов «надо раньше»: расписание —
/// инструмент человека, а не норма поведения. Вывод («обычно на час позже»)
/// он сделает сам, а приложение предложит подвинуть план под него.
struct MealAdherenceCard: View {
    let days: [MealAdherence.Day]

    private var habits: [MealAdherence.Habit] { MealAdherence.habits(days) }

    /// Факт одной точкой: приём, время дня в часах, день.
    private struct Point: Identifiable {
        let id = UUID()
        let period: MealPeriod
        let hour: Double
        let planned: Double
    }

    private var points: [Point] {
        let calendar = Calendar.current
        return days.flatMap { day in
            day.meals.compactMap { meal -> Point? in
                guard let actual = meal.actualTime else { return nil }
                return Point(period: meal.period,
                             hour: hours(of: actual, calendar),
                             planned: hours(of: meal.plannedTime, calendar))
            }
        }
    }

    /// Засечки плана — по одной на приём.
    private var plan: [Point] {
        var seen: Set<MealPeriod> = []
        return points.compactMap { point in
            guard !seen.contains(point.period) else { return nil }
            seen.insert(point.period)
            return point
        }
    }

    private func hours(of date: Date, _ calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    var body: some View {
        if points.isEmpty {
            // Молчим, а не показываем пустые оси: пустой график читается как
            // поломка, хотя на самом деле просто ещё нечего показывать.
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                chart
                if !habits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(habits) { habit in
                            line(for: habit)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var chart: some View {
        Chart {
            // Сначала факт, потом план: засечка плана должна лежать поверх
            // облака, иначе её не найти среди точек.
            ForEach(points) { point in
                PointMark(x: .value("Время", point.hour),
                          y: .value("Приём", point.period.rawValue))
                    .foregroundStyle(Color.accentColor.opacity(0.35))
                    .symbolSize(60)
            }
            ForEach(plan) { point in
                // Засечка, а не линия через весь график: `RuleMark` поперёк
                // категорий прочертил бы план одного приёма через чужие
                // строки, и читать их стало бы нельзя.
                RectangleMark(x: .value("По плану", point.planned),
                              y: .value("Приём", point.period.rawValue),
                              width: .fixed(3),
                              height: .fixed(22))
                    .foregroundStyle(.secondary)
                    .cornerRadius(1.5)
            }
        }
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Double.self) {
                        Text(verbatim: "\(Int(hour)):00")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading)
        }
        .frame(height: CGFloat(max(plan.count, 1)) * 34 + 30)
        .font(.app(.caption2))
    }

    /// Границы оси — по самому раннему и позднему, с запасом в час.
    ///
    /// Не сутки целиком: пустая половина графика съедает место, в котором и
    /// живёт вся разница между планом и жизнью.
    private var xDomain: ClosedRange<Double> {
        let all = points.map(\.hour) + plan.map(\.planned)
        let low = (all.min() ?? 6) - 1
        let high = (all.max() ?? 22) + 1
        return max(0, low)...min(24, max(high, low + 3))
    }

    @ViewBuilder
    private func line(for habit: MealAdherence.Habit) -> some View {
        let shift = abs(habit.shiftMinutes)
        let percent = Int((abs(habit.caloriesRatio - 1) * 100).rounded())
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: habit.period.rawValue)
                .font(.app(.caption, weight: .medium))
            Text(verbatim: summary(shift: shift, late: habit.shiftMinutes > 0,
                                   percent: percent, more: habit.caloriesRatio > 1))
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Одна фраза на приём. Когда сходится и время, и порция — так и
    /// говорим: человеку важно знать, что расписание работает, а не только
    /// где оно врёт.
    private func summary(shift: Int, late: Bool, percent: Int, more: Bool) -> String {
        let timeOK = shift < MealAdherence.noticeableShiftMinutes
        let sizeOK = percent < Int(MealAdherence.noticeableRatio * 100)
        switch (timeOK, sizeOK) {
        case (true, true):
            return String(localized: "идёт по плану")
        case (false, true):
            return late
                ? String(format: String(localized: "обычно на %lld мин позже"), shift)
                : String(format: String(localized: "обычно на %lld мин раньше"), shift)
        case (true, false):
            return more
                ? String(format: String(localized: "обычно на %lld%% больше плана"), percent)
                : String(format: String(localized: "обычно на %lld%% меньше плана"), percent)
        case (false, false):
            let when = late
                ? String(format: String(localized: "на %lld мин позже"), shift)
                : String(format: String(localized: "на %lld мин раньше"), shift)
            let how = more
                ? String(format: String(localized: "на %lld%% больше"), percent)
                : String(format: String(localized: "на %lld%% меньше"), percent)
            return String(format: String(localized: "обычно %1$@ и %2$@"), when, how)
        }
    }
}
