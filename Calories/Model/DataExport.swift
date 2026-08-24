import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Полный снимок данных пользователя. SwiftData живёт только на устройстве, синхронизации нет,
/// поэтому единственная защита от потери телефона — выгрузка файлом.
/// Формат намеренно плоский и самодостаточный: его можно прочитать чем угодно
/// и позже использовать для импорта обратно.
struct CaloriesBackup: Codable {
    struct Entry: Codable {
        let name: String
        let calories: Int
        let protein: Double
        let fat: Double
        let carbs: Double
        let grams: Double?
        let date: Date
    }

    struct Weight: Codable {
        let weightKg: Double
        let date: Date
    }

    struct Product: Codable {
        let name: String
        let caloriesPer100g: Int
        let protein: Double
        let fat: Double
        let carbs: Double
        let defaultGrams: Double
    }

    struct DishExport: Codable {
        let name: String
        let createdAt: Date
        let ingredients: [DishIngredient]
    }

    struct Goal: Codable {
        let date: Date
        let goal: Int
    }

    let exportedAt: Date
    let appVersion: String
    let profile: UserProfile?
    let plan: Plan?
    let dailyGoal: Int
    let entries: [Entry]
    let weights: [Weight]
    let products: [Product]
    let dishes: [DishExport]
    let goalHistory: [Goal]
}

extension CalorieStore {
    /// Собирает снимок для выгрузки. Читает уже загруженные коллекции, в базу не ходит.
    func makeBackup() -> CaloriesBackup {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return CaloriesBackup(
            exportedAt: Date(),
            appVersion: version,
            profile: profile,
            plan: plan,
            dailyGoal: dailyGoal,
            entries: entries.map {
                .init(name: $0.name, calories: $0.calories, protein: $0.protein,
                      fat: $0.fat, carbs: $0.carbs, grams: $0.grams, date: $0.date)
            },
            weights: weightEntries.map { .init(weightKg: $0.weightKg, date: $0.date) },
            products: customFoods.map {
                .init(name: $0.name, caloriesPer100g: $0.caloriesPer100g, protein: $0.protein,
                      fat: $0.fat, carbs: $0.carbs, defaultGrams: $0.defaultGrams)
            },
            dishes: dishes.map { .init(name: $0.name, createdAt: $0.createdAt, ingredients: $0.ingredients) },
            goalHistory: goalRecords.map { .init(date: $0.date, goal: $0.goal) }
        )
    }

    /// Дневник в CSV — чтобы открыть в таблице и посчитать что-то своё.
    /// Разделитель запятая, поля с запятыми и кавычками экранируются по RFC 4180.
    func makeDiaryCSV() -> String {
        let formatter = ISO8601DateFormatter()
        var rows = ["date,name,calories,protein_g,fat_g,carbs_g,grams"]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            let fields = [
                formatter.string(from: entry.date),
                Self.csvEscape(entry.name),
                "\(entry.calories)",
                String(format: "%.1f", entry.protein),
                String(format: "%.1f", entry.fat),
                String(format: "%.1f", entry.carbs),
                entry.grams.map { String(format: "%.0f", $0) } ?? ""
            ]
            rows.append(fields.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Документ для системного экспорта — сохраняется в «Файлы», iCloud Drive или куда выберет пользователь.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    var data: Data
    var type: UTType

    init(text: String, type: UTType) {
        self.data = Data(text.utf8)
        self.type = type
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        type = .json
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
