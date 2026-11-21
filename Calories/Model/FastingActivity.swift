import ActivityKit
import Foundation

/// Идущий пост в островке и на экране блокировки.
///
/// Заводится, когда пост идёт, и гасится, когда он кончился или его сняли.
/// Запись одна, в ней время конца: отсчёт рисует система, поэтому в фоне ничего
/// не обновляется. Заводить живую активность можно только из приложения на
/// экране — то есть здесь, при показе «Сегодня».
@MainActor
enum FastingActivity {

    private static var current: Activity<FastingAttributes>? {
        Activity<FastingAttributes>.activities.first
    }

    /// Вид поста строкой для записи активности.
    nonisolated static func kindName(_ kind: FastKind) -> String {
        switch kind {
        case .dry: return FastingAttributes.dry
        case .water: return FastingAttributes.water
        case .daytime: return FastingAttributes.daytime
        }
    }

    /// Приводит островок в соответствие с идущим постом: `nil` — поста нет.
    static func sync(running fast: FastDay?, now: Date = Date()) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }
        guard let fast, fast.hasExplicitInterval, fast.isRunning(at: now) else {
            end()
            return
        }
        let interval = fast.interval
        let kind = kindName(fast.kind)
        let state = FastingAttributes.ContentState(until: interval.end)

        if let existing = current {
            // Тот же пост уже показан — говорить нечего.
            guard existing.attributes.kind != kind
                    || existing.attributes.startedAt != interval.start
                    || existing.content.state.until != interval.end else { return }
            Task {
                await existing.end(nil, dismissalPolicy: .immediate)
                request(kind: kind, since: interval.start, state: state)
            }
            return
        }
        request(kind: kind, since: interval.start, state: state)
    }

    static func end() {
        Task {
            for activity in Activity<FastingAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func request(kind: String, since: Date, state: FastingAttributes.ContentState) {
        do {
            _ = try Activity.request(
                attributes: FastingAttributes(startedAt: since, kind: kind),
                // Устарела в момент конца: виджет сам переходит на «пост
                // закончился», даже если приложение так и не открыли.
                content: .init(state: state, staleDate: state.until)
            )
        } catch {
            // Отказать могут: активности выключены или их слишком много. Строка
            // на «Сегодня» важнее, а это — удобство поверх неё.
        }
    }
}
