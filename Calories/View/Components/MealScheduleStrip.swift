import SwiftUI
import WidgetKit

/// Ближайший приём пищи строкой под кольцом: когда и сколько на него.
///
/// Делить норму в уме приходится каждый день заново, и получается плохо:
/// к вечеру выясняется, что половина дня осталась на один ужин. Здесь видно,
/// сколько отведено на ближайшее окно прямо сейчас — с учётом съеденного
/// и пропущенного.
struct MealScheduleStrip: View {
    let slots: [MealSchedule.Slot]
    /// Сколько осталось от дневной нормы и какова она сама — чтобы не
    /// объявлять день закрытым, пока есть что есть.
    var remainingToday: Int = 0
    var dailyGoal: Int = 0
    var now: Date = Date()
    var onOpen: () -> Void

    private var next: MealSchedule.Slot? { MealSchedule.nextSlot(slots, now: now) }

    private var title: String {
        guard let next else {
            // Приёмы кончились, а норма — нет: так бывает, если человек ел
            // мало весь день. Говорить «день закрыт» в этот момент значит
            // спорить с кольцом, где висит остаток.
            guard MealSchedule.isDayClosed(remaining: remainingToday, goal: dailyGoal) else {
                return String(format: String(localized: "Осталось %lld ккал"), remainingToday)
            }
            return String(localized: "День закрыт")
        }
        // По названию, а не по номеру: «полдник» человек понимает сразу, а
        // «приём 4 из 5» заставляет пересчитывать, что это за еда.
        let name = String(localized: String.LocalizationValue(next.period.rawValue))
        // Зовём есть по времени приёма, а не по началу его окна.
        //
        // Окно открывается на середине пути от прошлого приёма — у полдника в
        // 16:00 это половина третьего, — и строка звала полдничать за час
        // двадцать до него. Окно нужно, чтобы решить, куда засчитать
        // съеденное; человеку показываем сам приём.
        if next.state == .current, now >= next.time {
            return next.period.timeTitle
        }
        // А до тех пор — через сколько. Час в этом месте бесполезен: «обед в
        // 13:20» надо вычитать из текущего времени в уме.
        return String(format: String(localized: "%1$@ через %2$@"), name,
                      MealScheduleStrip.countdown(to: next.time, from: now))
    }

    /// «2 ч 40 мин» или «25 мин» — сколько ждать.
    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let hours = minutes / 60
        guard hours > 0 else { return String(format: String(localized: "%lld мин"), minutes) }
        guard minutes % 60 > 0 else { return String(format: String(localized: "%lld ч"), hours) }
        return String(format: String(localized: "%1$lld ч %2$lld мин"), hours, minutes % 60)
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
                        // Начатый приём показывает остаток, а не порцию целиком:
                        // человек уже что-то съел, и «700 ккал» он прочитает как
                        // «ещё 700», хотя четырёхсот из них уже нет.
                        Text(verbatim: next.consumed > 0
                             ? String(format: String(localized: "ещё %lld ккал"), next.calories)
                             : String(format: String(localized: "%lld ккал"), next.calories))
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
    /// Дневник — чтобы напоминания знали, чем человек обычно закрывает приём.
    /// Необязательный: экран показывают и из настроек, где дневника нет.
    var store: CalorieStore? = nil
    /// Показан переходом из настроек, а не листом: тогда свой навигационный
    /// стек и кнопка закрытия не нужны — они уже есть снаружи.
    var isEmbedded = false
    @Environment(\.dismiss) private var dismiss

    /// Есть ли в расписании второй ужин — единственный приём, время которого
    /// зависит от отбоя.
    private var hasSecondDinner: Bool {
        MealSchedule.periods(count: settings.count).contains(.secondDinner)
    }

    private var slots: [MealSchedule.Slot] {
        MealSchedule.slots(settings: settings, entries: entries, dailyGoal: dailyGoal)
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
                    explain("Норма делится на равные приёмы, и на «Сегодня» видно, сколько осталось на ближайший.").map { Text($0) }
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
                    // Отбой спрашиваем, только когда он на что-то влияет:
                    // от него считается время второго ужина, а он бывает
                    // лишь при шести приёмах. На пяти приёмах строка стояла
                    // как настройка, которая ничего не меняет.
                    if hasSecondDinner {
                        DatePicker("Отбой", selection: $settings.sleep, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    explain(hasSecondDinner
                            ? String(localized: "Завтрак в 8:00, обед в 13:00, ужин в 19:00. Второй завтрак и полдник — ровно между ними, второй ужин — между ужином и отбоем.")
                            : String(localized: "Завтрак в 8:00, обед в 13:00, ужин в 19:00. Второй завтрак и полдник — ровно между ними."))
                        .map { Text(verbatim: $0) }
                }

                Section {
                    ForEach(slots) { slot in
                        row(slot)
                    }
                } footer: {
                    explain("Съеденный приём закрывается сразу, не дожидаясь конца окна. Пропущенное окно не сгорает: его калории расходятся по оставшимся приёмам.").map { Text($0) }
                }
            }
            // Напоминания переставляются на выходе: пока крутят стрелки,
            // дёргать систему на каждый тик незачем.
            .onDisappear {
                MealReminders.reschedule(settings: settings, store: store)
                // Виджет на блокировке живёт расписанием: правку он должен
                // увидеть сразу, а не на следующей перестройке кэшей.
                store?.publishMealsToWidget()
                WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesMealWidget")
            }
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
                Text(LocalizedStringKey(slot.period.rawValue))
                    .font(.app(.subheadline, weight: .medium))
                // У перекуса часов нет: это не окно расписания, а всё, что
                // съедено мимо окон.
                if slot.period == .nightSnack {
                    Text("Мимо расписания")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                } else {
                    // Время приёма, а не края окна: край первого совпадает с
                    // подъёмом, край последнего — с отбоем, и человек читал
                    // это как «поешь ровно когда проснёшься» и «ровно перед
                    // сном».
                    Text(verbatim: String(format: String(localized: "в %@"),
                                          slot.time.formatted(date: .omitted, time: .shortened)))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                if slot.consumed > 0 {
                    // Только съеденное, без «на столько-то больше».
                    //
                    // Перебор на приёме сравнивался с планом, который сам
                    // меняется: пропущенный завтрак раскидывается по
                    // оставшимся окнам, и съевший свои 831 во второй завтрак
                    // читал «на 473 больше», хотя за день не съел ничего
                    // лишнего. Счёт идёт по дню, а не по окнам.
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
