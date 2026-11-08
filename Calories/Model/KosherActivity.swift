import ActivityKit
import Foundation

/// Ожидание между мясным и молочным в островке и на экране блокировки.
///
/// Заводится, когда ждать есть чего, и гасится, когда ждать нечего. Запись
/// одна: в ней лежит время конца, а отсчёт до него рисует система — поэтому
/// ничего не обновляется в фоне и число остаётся верным, даже если
/// приложение больше не открывали.
///
/// Живую активность разрешено заводить только из приложения на экране — и это
/// ровно тот момент, когда человек записывает еду. Специально ловить его не
/// приходится.
@MainActor
enum KosherActivity {

    private static var current: Activity<KosherWaitAttributes>? {
        Activity<KosherWaitAttributes>.activities.first
    }

    /// Какое ожидание показывать: самое позднее из тех, что ещё идут.
    ///
    /// Островок один, а более долгое ожидание и есть более строгое: второе к
    /// его концу уже не ограничивает — дождавшись долгого, человек дождался
    /// и короткого.
    ///
    /// Порядок действий здесь не случаен и держится на этом же: сначала
    /// самое позднее, потом проверка, кончилось ли оно. Наоборот было бы
    /// ошибкой — но и так не ошибка именно потому, что раз кончилось самое
    /// позднее, то кончились и все прочие.
    ///
    /// Вынесено из `sync` ради проверки: остальное в этом файле — вызовы
    /// ActivityKit, которые без запущенного приложения не выполнить, а
    /// выбор ожидания ошибается тихо и показывает не то число.
    nonisolated static func chosen(from waits: [KosherWait], now: Date = Date()) -> KosherWait? {
        guard let wait = waits.max(by: { $0.until < $1.until }), !wait.isOver(at: now) else {
            return nil
        }
        return wait
    }

    /// Как ожидание называется в записи активности: виджет своей модели не
    /// видит и читает строку.
    nonisolated static func blockedName(_ status: KosherStatus) -> String {
        status == .meat ? KosherWaitAttributes.meat : KosherWaitAttributes.dairy
    }

    /// Приводит островок в соответствие с дневником.
    static func sync(waits: [KosherWait], enabled: Bool) {
        // Пока кашрут выключен, ActivityKit не трогаем вовсе — даже чтобы
        // спросить, нет ли чего погасить. Выключенная функция не должна
        // будить подсистему, которая ей не нужна, а зовётся это на каждом
        // появлении «Сегодня». Гасит запись тот, кто выключает тумблер, —
        // там это ровно одно действие, а не проверка на каждый показ экрана.
        guard enabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }
        guard let wait = chosen(from: waits) else {
            end()
            return
        }
        let blocked = blockedName(wait.blocked)
        let state = KosherWaitAttributes.ContentState(until: wait.until)

        if let existing = current {
            // То же самое ожидание уже идёт — говорить нечего.
            guard existing.attributes.blocked != blocked
                    || existing.content.state.until != wait.until else { return }
            Task {
                await existing.end(nil, dismissalPolicy: .immediate)
                request(blocked: blocked, since: wait.since, state: state)
            }
            return
        }
        request(blocked: blocked, since: wait.since, state: state)
    }

    static func end() {
        Task {
            for activity in Activity<KosherWaitAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func request(blocked: String, since: Date,
                                state: KosherWaitAttributes.ContentState) {
        do {
            _ = try Activity.request(
                attributes: KosherWaitAttributes(blocked: blocked, since: since),
                // Устарела, когда ожидание кончилось: система перестаёт
                // показывать число, переставшее что-либо значить, даже если
                // приложение так и не вернулось.
                content: .init(state: state, staleDate: state.until)
            )
        } catch {
            // Отказать могут: активности выключены, их уже слишком много.
            // Строка под кольцом — то, что действительно важно, а это
            // удобство поверх неё.
        }
    }
}
