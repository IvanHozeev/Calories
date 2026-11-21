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
    /// Что делать, когда приём уже начался: добавить еду, а не открыть
    /// расписание. Отдельной подсказки «Пора есть» больше нет — она говорила
    /// про тот же приём, что и плитка, и стояла строкой ниже.
    var onEat: (() -> Void)? = nil

    private var next: MealSchedule.Slot? { MealSchedule.nextSlot(slots, now: now) }

    /// Приём начался, а еды за него ещё нет.
    ///
    /// То же условие, по которому строка звала есть: время приёма наступило,
    /// а он не закрыт. Считается здесь, а не на экране, — иначе плитка и
    /// строка разошлись бы в том, «пора» или ещё нет.
    private var isTimeToEat: Bool {
        guard let next else { return false }
        return next.state == .current && now >= next.time
    }

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

    /// Та же строка, но плиткой: сверху — какой приём, крупно — когда,
    /// подписью — сколько на него отведено.
    ///
    /// Разложено на три куска именно здесь, рядом с полосой, чтобы правило
    /// «начатый приём показывает остаток» и «день закрыт только когда норма
    /// действительно добрана» не разошлись между двумя видами одного и того
    /// же.
    var tile: TodayTile {
        // Тип замыкания называем явно: тернарник с необязательным замыканием
        // в списке аргументов вешает проверку типов.
        let tap: () -> Void = isTimeToEat ? (onEat ?? onOpen) : onOpen
        return TodayTile(icon: isTimeToEat ? "clock.fill" : "fork.knife",
                         // Коралл только тут: тёплый цвет зовёт к еде, и
                         // больше нигде в приложении его нет.
                         tint: isTimeToEat ? Palette.mealTime : Color.accentColor,
                         label: tileLabel,
                         value: tileValue,
                         caption: tileCaption,
                         identifier: "mealScheduleStrip",
                         onTap: tap)
    }

    private var tileLabel: String {
        guard let next else { return String(localized: "Приёмы пищи") }
        if isTimeToEat { return String(localized: "Пора есть") }
        return String(localized: String.LocalizationValue(next.period.rawValue))
    }

    /// Крупным — когда. Это и есть вопрос, с которым на плитку смотрят.
    ///
    /// Когда пора есть, вопрос уже другой — «что именно», поэтому крупным
    /// идёт название приёма, а «пора есть» сказано подписью сверху.
    private var tileValue: String {
        guard let next else { return title }
        if isTimeToEat { return String(localized: String.LocalizationValue(next.period.rawValue)) }
        return String(format: String(localized: "через %@"),
                      MealScheduleStrip.countdown(to: next.time, from: now))
    }

    private var tileCaption: String? {
        guard let next else { return nil }
        return next.consumed > 0
            ? String(format: String(localized: "ещё %lld ккал"), next.calories)
            : String(format: String(localized: "%lld ккал"), next.calories)
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
    /// Растёт, когда окно сдвинули кнопкой: смещения лежат в UserDefaults, и
    /// экран сам об этом не узнает.
    @State private var slotsTick = 0

    /// Есть ли в расписании второй ужин — единственный приём, время которого
    /// зависит от отбоя.
    private var hasSecondDinner: Bool {
        MealSchedule.periods(count: settings.count).contains(.secondDinner)
    }

    private var slots: [MealSchedule.Slot] {
        _ = slotsTick
        return MealSchedule.slots(settings: settings, entries: entries, dailyGoal: dailyGoal)
    }

    /// Прожитые дни для сверки плана с фактом. Без дневника сверять нечего —
    /// экран открывают и из настроек, где стора нет.
    private var adherence: [MealAdherence.Day] {
        guard settings.isEnabled, let store else { return [] }
        _ = slotsTick
        return store.adherenceDays(schedule: settings)
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
                // Порядок — как в макете: сначала день, как он идёт, потом
                // как он получается, и только потом настройки. Раньше
                // сверху стояли тумблер и степпер, и до самого дня надо было
                // долистывать.
                if settings.isEnabled {
                    Section {
                        timeline
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    } header: {
                        Text("Сегодня").listSectionTitle()
                    } footer: {
                        explain("Съеденный приём закрывается сразу, не дожидаясь конца окна. Пропущенное окно не сгорает: его калории расходятся по оставшимся приёмам.").map { Text($0) }
                    }

                    // Как расписание выглядит в жизни — ниже самого дня и выше
                    // настроек: сначала смотрят, сходится ли план с прожитыми
                    // днями, потом правят.
                    if !adherence.isEmpty {
                        Section {
                            MealWindowCard(days: adherence, slots: slots, settings: settings,
                                           onMoved: { slotsTick += 1 })
                        } header: {
                            Text("Как получается").listSectionTitle()
                        } footer: {
                            explain("Серая дорожка — часть дня, синяя — окно приёма по расписанию, точка — когда приём в среднем начинался. Считается по дням с записями, начиная с пятого.").map { Text($0) }
                        }
                    }
                }

                Section {
                    // Тумблер первым в своей карточке: он включает всё
                    // остальное на этом экране.
                    Toggle("Делить день на приёмы", isOn: $settings.isEnabled)
                        .accessibilityIdentifier("mealScheduleToggle")

                    // Минус, число, плюс — как в макете: системный степпер
                    // рисовал две серые половинки, у которых число жило
                    // слева от них.
                    HStack(spacing: 4) {
                        Text("Приёмов в день")
                        Spacer()
                        countButton("minus", label: "Меньше приёмов",
                                    enabled: settings.count > MealSchedule.allowedCounts.lowerBound) {
                            settings.count -= 1
                        }
                        Text(verbatim: "\(settings.count)")
                            .font(.app(.body, weight: .semibold))
                            .monospacedDigit()
                            .frame(minWidth: 20)
                            .accessibilityIdentifier("mealCountValue")
                        countButton("plus", label: "Больше приёмов",
                                    enabled: settings.count < MealSchedule.allowedCounts.upperBound) {
                            settings.count += 1
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("mealCountStepper")

                    DatePicker("Подъём", selection: $settings.wake, displayedComponents: .hourAndMinute)
                    // Отбой — всегда, как в макете: он закрывает последнее
                    // окно дня, и без него «подъём» остаётся без пары. От него
                    // же считается время второго ужина.
                    DatePicker("Отбой", selection: $settings.sleep, displayedComponents: .hourAndMinute)
                    Toggle("Напоминать взвешиваться", isOn: $settings.remindsWeighIn)
                    if settings.remindsWeighIn {
                        DatePicker("Взвешивание", selection: $settings.weighIn,
                                   displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Расписание").listSectionTitle()
                } footer: {
                    explain(hasSecondDinner
                            ? String(localized: "Завтрак в 8:00, обед в 13:00, ужин в 19:00. Второй завтрак и полдник — ровно между ними, второй ужин — между ужином и отбоем.")
                            : String(localized: "Завтрак в 8:00, обед в 13:00, ужин в 19:00. Второй завтрак и полдник — ровно между ними."))
                        .map { Text(verbatim: $0) }
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
            .contentMargins(.top, 4, for: .scrollContent)
            .screenTitle(String(localized: "Приёмы пищи"),
                         trailingButtons: isEmbedded ? 0 : 1)
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

    /// Круглая кнопка «−» или «+»: серая подложка тридцать два, касание сорок четыре.
    private func countButton(_ symbol: String, label: LocalizedStringKey, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(.footnote, weight: .bold))
                .foregroundStyle(Color.primary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.16), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // Системный стиль без обводки: две кнопки в одной строке списка с
        // `.plain` отдают тап строке, и нажимались обе.
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    /// День по приёмам одной лентой: слева рейка с отметками, справа что и когда.
    ///
    /// Отметка — состояние приёма: залитая галочка, если съеден; кольцо
    /// акцента, если пора; серая точка, если ещё нет. Рейка соединяет их
    /// в один день, а не в семь отдельных строк.
    private var timeline: some View {
        VStack(spacing: 0) {
            weighInRow
            ForEach(slots) { slot in
                row(slot)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 2)
                .padding(.leading, 27)
                .padding(.vertical, 32)
        }
        .tileSurface(cornerRadius: 20)
    }

    /// Когда съеден приём: время первой записи в его окне.
    private func eatenAt(_ slot: MealSchedule.Slot) -> Date? {
        entries.filter { $0.date >= slot.start && $0.date <= slot.end && $0.calories > 0 }
            .map(\.date).min()
    }

    /// Взвешивание в ленте дня — с галочкой, когда оно уже сделано.
    @ViewBuilder
    private var weighInRow: some View {
        if settings.remindsWeighIn {
            let done = store?.hasWeighedToday ?? false
            timelineRow(marker: marker(done: done, current: false),
                        title: Text("Взвешивание").font(.app(.body)),
                        caption: String(format: String(localized: "в %@"),
                                        settings.weighIn.formatted(date: .omitted, time: .shortened)),
                        trailing: nil)
        }
    }

    private func row(_ slot: MealSchedule.Slot) -> some View {
        let name = Text(LocalizedStringKey(slot.period.rawValue))
        let window = "\(slot.start.formatted(date: .omitted, time: .shortened))–\(slot.end.formatted(date: .omitted, time: .shortened))"
        let caption: String
        let title: Text
        let trailing: Text?
        switch slot.state {
        case .done:
            // Съеден — когда именно, а не «съедено столько-то»: сколько,
            // стоит справа, и счёт идёт по дню, а не по окнам.
            title = name.font(.app(.body))
            caption = eatenAt(slot).map {
                window + " · " + String(format: String(localized: "съеден в %@"),
                                        $0.formatted(date: .omitted, time: .shortened))
            } ?? window
            trailing = Text("\(Text(verbatim: "\(slot.consumed.formatted()) "))\(Text("ккал").font(.app(.caption)).foregroundColor(.secondary))")
        case .current:
            title = Text(String(format: String(localized: "%@ — пора есть"),
                                String(localized: String.LocalizationValue(slot.period.rawValue))))
                .font(.app(.body, weight: .semibold))
            caption = window
            trailing = Text(verbatim: "≈ \(slot.calories.formatted())").foregroundColor(.secondary)
        case .missed, .upcoming:
            title = name.font(.app(.body))
            // У перекуса часов нет: это не окно расписания, а всё, что
            // съедено мимо окон.
            caption = slot.period == .nightSnack ? String(localized: "Мимо расписания") : window
            trailing = Text(verbatim: "≈ \(slot.calories.formatted())").foregroundColor(.secondary)
        }
        return timelineRow(marker: marker(for: slot.state), title: title, caption: caption,
                           trailing: trailing)
    }

    private func timelineRow(marker: some View, title: Text, caption: String, trailing: Text?) -> some View {
        HStack(spacing: 14) {
            marker
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                title
                Text(verbatim: caption)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if let trailing {
                trailing
                    .font(.app(.subheadline))
                    .monospacedDigit()
            }
        }
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }

    /// Отметка приёма на рейке.
    @ViewBuilder
    private func marker(for state: MealSchedule.Slot.State) -> some View {
        switch state {
        case .done:     marker(done: true, current: false)
        case .current:  marker(done: false, current: true)
        case .missed:   Circle().fill(Color.secondary.opacity(0.35)).frame(width: 12, height: 12)
        case .upcoming: Circle().fill(Color.secondary.opacity(0.35)).frame(width: 12, height: 12)
        }
    }

    @ViewBuilder
    private func marker(done: Bool, current: Bool) -> some View {
        if done {
            Image(systemName: "checkmark")
                .font(.app(size: 12, weight: .bold))
                .foregroundStyle(Color(.systemBackground))
                .frame(width: 24, height: 24)
                .background(ProgressRing.kcalColors[0], in: Circle())
        } else if current {
            // Кольцо акцента с белой серединой: «сейчас», а не «было» и не
            // «будет».
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 4)
                .background(Circle().fill(Color(.systemBackground)))
                .frame(width: 24, height: 24)
        } else {
            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 12, height: 12)
        }
    }
}
