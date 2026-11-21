import SwiftUI

/// Как расписание выглядит в жизни — на примере одного приёма.
///
/// Раньше здесь была диаграмма всех приёмов разом: точки по дням и засечки
/// плана, шесть строк, из которых надо было самому понять, где расписание
/// врёт. Теперь карточка говорит о том приёме, который расходится с планом
/// сильнее всего, и отвечает на три вопроса подряд: где его окно, когда он
/// начинался на самом деле и что с этим делать.
///
/// - Дорожка: серая — отрезок дня, синяя — окно приёма по расписанию, точка —
///   когда в среднем приём начинался.
/// - Фраза: в окне или мимо, ближе к началу, к середине или к концу.
/// - Кнопка: сдвинуть окно на то, на сколько приём в среднем уехал, но не
///   точно по минутам, а по получасам — расписание с «13:25» читать некому.
struct MealWindowCard: View {
    let days: [MealAdherence.Day]
    /// Окна сегодняшнего дня — по ним рисуется дорожка.
    let slots: [MealSchedule.Slot]
    @Bindable var settings: MealScheduleSettings
    /// Окно сдвинули: пересчитать расписание и напоминания.
    var onMoved: () -> Void = {}

    @State private var chosen: MealPeriod?

    private var habits: [MealAdherence.Habit] { MealAdherence.habits(days) }

    /// Приёмы, про которые есть что сказать: у них есть окно на сегодня и
    /// накопленная привычка. «Перекус» — не приём, а всё съеденное мимо окон.
    private var candidates: [(habit: MealAdherence.Habit, slot: MealSchedule.Slot)] {
        habits.compactMap { habit in
            guard habit.period != .nightSnack,
                  let slot = slots.first(where: { $0.period == habit.period }) else { return nil }
            return (habit, slot)
        }
    }

    /// Показываем выбранный приём, а по умолчанию — тот, что уехал дальше всех.
    private var focus: (habit: MealAdherence.Habit, slot: MealSchedule.Slot)? {
        if let chosen, let pick = candidates.first(where: { $0.habit.period == chosen }) { return pick }
        // Тот, что сейчас дальше всех от жизни: после сдвига приём перестаёт
        // быть первым, а не остаётся на месте, цепляя кнопку снова.
        return candidates.max { missBy($0.habit) < missBy($1.habit) }
    }

    private func missBy(_ habit: MealAdherence.Habit) -> Int {
        abs(habit.shiftMinutes - settings.mealOffset(habit.period))
    }

    /// Съеденное мимо расписания за последнюю неделю: сколько раз.
    private var outsideThisWeek: Int {
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date())) ?? Date()
        return days.filter { $0.date >= from }
            .flatMap(\.meals)
            .filter { $0.period == .nightSnack && $0.actualTime != nil }
            .count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let focus {
                if candidates.count > 1 { chips(selected: focus.habit.period) }
                track(focus.habit, focus.slot)
                Text(verbatim: sentence(focus.habit, focus.slot))
                    .font(.app(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
                moveButton(focus.habit, focus.slot)
            } else {
                // Привычку по приёму собирает пять дней с записями: по
                // меньшему числу один проспанный завтрак двигал бы расписание.
                Text(String(format: String(localized: "Пока мало данных: по каждому приёму нужно пять дней с записями. Записано дней: %lld."),
                            days.count))
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }

            if outsideThisWeek > 0 {
                Divider()
                HStack {
                    Text("Мимо расписания")
                    Spacer()
                    Text(String(localized: "\(outsideThisWeek) приёмов за неделю"))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.app(.subheadline))
            }

            if !habits.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(habits) { habit in
                        line(habit)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Дорожка

    private func track(_ habit: MealAdherence.Habit, _ slot: MealSchedule.Slot) -> some View {
        let usual = usualTime(habit, slot)
        let lower = min(slot.start.addingTimeInterval(-90 * 60), usual.addingTimeInterval(-30 * 60))
        let upper = max(slot.end.addingTimeInterval(150 * 60), usual.addingTimeInterval(30 * 60))
        let span = max(upper.timeIntervalSince(lower), 1)
        func share(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(lower) / span) }
        return VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: max(6, width * (share(slot.end) - share(slot.start))), height: 6)
                        .offset(x: width * share(slot.start))
                    Circle()
                        .fill(Color.accentColor)
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 3))
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .offset(x: width * share(usual) - 8)
                }
                .frame(height: 22)
            }
            .frame(height: 22)
            .accessibilityHidden(true)

            HStack {
                Text(verbatim: clock(lower))
                Spacer()
                Text(String(format: String(localized: "окно %1$@–%2$@"), clock(slot.start), clock(slot.end)))
                Spacer()
                Text(verbatim: clock(upper))
            }
            .font(.app(.caption2))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    // MARK: - Слова

    /// «Обед за 9 дн. в среднем начинался в 13:25 — в окне, но ближе к его концу».
    private func sentence(_ habit: MealAdherence.Habit, _ slot: MealSchedule.Slot) -> String {
        let usual = usualTime(habit, slot)
        let where_: String
        if usual < slot.start {
            where_ = String(localized: "раньше окна")
        } else if usual > slot.end {
            where_ = String(localized: "позже окна")
        } else {
            let place = usual.timeIntervalSince(slot.start) / max(slot.end.timeIntervalSince(slot.start), 1)
            where_ = place < 1.0 / 3
                ? String(localized: "в окне, но ближе к его началу")
                : (place > 2.0 / 3
                   ? String(localized: "в окне, но ближе к его концу")
                   : String(localized: "в окне, ближе к середине"))
        }
        return String(format: String(localized: "%1$@ за %2$lld дн. в среднем начинался в %3$@ — %4$@"),
                      mealName(habit.period), habit.days, clock(usual), where_)
    }

    private func mealName(_ period: MealPeriod) -> String {
        String(localized: String.LocalizationValue(period.rawValue))
    }

    /// Одна строка на приём: когда обычно и сколько калорий.
    private func line(_ habit: MealAdherence.Habit) -> some View {
        let single = abs(habit.usualToMinutes - habit.usualFromMinutes) < 10
        let text = single
            ? String(format: String(localized: "обычно около %1$@, в среднем %2$lld ккал"),
                     clock(minutes: (habit.usualFromMinutes + habit.usualToMinutes) / 2), habit.typicalCalories)
            : String(format: String(localized: "обычно между %1$@ и %2$@, в среднем %3$lld ккал"),
                     clock(minutes: habit.usualFromMinutes), clock(minutes: habit.usualToMinutes),
                     habit.typicalCalories)
        return Text("\(Text(verbatim: mealName(habit.period)).font(.app(.footnote, weight: .semibold)))\(Text(verbatim: " " + text).font(.app(.footnote)).foregroundColor(.secondary))")
    }

    // MARK: - Кнопки

    /// Когда приём в среднем начинался. Сдвиг привычки считается от времени
    /// приёма без личного сдвига, поэтому и откладывается от него.
    private func usualTime(_ habit: MealAdherence.Habit, _ slot: MealSchedule.Slot) -> Date {
        slot.time
            .addingTimeInterval(-Double(settings.mealOffset(habit.period)) * 60)
            .addingTimeInterval(Double(habit.shiftMinutes) * 60)
    }

    /// Какой сдвиг приёма нужен, чтобы он совпал с жизнью: полчаса — шаг, «на
    /// 55 минут» расписанием не назвать.
    private func neededOffset(_ habit: MealAdherence.Habit) -> Int {
        Int((Double(habit.shiftMinutes) / 30).rounded()) * 30
    }

    /// Насколько ещё сдвигать от нынешнего. Ноль — приём уже стоит где надо, и
    /// кнопка пропадает: она задаёт сдвиг, а не прибавляет к нему.
    private func step(_ habit: MealAdherence.Habit) -> Int {
        neededOffset(habit) - settings.mealOffset(habit.period)
    }

    @ViewBuilder
    private func moveButton(_ habit: MealAdherence.Habit, _ slot: MealSchedule.Slot) -> some View {
        let step = step(habit)
        let missBy = abs(habit.shiftMinutes - settings.mealOffset(habit.period))
        if missBy >= MealAdherence.noticeableShiftMinutes, step != 0 {
            let start = slot.start.addingTimeInterval(Double(step) * 60)
            let end = slot.end.addingTimeInterval(Double(step) * 60)
            Button {
                // Задаём сдвиг целиком, а не прибавляем: второе нажатие после
                // первого не должно двигать окно снова.
                settings.setMealOffset(neededOffset(habit), for: habit.period)
                onMoved()
            } label: {
                Text(String(format: String(localized: "Сдвинуть окно на %1$@–%2$@"), clock(start), clock(end)))
                    .frame(maxWidth: .infinity)
                    .actionPlate(prominent: false)
            }
            // Системный стиль без обводки: кнопка в строке списка с `.plain`
            // отдаёт тап всей строке.
            .buttonStyle(.borderless)
            .accessibilityIdentifier("moveMealWindow")
        }
    }

    /// Выбор приёма — когда у нескольких есть привычка.
    private func chips(selected: MealPeriod) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(candidates, id: \.habit.id) { item in
                    Button {
                        chosen = item.habit.period
                    } label: {
                        Text(verbatim: mealName(item.habit.period))
                            .font(.app(.footnote, weight: .medium))
                            .foregroundStyle(item.habit.period == selected ? Color(.systemBackground) : Color.primary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(item.habit.period == selected ? Color.primary : Color.secondary.opacity(0.16),
                                        in: Capsule())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Время

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func clock(minutes: Int) -> String {
        let day = Calendar.current.startOfDay(for: Date())
        return clock(Calendar.current.date(byAdding: .minute, value: minutes, to: day) ?? day)
    }
}
