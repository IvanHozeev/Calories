import Foundation
import SwiftData
import os

/// Голодание: отметки, советы, обратный отсчёт.
extension CalorieStore {

    /// Отмечен ли день голоданием. Именно отметка, а не пустой день: забытый день
    /// и намеренное голодание выглядят в базе одинаково, и различить их больше нечем.
    func isFastDay(_ date: Date) -> Bool {
        fastDates.contains(Calendar.current.startOfDay(for: date))
    }

    func fastDay(on date: Date) -> FastDay? {
        let day = Calendar.current.startOfDay(for: date)
        return fastDays.first { $0.coveredDays.contains(day) }
    }

    /// Ближайшее голодание — сегодня или в пределах трёх дней — и советы, которые
    /// к месту именно сейчас. nil, когда голодания впереди нет или советовать
    /// пока рано.
    func fastingHint(now: Date = Date()) -> FastingHint? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for offset in 0...FastingAdvice.earliestDaysBefore {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                  let fast = fastDay(on: date) else { continue }
            let items = FastingAdvice.advice(for: fast.kind, daysBefore: offset)
            guard !items.isEmpty else { return nil }
            return FastingHint(date: date, kind: fast.kind, daysUntil: offset,
                               items: items,
                               // Обратный отсчёт — только по явным границам.
                               // У старой отметки «днём» их нет, и отсчёт шёл
                               // бы до полуночи, хотя пост давно кончился.
                               interval: fast.hasExplicitInterval ? fast.interval : nil)
        }
        return nil
    }

    /// Ближайший пост к сегодняшнему дню: идущий, иначе последний прошедший
    /// или ближайший запланированный. Его и открывает экран голодания.
    func nearestFast(to moment: Date = Date()) -> FastDay? {
        if let running = runningFast(at: moment) { return running }
        return fastDays.min {
            abs($0.interval.start.timeIntervalSince(moment)) < abs($1.interval.start.timeIntervalSince(moment))
        }
    }

    /// Отметить пост промежутком: с вечера одного дня до вечера другого.
    ///
    /// `replacing` — отметка, которую правят. Без неё правка времени заводила
    /// бы вторую отметку рядом с прежней, когда новое начало попадает на другие
    /// сутки.
    @discardableResult
    func markFast(from start: Date, to end: Date, kind: FastKind, replacing: FastDay? = nil) -> FastDay {
        let day = Calendar.current.startOfDay(for: start)
        if let existing = replacing ?? fastDay(on: day) {
            existing.kind = kind
            existing.date = day
            existing.startedAt = start
            existing.endedAt = end
            do { try context.save() } catch { storeLogger.error("context.save failed: \(error)") }
            rebuildCaches()
            return existing
        }
        let fast = FastDay(date: day, kind: kind, startedAt: start, endedAt: end)
        context.insert(fast)
        do { try context.save() } catch { storeLogger.error("context.save failed: \(error)") }
        fastDays = (fastDays + [fast]).sorted { $0.date > $1.date }
        rebuildCaches()
        return fast
    }

    /// Идущий прямо сейчас пост — для обратного отсчёта на «Сегодня».
    func runningFast(at moment: Date = Date()) -> FastDay? {
        fastDays.first { $0.hasExplicitInterval && $0.isRunning(at: moment) }
    }

    @discardableResult
    func markFastDay(_ date: Date = Date(), kind: FastKind) -> FastDay {
        if let existing = fastDay(on: date) {
            existing.kind = kind
            do { try context.save() } catch { storeLogger.error("context.save failed: \(error)") }
            rebuildCaches()
            return existing
        }
        let day = FastDay(date: date, kind: kind)
        context.insert(day)
        do { try context.save() } catch { storeLogger.error("context.save failed: \(error)") }
        fastDays = (fastDays + [day]).sorted { $0.date > $1.date }
        rebuildCaches()
        return day
    }

    func unmarkFastDay(_ date: Date = Date()) {
        guard let day = fastDay(on: date) else { return }
        context.delete(day)
        do { try context.save() } catch { storeLogger.error("context.save failed: \(error)") }
        fastDays.removeAll { $0.id == day.id }
        rebuildCaches()
    }
}
