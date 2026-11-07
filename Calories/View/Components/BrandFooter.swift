import SwiftUI

/// Подпись в самом низу настроек: знак «С» и название цветами приложения.
///
/// Место, куда доходят, только долистав до конца, — там подпись ни с чем не
/// спорит и читается как подпись под письмом, а не как реклама. Знак при этом
/// одноцветный и приглушённый, а цвет отдан названию: буквы идут по кругу
/// теми же четырьмя цветами, что и кольцо — углеводы, жиры, белок, калории.
///
/// Цвета берутся из колец, а не записаны числами: у палитры есть насыщенность,
/// которую человек выбирает в настройках, и подпись обязана меняться вместе
/// со всем остальным.
///
/// Только в настройках: на экране профиля прямо над ней стоит кольцо тех же
/// цветов, и две цветные вещи подряд читались бы удвоением.
struct BrandFooter: View {
    var showsVersion = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    /// «Calories» по буквам, цвета по кругу.
    ///
    /// Одной строкой с разметкой, а не восемью `Text` в ряд: у букв остаются
    /// их кернинг и лигатуры, а строка — строкой для чтения с экрана.
    private var colorfulName: AttributedString {
        let colors = [ProgressRing.carbColors, ProgressRing.fatColors,
                      ProgressRing.proteinColors, ProgressRing.kcalColors].map { $0[1] }
        var result = AttributedString()
        for (index, letter) in "Calories".enumerated() {
            var piece = AttributedString(String(letter))
            piece.foregroundColor = colors[index % colors.count]
            result += piece
        }
        return result
    }

    var body: some View {
        VStack(spacing: 4) {
            Image("TodayTab")
                .renderingMode(.template)
                .resizable()
                .frame(width: 22, height: 22)
            Text(colorfulName)
                .font(.app(.caption, weight: .semibold))
            if showsVersion {
                Text(verbatim: version)
                    .font(.app(.caption2))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("brandFooter")
    }
}

extension View {
    /// Строка списка под подпись: без фона, разделителей и отступов секции.
    func brandFooterRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }
}
