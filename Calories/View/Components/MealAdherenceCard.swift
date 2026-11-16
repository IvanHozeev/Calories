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

    /// Приёмы, у которых есть точки, — в порядке дня.
    private var rows: [MealPeriod] {
        let present = Set(points.map(\.period))
        return MealPeriod.allCases.filter { present.contains($0) }
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
        // Строки — в порядке дня, а не в порядке появления данных: ось
        // сама раскладывает категории по тому, какая встретилась первой, и
        // если у первого дня не было завтрака, он оказывался внизу, а
        // «Второй завтрак» наверху. Область задана явно, сверху вниз — от
        // завтрака к ужину.
        .chartYScale(domain: rows.map(\.rawValue))
        .chartYAxis {
            // Подпись по центру своей строки и без линий между строками:
            // выровненные по краю подписи стояли на линиях сетки, а точки —
            // между ними, и строки читались со сдвигом.
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(LocalizedStringKey(name))
                    }
                }
            }
        }
        .frame(height: CGFloat(max(rows.count, 1)) * 34 + 30)
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

    /// Привычка одним предложением: «Завтрак обычно между 8:10 и 9:20, в
    /// среднем 650 ккал».
    ///
    /// Раньше строка говорила «на 42 мин позже» и «на 47 % меньше» — позже и
    /// меньше чего, не сказано: это была разница с планом, которого на экране
    /// рядом нет. Теперь называется само время и сама порция, а сравнить их
    /// с расписанием можно по засечкам на графике выше.
    @ViewBuilder
    private func line(for habit: MealAdherence.Habit) -> some View {
        Text(verbatim: habit.period.rawValue).font(.app(.subheadline, weight: .semibold))
            + Text(verbatim: " " + summary(habit))
                .font(.app(.subheadline))
                .foregroundColor(.secondary)
    }

    private func summary(_ habit: MealAdherence.Habit) -> String {
        let from = clock(habit.usualFromMinutes)
        let to = clock(habit.usualToMinutes)
        // Четверть и три четверти почти совпали — промежутка нет, и «между
        // 8:10 и 8:12» звучало бы как точность, которой у привычки нет.
        if abs(habit.usualToMinutes - habit.usualFromMinutes) < 10 {
            return String(format: String(localized: "обычно около %1$@, в среднем %2$lld ккал"),
                          clock((habit.usualFromMinutes + habit.usualToMinutes) / 2), habit.typicalCalories)
        }
        return String(format: String(localized: "обычно между %1$@ и %2$@, в среднем %3$lld ккал"),
                      from, to, habit.typicalCalories)
    }

    /// Время суток по минутам от полуночи — в формате часов, выбранном на телефоне.
    private func clock(_ minutes: Int) -> String {
        let day = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(byAdding: .minute, value: minutes, to: day) ?? day
        return date.formatted(date: .omitted, time: .shortened)
    }
}
