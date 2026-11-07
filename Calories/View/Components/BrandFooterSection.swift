import SwiftUI

/// Подпись приложения в конце списка профиля.
struct BrandFooterSection: View {
    var body: some View {
        Section {
            BrandFooter()
                .brandFooterRow()
        }
    }
}
