import SwiftUI
import UserNotifications

struct RemindersView: View {
    @State private var store = ReminderStore()
    @State private var schedule = MealScheduleSettings()

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { store.appEnabled && store.authStatus == .authorized },
            set: { newValue in
                if newValue {
                    if store.authStatus == .denied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        Task { await store.enableNotifications() }
                    }
                } else {
                    store.disableNotifications()
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Уведомления", isOn: notificationsBinding)
            } footer: {
                if store.authStatus == .denied {
                    Text("Уведомления отключены. Включи в Настройках → Калории.")
                } else if store.authStatus == .notDetermined {
                    Text("Включи, чтобы получать напоминания записывать приёмы пищи.")
                }
            }

            // Расписание приёмов пищи — про то, как делится день, а не про
            // время уведомлений, поэтому оно выше и работает независимо от них.
            Section {
                Toggle("Делить день на приёмы", isOn: Binding(
                    get: { schedule.isEnabled },
                    set: { schedule.isEnabled = $0 }
                ))
                .accessibilityIdentifier("mealScheduleToggle")

                if schedule.isEnabled {
                    DatePicker("Подъём", selection: Binding(
                        get: { schedule.wake }, set: { schedule.wake = $0 }
                    ), displayedComponents: .hourAndMinute)
                    DatePicker("Отбой", selection: Binding(
                        get: { schedule.sleep }, set: { schedule.sleep = $0 }
                    ), displayedComponents: .hourAndMinute)
                    Stepper(value: Binding(get: { schedule.count }, set: { schedule.count = $0 }),
                            in: MealSchedule.allowedCounts) {
                        HStack {
                            Text("Приёмов в день")
                            Spacer()
                            Text(verbatim: "\(schedule.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("Приёмы пищи")
            } footer: {
                if schedule.isEnabled {
                    Text("Первый приём через 45 минут после подъёма, последний за час до отбоя, остальные поровну между ними. Пропущенное окно не сгорает: его калории расходятся по оставшимся приёмам.")
                } else {
                    Text("Норма делится на равные приёмы, и на «Сегодня» видно, сколько осталось на ближайший.")
                }
            }

            if store.appEnabled && store.authStatus == .authorized {
                Section {
                    ForEach($store.reminders) { $reminder in
                        ReminderRow(reminder: $reminder, enabled: true) {
                            store.saveAndReschedule()
                        }
                    }
                } header: {
                    Text("Расписание")
                } footer: {
                    Text("Повторяются каждый день в выбранное время.")
                }
            }
        }
        // Напоминания об окнах переставляются на выходе: внутри экрана
        // настройки трогают по нескольку раз, и переставлять на каждый тик
        // значило бы дёргать систему зря.
        .onDisappear { MealReminders.reschedule(settings: schedule) }
        .glassRow()
        .navigationTitle("Напоминания")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await store.refreshAuthStatus() }
        }
        .alert("Не удалось включить уведомления", isPresented: Binding(
            get: { store.authError != nil },
            set: { if !$0 { store.authError = nil } }
        )) {
            Button("OK", role: .cancel) { store.authError = nil }
        } message: {
            Text(store.authError ?? "")
        }
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
