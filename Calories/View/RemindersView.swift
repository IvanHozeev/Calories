import SwiftUI
import UserNotifications

struct RemindersView: View {
    @State private var store = ReminderStore()

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
        .navigationTitle("Напоминания")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await store.refreshAuthStatus() }
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
