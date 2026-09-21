import SwiftUI

/// Ближайший приём пищи строкой под кольцом: когда и сколько на него.
///
/// Делить норму в уме приходится каждый день заново, и получается плохо:
/// к вечеру выясняется, что половина дня осталась на один ужин. Здесь видно,
/// сколько отведено на ближайшее окно прямо сейчас — с учётом съеденного
/// и пропущенного.
struct MealScheduleStrip: View {
    let slots: [MealSchedule.Slot]
    var now: Date = Date()
    var onOpen: () -> Void

    private var next: MealSchedule.Slot? { MealSchedule.nextSlot(slots, now: now) }

    private var title: String {
        guard let next else { return String(localized: "День закрыт") }
        let number = next.index + 1
        if next.state == .current {
            return String(format: String(localized: "Сейчас приём %1$lld из %2$lld"), number, slots.count)
        }
        return String(format: String(localized: "Приём %1$lld из %2$lld в %3$@"), number, slots.count,
                      next.start.formatted(date: .omitted, time: .shortened))
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.app(.caption))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.app(.subheadline, weight: .semibold))
                    if let next {
                        Text(verbatim: String(format: String(localized: "%1$lld ккал · окно до %2$@"),
                                              next.calories,
                                              next.end.formatted(date: .omitted, time: .shortened)))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mealScheduleStrip")
    }
}

/// Весь день по приёмам: когда, сколько отведено и что уже съедено.
///
/// Здесь же расписание и настраивается. Настройки жили в «Напоминаниях», и
/// найти их там можно было только зная, что они там есть: на расписание
/// смотрят отсюда, значит и править его логично отсюда.
struct MealScheduleSheet: View {
    /// Съеденное за день и норма — чтобы пересчитывать окна прямо на экране,
    /// пока крутят число приёмов.
    let entries: [(date: Date, calories: Int)]
    let dailyGoal: Int
    @Bindable var settings: MealScheduleSettings
    /// Показан переходом из настроек, а не листом: тогда свой навигационный
    /// стек и кнопка закрытия не нужны — они уже есть снаружи.
    var isEmbedded = false
    @Environment(\.dismiss) private var dismiss

    private var slots: [MealSchedule.Slot] {
        let now = Date()
        return MealSchedule.slots(.init(
            wake: settings.today(settings.wake, now: now),
            sleep: settings.today(settings.sleep, now: now),
            mealCount: settings.count,
            dailyGoal: dailyGoal,
            entries: entries,
            now: now
        ))
    }

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        Group {
            List {
                // Тумблер первым: он включает всё остальное на этом экране,
                // и раньше лежал под расписанием — то есть под тем, чем
                // управляет.
                Section {
                    Toggle("Делить день на приёмы", isOn: $settings.isEnabled)
                        .accessibilityIdentifier("mealScheduleToggle")
                } footer: {
                    Text("Норма делится на равные приёмы, и на «Сегодня» видно, сколько осталось на ближайший.")
                }

                Section {
                    Stepper(value: $settings.count, in: MealSchedule.allowedCounts) {
                        HStack {
                            Text("Приёмов в день")
                            Spacer()
                            Text(verbatim: "\(settings.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityIdentifier("mealCountStepper")
                    DatePicker("Подъём", selection: $settings.wake, displayedComponents: .hourAndMinute)
                    DatePicker("Отбой", selection: $settings.sleep, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Первый приём через 45 минут после подъёма, последний за час до отбоя, остальные поровну между ними.")
                }

                Section {
                    ForEach(slots) { slot in
                        row(slot)
                    }
                } footer: {
                    Text("Пропущенное окно не сгорает: его калории расходятся по оставшимся приёмам.")
                }
            }
            // Напоминания переставляются на выходе: пока крутят стрелки,
            // дёргать систему на каждый тик незачем.
            .onDisappear { MealReminders.reschedule(settings: settings) }
            .glassRow()
            .listStyle(.insetGrouped)
            .navigationTitle("Приёмы пищи")
            .navigationBarTitleDisplayMode(.inline)
            // Закрывать нечего, когда экран открыт переходом: назад ведёт
            // сам навигационный стек.
            .toolbar {
                if !isEmbedded {
                    ToolbarItem(placement: .confirmationAction) {
                        CheckmarkButton { dismiss() }
                    }
                }
            }
        }
    }

    private func row(_ slot: MealSchedule.Slot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(slot.state))
                .font(.app(.footnote))
                .foregroundStyle(color(slot.state))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(format: String(localized: "%1$@ – %2$@"),
                                      slot.start.formatted(date: .omitted, time: .shortened),
                                      slot.end.formatted(date: .omitted, time: .shortened)))
                    .font(.app(.subheadline))
                if slot.consumed > 0 {
                    Text(verbatim: String(format: String(localized: "съедено %lld ккал"), slot.consumed))
                        .font(.app(.caption2))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            Spacer()
            Text(verbatim: "\(slot.calories)")
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(slot.state == .missed ? Color.secondary : ProgressRing.kcalColors[0])
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func icon(_ state: MealSchedule.Slot.State) -> String {
        switch state {
        case .done:     return "checkmark.circle.fill"
        case .missed:   return "arrow.turn.down.right"
        case .current:  return "clock.fill"
        case .upcoming: return "clock"
        }
    }

    private func color(_ state: MealSchedule.Slot.State) -> Color {
        switch state {
        case .done:     return ProgressRing.kcalColors[0]
        case .missed:   return .secondary
        case .current:  return .orange
        case .upcoming: return .secondary
        }
    }
}
