import Foundation
import SwiftData
import os

/// Замеры тела: сеансы, процент жира, динамика обхватов.
extension CalorieStore {

    /// Последний сеанс замеров — по нему считается отчёт.
    var latestMeasurement: BodyMeasurement? { measurements.first }

    /// Предыдущий заполненный сеанс, чтобы показать динамику относительно него.
    var previousMeasurement: BodyMeasurement? {
        measurements.dropFirst().first
    }

    /// Сеанс замеров за сегодня. Если его ещё нет, заводит новый, унаследовав
    /// обхваты прошлого: снимают обычно одно-два места, а производные величины
    /// читаются по последнему сеансу целиком.
    func measurementForToday() -> BodyMeasurement {
        if let latest = latestMeasurement, Calendar.current.isDateInToday(latest.date) {
            return latest
        }
        let fresh = BodyMeasurement(date: Date())
        if let previous = latestMeasurement {
            fresh.copyValues(from: previous)
        }
        addMeasurement(fresh)
        return fresh
    }

    func addMeasurement(_ measurement: BodyMeasurement) {
        context.insert(measurement)
        do { try context.save() } catch { storeLogger.error("context.save failed: \(error)") }
        measurements = (measurements + [measurement]).sorted { $0.date > $1.date }
    }

    func deleteMeasurement(_ measurement: BodyMeasurement) {
        context.delete(measurement)
        do { try context.save() } catch { storeLogger.error("context.save failed: \(error)") }
        measurements.removeAll { $0.id == measurement.id }
    }

    func saveMeasurementEdits() {
        do { try context.save() } catch { storeLogger.error("context.save failed: \(error)") }
        measurements.sort { $0.date > $1.date }
        // Процент жира только что изменился — пусть зал узнает об этом сразу,
        // а не на следующей перестройке кэшей.
        BodyBridge.publish(profile: profile, measurement: latestMeasurement)
    }
}
