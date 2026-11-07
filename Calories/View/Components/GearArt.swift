import SwiftUI

/// Рисунки снаряжения для онбординга: напольные весы, кухонные весы, часы.
///
/// Нарисованы здесь, а не взяты картинками. Причин три. Рисунок подстраивается
/// под тёмную тему и крупный шрифт, а картинка в ассетах — нет, и её пришлось
/// бы держать в трёх размерах и двух темах. Цвета берутся из той же палитры,
/// что кольцо, и меняются вместе с насыщенностью, которую человек выбрал.
/// И за них никому не надо платить.
///
/// Линии, а не заливки: знак приложения — три дуги со скруглёнными концами, и
/// снаряжение нарисовано той же рукой. Толщина задана долей от размера, чтобы
/// рисунок не тончал на большом экране и не жирнел на маленьком.
struct GearArt: View {
    enum Kind { case bodyScale, kitchenScale, watch }

    let kind: Kind
    var color: Color

    /// Холст, в котором заданы все числа ниже. Рисунок потом растягивается
    /// целиком, поэтому достаточно держать пропорции внутри этой сотни.
    private static let canvas: CGFloat = 100

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let k = side / Self.canvas
            let line = max(2, side * 0.055)
            let stroke = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)

            ZStack {
                switch kind {
                case .bodyScale:    bodyScale(k: k, stroke: stroke)
                case .kitchenScale: kitchenScale(k: k, stroke: stroke)
                case .watch:        watch(k: k, stroke: stroke)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }

    // MARK: - Напольные весы

    /// Квадрат со скруглёнными углами и окошко с числом посередине-сверху.
    ///
    /// Прежний рисунок показывал форму прибора — плита, окошко, ножки, — и
    /// формой этой мог оказаться планшет или коробка. Узнаёт вещь не силуэт, а
    /// число в окошке: «72» на квадрате читается весами и ничем другим.
    private func bodyScale(k: CGFloat, stroke: StrokeStyle) -> some View {
        let square = 72 * k
        return ZStack {
            RoundedRectangle(cornerRadius: square * 0.17, style: .continuous)
                .stroke(style: stroke)
                .frame(width: square, height: square)
            display("72", width: 33 * k, height: 15.5 * k, stroke: stroke)
                .offset(y: -15.5 * k)
        }
    }

    // MARK: - Настольные весы

    /// Прямоугольник, внутри круг площадки, над ним окошко с числом.
    ///
    /// Килограммы на напольных и граммы на настольных: две вещи различаются
    /// не только формой, но и тем, что показывают. Чаша на стойке, стоявшая
    /// здесь раньше, читалась кубком.
    private func kitchenScale(k: CGFloat, stroke: StrokeStyle) -> some View {
        let w = 77 * k, h = 65 * k
        return ZStack {
            RoundedRectangle(cornerRadius: h * 0.16, style: .continuous)
                .stroke(style: stroke)
                .frame(width: w, height: h)
            display("250", width: w * 0.42, height: h * 0.19, stroke: stroke)
                .offset(y: -h * 0.28)
            Circle()
                .stroke(style: stroke)
                .frame(width: h * 0.42, height: h * 0.42)
                .offset(y: h * 0.13)
        }
    }

    /// Окошко с числом: рамка и цифры внутри.
    ///
    /// Цифры шрифтом приложения, а не системным: это те же числа, что в
    /// дневнике, и набраны они должны быть так же.
    private func display(_ value: String, width: CGFloat, height: CGFloat,
                         stroke: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                .stroke(style: stroke)
            Text(verbatim: value)
                .font(.custom("Nunito-Bold", size: height * 0.72))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, height * 0.18)
        }
        .frame(width: width, height: height)
    }

    // MARK: - Браслет или часы

    /// Корпус, ремешки и колечко на циферблате — тот же знак, что у
    /// приложения. Часы в этом списке единственные необязательные, и
    /// напоминание о том, зачем они здесь, стоит прямо на них.
    private func watch(k: CGFloat, stroke: StrokeStyle) -> some View {
        ZStack {
            // Ремешки — за корпусом, поэтому рисуются первыми.
            ForEach([-1.0, 1.0], id: \.self) { side in
                RoundedRectangle(cornerRadius: 4 * k, style: .continuous)
                    .stroke(style: stroke)
                    .frame(width: 26 * k, height: 26 * k)
                    .offset(y: 26 * k * side)
            }

            RoundedRectangle(cornerRadius: 11 * k, style: .continuous)
                .fill(Color("LaunchBackground"))
                .frame(width: 46 * k, height: 54 * k)

            RoundedRectangle(cornerRadius: 11 * k, style: .continuous)
                .stroke(style: stroke)
                .frame(width: 46 * k, height: 54 * k)

            // Заводная головка.
            Capsule()
                .frame(width: 5 * k, height: stroke.lineWidth)
                .offset(x: 25 * k, y: -8 * k)

            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(style: StrokeStyle(lineWidth: stroke.lineWidth * 0.9, lineCap: .round))
                .frame(width: 22 * k, height: 22 * k)
                .rotationEffect(.degrees(50))
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        GearArt(kind: .bodyScale, color: MacroKind.protein.color)
        GearArt(kind: .kitchenScale, color: MacroKind.carbs.color)
        GearArt(kind: .watch, color: MacroKind.fat.color)
    }
    .frame(height: 140)
    .padding()
}
