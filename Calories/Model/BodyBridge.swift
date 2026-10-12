//
//  BodyBridge.swift
//  Calories
//
//  Линия между Calories и GymLogger.
//
//  Обхваты снимаются здесь, процент жира считается здесь — и там, в зале, он нужен ровно
//  такой же: без него FFMI не посчитать, а считать его второй раз по второму комплекту
//  замеров значит получить два разных числа про одного человека. Приложения подписаны
//  одной командой, поэтому делятся напрямую через общую группу, без сервера и без Health.
//

import Foundation

/// Что отдаём. Близнец этой структуры лежит в GymLogger
/// (`GymLogger/Core/Services/SharedBody.swift`) — имена полей это формат обмена,
/// менять их можно только в обоих местах сразу.
struct SharedBodyPayload: Codable, Equatable, Sendable {
    var date: Date
    var weightKg: Double?
    var heightCm: Double?
    /// Проценты, 0–100.
    var bodyFatPercent: Double?
    var leanMassKg: Double?
    /// Снято лентой (Navy), а не прикинуто по ИМТ. Оценка по ИМТ считает мышцы жиром,
    /// поэтому в зале её игнорируют — но пусть решает тот, кто читает.
    var isMeasured: Bool
}

enum BodyBridge {

    /// Группа, которая есть в entitlements обоих приложений — своя, давно заведённая:
    /// заводить вторую ради одной записи незачем, тем более что эта уже провижена.
    static let appGroup = CalorieStore.appGroup
    static let key = "body_snapshot"

    /// Кладёт свежие цифры в общую группу. Ничего не пишет, пока профиля нет:
    /// пустая запись у читателя неотличима от «приложение не установлено».
    static func publish(profile: UserProfile?,
                        measurement: BodyMeasurement?,
                        defaults: UserDefaults? = UserDefaults(suiteName: BodyBridge.appGroup),
                        now: Date = Date()) {
        guard let defaults, let profile else { return }
        let measured = profile.navyBodyFat(from: measurement) != nil
        let payload = SharedBodyPayload(
            date: now,
            weightKg: profile.weightKg > 0 ? profile.weightKg : nil,
            heightCm: profile.heightCm > 0 ? profile.heightCm : nil,
            bodyFatPercent: profile.bodyFatPercentage(from: measurement),
            leanMassKg: profile.leanMassKg(from: measurement),
            isMeasured: measured
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }
}
