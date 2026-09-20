import SwiftUI

/// Подпись в самом низу длинных списков: знак «С» и название.
///
/// Место, куда доходят, только долистав до конца, — там подпись ни с чем не
/// спорит и читается как подпись под письмом, а не как реклама. Знак
/// одноцветный и приглушённый: цветной отвлекал бы от последней секции.
/// В настройках к ней добавляется версия — её там и ищут, когда пишут о проблеме.
struct BrandFooter: View {
    var showsVersion = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 4) {
            Image("TodayTab")
                .renderingMode(.template)
                .resizable()
                .frame(width: 22, height: 22)
            Text(verbatim: "Calories")
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
