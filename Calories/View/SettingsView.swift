import SwiftUI
import UniformTypeIdentifiers

/// Настройки приложения: подписка, выгрузка данных и системные параметры.
/// Профиль отсюда вынесен в ProfileSettingsView — он про пользователя, а не про приложение,
/// и занимал пять секций из восьми, из-за чего экран лишь назывался настройками.
struct SettingsView: View {
    var store: CalorieStore
    @State private var showingPaywall = false
    @AppStorage("use_imperial") private var useImperial = false
    @AppStorage("app_theme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("app_font") private var appFont = AppFont.system.rawValue
    
    @State private var exportDocument: ExportDocument?
    @State private var exportFilename = ""
    @State private var showingExporter = false
    @State private var exportError: String?
    
    
    
    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private func prepareBackup() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(store.makeBackup()),
              let text = String(data: data, encoding: .utf8) else {
            exportError = String(localized: "Не удалось собрать файл.")
            return
        }
        exportDocument = ExportDocument(text: text, type: .json)
        exportFilename = "calories-backup-\(dateStamp())"
        showingExporter = true
    }
    
    private func prepareCSV() {
        exportDocument = ExportDocument(text: store.makeDiaryCSV(), type: .commaSeparatedText)
        exportFilename = "calories-diary-\(dateStamp())"
        showingExporter = true
    }
    
    
    var body: some View {
        List {
            Section("Подписка") {
#if DEBUG
                // Отладочный тумблер: пока продукты StoreKit не грузятся, это
                // единственный способ проверять платные экраны. В релиз не попадает.
                Toggle(isOn: Binding(
                    get: { store.isPremium },
                    set: { store.isPremium = $0 }
                )) {
                    Label("Premium (отладка)", systemImage: "hammer")
                }
#endif
                
                if store.isPremium {
                    Label("Premium активен", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        showingPaywall = true
                    } label: {
                        Label("Оформить Premium", systemImage: "sparkles")
                    }
                }
            }
            
            Section {
                Button {
                    prepareBackup()
                } label: {
                    Label("Резервная копия (JSON)", systemImage: "arrow.down.doc")
                }
                Button {
                    prepareCSV()
                } label: {
                    Label("Дневник таблицей (CSV)", systemImage: "tablecells")
                }
            } header: {
                Text("Данные")
            } footer: {
                Text("Данные хранятся только на этом устройстве. Синхронизации нет — выгрузи копию, чтобы не потерять историю вместе с телефоном.")
            }
            
            Section("Системное") {
                Picker(selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.title, systemImage: theme.icon).tag(theme.rawValue)
                    }
                } label: {
                    Label("Оформление", systemImage: "circle.lefthalf.filled")
                }
                
                NavigationLink {
                    FontSettingsView()
                } label: {
                    HStack {
                        Label("Шрифт и размер", systemImage: "textformat")
                        Spacer()
                        Text(AppFont(rawValue: appFont)?.title ?? "")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("openFontSettings")

                NavigationLink {
                    UnitsSettingsView()
                } label: {
                    Label("Единицы измерения", systemImage: "globe")
                }
                NavigationLink {
                    RemindersView()
                } label: {
                    Label("Напоминания", systemImage: "bell")
                }
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    Label("Язык", systemImage: "character.bubble")
                }
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .navigationTitle("Настройки")
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportDocument?.type ?? .json,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert("Не удалось сохранить", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(store: store, focus: .plan)
        }
    }
}

private struct UnitsSettingsView: View {
    @AppStorage("use_imperial") private var useImperial = false
    
    var body: some View {
        List {
            Section {
                Picker("Система", selection: $useImperial) {
                    Text("Метрическая").tag(false)
                    Text("Американская").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Система")
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .navigationTitle("Единицы измерения")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LanguageSettingsView: View {
    @State private var selectedLanguage: String
    @State private var showRestartAlert = false
    
    init() {
        let saved = UserDefaults.standard.array(forKey: "AppleLanguages")?.first as? String
        let lang: String
        if let saved {
            lang = String(saved.prefix(2))
        } else {
            lang = Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
        }
        _selectedLanguage = State(initialValue: lang)
    }
    
    var body: some View {
        List {
            Section {
                languageRow(code: "ru", title: "Русский", flag: "🇷🇺")
                languageRow(code: "en", title: "English", flag: "🇺🇸")
                languageRow(code: "he", title: "עברית", flag: "🇮🇱")
                languageRow(code: "es", title: "Español", flag: "🇪🇸")
                languageRow(code: "ar", title: "العربية", flag: "🇸🇦")
                languageRow(code: "pt", title: "Português", flag: "🇧🇷")
                languageRow(code: "fr", title: "Français", flag: "🇫🇷")
                languageRow(code: "de", title: "Deutsch", flag: "🇩🇪")
            } footer: {
                Text("Для применения нового языка перезапусти приложение.")
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .navigationTitle("Язык")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Перезапусти приложение", isPresented: $showRestartAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Закрой и открой приложение заново, чтобы язык применился.")
        }
    }
    
    private func languageRow(code: String, title: String, flag: String) -> some View {
        Button {
            guard selectedLanguage != code else { return }
            selectedLanguage = code
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            showRestartAlert = true
        } label: {
            HStack {
                Text(flag)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedLanguage == code {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}


/// Выбор начертания. Каждый вариант написан своим же шрифтом — иначе выбирать
/// пришлось бы по названию, ничего не увидев.
struct FontSettingsView: View {
    @AppStorage("app_font") private var appFont = AppFont.system.rawValue
    @AppStorage("app_text_size") private var appTextSize = AppTextSize.normal.rawValue

    var body: some View {
        List {
            Section("Размер") {
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(appTextSize) },
                            set: { appTextSize = Int($0.rounded()) }
                        ),
                        in: 0...Double(AppTextSize.allCases.count - 1),
                        step: 1
                    ) {
                        Text("Размер")
                    } minimumValueLabel: {
                        Text(verbatim: "A").font(.caption2)
                    } maximumValueLabel: {
                        Text(verbatim: "A").font(.title3)
                    }
                    .accessibilityIdentifier("textSizeSlider")

                    Text(AppTextSize(rawValue: appTextSize)?.title ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Начертание") {
                ForEach(AppFont.allCases) { font in
                    Button {
                        // Глифы подменяются мгновенно — шрифты не интерполируются.
                        // Анимируется раскладка: при смене начертания меняется ширина
                        // текста, и без этого весь список дёргается рывком.
                        withAnimation(.easeInOut(duration: 0.25)) {
                            appFont = font.rawValue
                        }
                    } label: {
                        // Образца «каждая строка своим шрифтом» здесь нет намеренно:
                        // корневой .fontDesign переписывает начертание у любого шрифта
                        // ниже себя, включая собранный из дескриптора, поэтому все
                        // строки выглядели бы одинаково. Предпросмотр даёт сам выбор —
                        // по тапу интерфейс мгновенно перерисовывается целиком.
                        HStack {
                            Text(font.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appFont == font.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .accessibilityIdentifier("font-\(font.rawValue)")
                }
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .navigationTitle("Шрифт и размер")
        .navigationBarTitleDisplayMode(.inline)
    }
}
