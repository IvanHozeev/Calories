import SwiftUI
import UserNotifications

struct RemindersView: View {
    let store: CalorieStore
    @State private var reminderStore = ReminderStore()
    private var schedule: MealScheduleSettings { .shared }
    @State private var showingHabits = false

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { reminderStore.appEnabled && reminderStore.authStatus == .authorized },
            set: { newValue in
                if newValue {
                    if reminderStore.authStatus == .denied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        Task { await reminderStore.enableNotifications() }
                    }
                } else {
                    reminderStore.disableNotifications()
                }
            }
        )
    }

    /// Обучаемые напоминания: привычки и предложения по их корректировке.
    private var habits: [MealAdherence.Habit] {
        let days = store.adherenceDays(back: 21, schedule: schedule)
        return MealAdherence.habits(days)
    }

    /// Предложения по корректировке расписания на основе привычек.
    private var habitSuggestions: [MealAdherence.Suggestion] {
        let days = store.adherenceDays(back: 21, schedule: schedule)
        return MealAdherence.suggestions(for: days)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Уведомления", isOn: notificationsBinding)
            } footer: {
                if reminderStore.authStatus == .denied {
                    Text("Уведомления отключены. Включи в Настройках → Калории.")
                } else if reminderStore.authStatus == .notDetermined {
                    Text("Включи, чтобы получать напоминания записывать приёмы пищи.")
                }
            }

            if reminderStore.appEnabled && reminderStore.authStatus == .authorized {
                Section {
                    ForEach($reminderStore.reminders) { $reminder in
                        ReminderRow(reminder: $reminder, enabled: true) {
                            reminderStore.saveAndReschedule()
                        }
                    }
                } header: {
                    Text("Расписание")
                } footer: {
                    Text("Повторяются каждый день в выбранное время.")
                }

                Section {
                    ForEach(habits) { habit in
                        habitRow(habit)
                    }
                } header: {
                    Text("Обучаемые напоминания")
                } footer: {
                    Text("Приложение учится, когда ты обычно ешь, и предлагает скорректировать расписание. Нажми «Применить», чтобы сдвинуть время приёма.")
                }
            }
        }
        .glassRow()
        .screenTitle(String(localized: "Напоминания"))
        .onAppear {
            Task { await reminderStore.refreshAuthStatus() }
        }
        .alert("Не удалось включить уведомления", isPresented: Binding(
            get: { reminderStore.authError != nil },
            set: { if !$0 { reminderStore.authError = nil } }
        )) {
            Button("Понятно", role: .cancel) { reminderStore.authError = nil }
        } message: {
            Text(reminderStore.authError ?? "")
        }
    }

    @ViewBuilder
    private var habitRow: some View {
        ForEach(habits) { habit in
            habitRow(habit)
        }
    }

    @ViewBuilder
    private func habitRow(_ habit: MealAdherence.Habit) -> some View {
        let habitSuggestions = habitSuggestions.filter { $0.id == habit.id }
        let moveSuggestion = habitSuggestions.first(where: {
            if case .moveMeal = $0 { return true }; return false
        })

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
                .font(.app(.caption))
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.period.timeTitle)
                    .font(.app(.subheadline, weight: .semibold))
                Text("Обычно ест в \(slotTime(for: habit.period, shiftedBy: habit.shiftMinutes))")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Text("\(habit.shiftMinutes > 0 ? "+" : "")\(habit.shiftMinutes) мин к плану, \(habit.days) дн.")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if abs(habit.shiftMinutes) >= MealAdherence.noticeableShiftMinutes {
                Button("Перенести") {
                    applyMoveHabit(habit)
                }
                .font(.app(.caption))
                .buttonStyle(.borderless)
                .tint(.blue)
            }
        }
        .padding(.vertical, 2)
    }

    private func slotTime(for period: MealPeriod, shiftedBy minutes: Int) -> String {
        let slots = MealSchedule.slots(
            settings: schedule,
            entries: [],
            dailyGoal: store.adaptedTodayGoal,
            now: Date()
        )
        guard let slot = slots.first(where: { $0.period == period }) else { return "--:--" }
        let shifted = slot.time.addingTimeInterval(Double(minutes) * 60)
        return shifted.formatted(date: .omitted, time: .shortened)
    }

    private func applyMoveHabit(_ habit: MealAdherence.Habit) {
        let schedule = MealScheduleSettings.shared
        let calendar = Calendar.current
        let shift = habit.shiftMinutes
        let newWake = calendar.date(byAdding: .minute, value: shift, to: schedule.wake) ?? schedule.wake
        let newSleep = calendar.date(byAdding: .minute, value: shift, to: schedule.sleep) ?? schedule.sleep
        schedule.wake = newWake
        schedule.sleep = newSleep
        MealReminders.reschedule(settings: schedule)
    }
}

private struct ReminderRow: View {
    @Binding var reminder: ReminderItem
    let enabled: Bool
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(reminder.title, isOn: $reminder.isEnabled)
                .disabled(!enabled)
                .onChange(of: reminder.isEnabled) { _, _ in onChange() }
            if reminder.isEnabled && enabled {
                DatePicker(
                    "",
                    selection: $reminder.time,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .onChange(of: reminder.time) { _, _ in onChange() }
            }
        }
        .padding(.vertical, 2)
    }
}
