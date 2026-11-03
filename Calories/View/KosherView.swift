import SwiftUI

/// Кашрут: ожидание между мясным и молочным.
///
/// В профиле, а не в настройках приложения, и по той же причине, по которой
/// там же лежат приёмы пищи: это про то, как человек ест, а не про то, как
/// приложение выглядит и куда кладёт копии.
///
/// Своим экраном, а не четырьмя строками в «Питании»: пока тумблер выключен,
/// показывать там нечего, а включённый добавил бы в список профиля четыре
/// строки, которые читают раз в жизни — обычай выбирают однажды.
struct KosherView: View {
    private var settings: KosherSettings { .shared }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { settings.isEnabled },
                                     set: { newValue in
                                         settings.isEnabled = newValue
                                         // Выключил — гасим запись в островке
                                         // сразу: ждать нечего, а висеть она
                                         // будет до своего конца.
                                         if !newValue { KosherActivity.end() }
                                     })) {
                    Label("Мясное и молочное", systemImage: "clock.arrow.2.circlepath")
                }
                .accessibilityIdentifier("kosherEnabled")
            } footer: {
                if !settings.isEnabled {
                    explain("Приложение будет считать, сколько осталось до молочного после мясного и наоборот, и предупреждать, если мясное и молочное попали в одну тарелку. Кошерность продукта оно не определяет: про забой говядины по таблице калорий узнать нечего.",
                            short: "Счёт времени между мясным и молочным. Кошерность продукта не определяется.").map { Text($0) }
                }
            }
            .glassRow()

            if settings.isEnabled {
                Section {
                    Picker(selection: Binding(get: { settings.afterMeat },
                                              set: { settings.afterMeat = $0 })) {
                        ForEach(KosherCustom.afterMeatOptions, id: \.self) { minutes in
                            Text(verbatim: KosherWaitText.title(minutes: minutes)).tag(minutes)
                        }
                    } label: {
                        Label("После мясного", systemImage: "fork.knife")
                    }

                    Picker(selection: Binding(get: { settings.afterDairy },
                                              set: { settings.afterDairy = $0 })) {
                        ForEach(KosherCustom.afterDairyOptions, id: \.self) { minutes in
                            Text(verbatim: KosherWaitText.title(minutes: minutes)).tag(minutes)
                        }
                    } label: {
                        Label("После молочного", systemImage: "drop")
                    }

                    Toggle(isOn: Binding(get: { settings.hardCheeseLikeMeat },
                                         set: { settings.hardCheeseLikeMeat = $0 })) {
                        Label("Твёрдый сыр как мясное", systemImage: "square.grid.2x2")
                    }
                } header: {
                    Text("Обычай")
                } footer: {
                    explain("Сколько ждать — обычай общины, а не одно число: после мясного ждут шесть часов, пять с половиной, три или час. После молочного по букве закона ждать не нужно, но полчаса — распространённый обычай. Приложение считает по тому, как принято у вас, и говорит только время: решаете вы.",
                            short: "Обычай у каждой общины свой — приложение считает по вашему.").map { Text($0) }
                }
                .glassRow()

                Section {
                    Toggle(isOn: Binding(get: { settings.warnsMixing },
                                         set: { settings.warnsMixing = $0 })) {
                        Label("Говорить о смешении", systemImage: "exclamationmark.triangle")
                    }
                } footer: {
                    explain("Приложение скажет, если в собираемом приёме встретились мясное и молочное, — пока приём ещё можно разложить на два. Запретить сохранение оно не может и не должно: что у вас в тарелке, знаете вы.",
                            short: "Предупреждение, пока приём ещё собирается.").map { Text($0) }
                }
                .glassRow()
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .screenTitle(String(localized: "Кашрут"))
    }
}
