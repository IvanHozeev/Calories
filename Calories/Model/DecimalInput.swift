import Foundation

extension String {
    /// Число, введённое человеком: запятая и точка значат одно и то же.
    ///
    /// На русской и израильской раскладках десятичный разделитель — запятая,
    /// а `Double("1,5")` возвращает nil. Замена жила в четырнадцати местах по
    /// вьюхам, и стоило её забыть в одном поле — вес «1,5» молча становился
    /// нулём, без ошибки и без следа.
    var decimalValue: Double? {
        let normalized = trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    /// То же, но нечитаемое считается нулём — для полей, где пусто значит «нет».
    var decimalValueOrZero: Double { decimalValue ?? 0 }
}
