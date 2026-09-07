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

    /// Вычисляемым, а не хранимым: хранимое свойство попадает в почленный
    /// инициализатор, а `SettingsView` создаётся внутри и без того тяжёлого
    /// `body` вкладки «Тело» — от лишнего параметра тот перестаёт выводиться
    /// по типам за отведённое время. Наблюдение при этом не теряется:
    /// `@Observable` отслеживает чтение свойств в `body`, а не место хранения.
    private var backups: BackupService { .shared }
    @State private var showingFolderPicker = false
    @State private var showingRestorePicker = false
    @State private var pendingRestore: CaloriesBackup?
    @State private var restoreError: String?
    @State private var restoreDone = false
    
    
    
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
    
    
    private func loadRestoreFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            pendingRestore = try decoder.decode(CaloriesBackup.self, from: Data(contentsOf: url))
        } catch {
            restoreError = String(localized: "Это не похоже на копию Calories.")
        }
    }

    private var lastBackupText: String {
        guard let date = backups.lastBackupDate else { return String(localized: "ещё не было") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        List {
            Section("Подписка") {
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

            Section {
                if backups.isConfigured {
                    LabeledContent("Папка", value: backups.folderName ?? "—")
                    LabeledContent("Последняя копия", value: lastBackupText)
                    Button("Сделать копию сейчас") { backups.backupNow(store) }
                    Button("Выбрать другую папку") { showingFolderPicker = true }
                } else {
                    Button {
                        showingFolderPicker = true
                    } label: {
                        Label("Включить автоматическую копию", systemImage: "clock.arrow.circlepath")
                    }
                }
                Button {
                    showingRestorePicker = true
                } label: {
                    Label("Восстановить из копии", systemImage: "arrow.up.doc")
                }
                if let error = backups.lastError {
                    Text(verbatim: error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Автоматическая копия")
            } footer: {
                Text("Раз в сутки приложение само кладёт копию дневника в выбранную папку. Выбирай папку в iCloud Drive: она лежит отдельно от приложения и переживёт его удаление, а папка внутри приложения удалится вместе с ним.")
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
                    FastingView(store: store)
                } label: {
                    Label("Голодание", systemImage: "moon.stars")
                }
                .accessibilityIdentifier("openFasting")
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    Label("Язык", systemImage: "character.bubble")
                }
            }

#if DEBUG
            // Инструменты разработчика собраны на своём экране и только в
            // отладочной сборке. Вперемешку с настройками пользователя они
            // выглядели как возможности, которых он лишён, — а это не так.
            Section {
                NavigationLink {
                    DeveloperSettingsView(store: store)
                } label: {
                    Label("Отладка", systemImage: "hammer")
                }
            }
#endif
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
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): backups.useFolder(url)
            case .failure(let error): exportError = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showingRestorePicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): loadRestoreFile(url)
            case .failure(let error): restoreError = error.localizedDescription
            }
        }
        // Спрашиваем прямо, что произойдёт, и показываем дату копии: восстановление
        // заменяет всё, и человек должен видеть, на что именно меняет.
        .alert("Заменить все данные?", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        ), presenting: pendingRestore) { backup in
            Button("Отмена", role: .cancel) { pendingRestore = nil }
            Button("Восстановить", role: .destructive) {
                store.restore(from: backup)
                pendingRestore = nil
                restoreDone = true
            }
        } message: { backup in
            Text("Копия от \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened)): записей \(backup.entries.count), взвешиваний \(backup.weights.count). Нынешний дневник будет полностью заменён.")
        }
        .alert("Готово", isPresented: $restoreDone) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Данные восстановлены из копии.")
        }
        .alert("Не удалось прочитать копию", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK", role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
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

#if DEBUG
/// Инструменты разработчика. Существует только в отладочной сборке — в релизе
/// этого экрана нет вовсе, а не «спрятан поглубже».
struct DeveloperSettingsView: View {
    var store: CalorieStore

    @AppStorage("fdc_api_key") private var fdcAPIKey = ""
    @AppStorage("gemini_api_key") private var geminiAPIKey = ""

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { store.isPremium },
                    set: { store.isPremium = $0 }
                )) {
                    Label("Premium", systemImage: "sparkles")
                }
            } header: {
                Text("Подписка")
            } footer: {
                Text("Пока продукты StoreKit не грузятся, это единственный способ открыть платные экраны.")
            }

            Section {
                TextField("Ключ Gemini", text: $geminiAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
            } header: {
                Text("Распознавание фото")
            } footer: {
                Text(geminiAPIKey.isEmpty
                     ? "Пусто — кнопка камеры в приёме пищи не показывается."
                     : "Ключ задан: в приёме пищи появилась кнопка камеры.")
            }

            Section {
                TextField("Ключ USDA", text: $fdcAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
            } header: {
                Text("Источник продуктов")
            } footer: {
                Text(fdcAPIKey.isEmpty
                     ? "Пусто — поиск идёт в Open Food Facts, как у обычного пользователя."
                     : "Ключ задан: поиск идёт в USDA и приносит витамины и минералы.")
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .navigationTitle("Отладка")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
