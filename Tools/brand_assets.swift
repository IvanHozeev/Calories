import Foundation
import AppKit
import CoreGraphics
import ImageIO
import CoreText
import UniformTypeIdentifiers

// Знак Calories: «С» из трёх дуг — углеводы, жиры, белки. Незамкнутое кольцо макросов.
// Генерирует иконку (светлая, тёмная, tinted), логотип лаунч-скрина и иконку
// вкладки «Сегодня».
//
// Запуск из корня репозитория:
//   mkdir -p /tmp/brand && swift Tools/brand_assets.swift /tmp/brand
// Потом файлы разложить по Calories/Assets.xcassets: AppIcon.appiconset,
// LaunchLogo.imageset и TodayTab.imageset.
//
// Вайб — лёгкость и свежесть: плоские дуги цветами кольца «Сегодня» на светлом
// поле, без стекла, канавок и свечения. Прежний знак, прорезанный в чёрном
// стекле, спорил с приложением, которое стало светлым и тихим.

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.displayP3)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255,
                                            CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a])!
}
func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [v, v, v, a])! }

/// Рисуем в 16 битах на канал: плавные градиенты фона в 8 битах расходились
/// ступенями. Сохраняется уже в 8 бит одним переводом в конце.
func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 16, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
}

/// Непрозрачные картинки (иконка) сводятся к 8 битам без альфа-канала:
/// App Store не принимает иконки с прозрачностью.
func flatten(_ image: CGImage, opaque: Bool) -> CGImage {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: info)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

func save(_ ctx: CGContext, _ name: String) {
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, flatten(ctx.makeImage()!, opaque: name.hasPrefix("AppIcon")), nil)
    CGImageDestinationFinalize(dest)
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!,
                           start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Цвета дуг кольца «Сегодня» (ProgressRing): иконка и приложение одного цвета.
/// Сверху вниз против часовой — углеводы, жиры, белки, как на кольце.
let palette: [[CGColor]] = [
    [rgb(0xC08CFF), rgb(0x8B4DFF)],
    [rgb(0xFFA06B), rgb(0xFF6B3D)],
    [rgb(0x23DCF0), rgb(0x04ACDA)],
]
/// Доли дуг как у типичной сушки на 80 кг: углеводы 250 г, жиры 64 г, белки 160 г.
let grams: [CGFloat] = [250, 64, 160]
let weights = grams.map { $0 / grams.reduce(0, +) }
/// Разрыв повёрнут на 40° против часовой: знак читается кольцом, а не буквой.
let rotation: CGFloat = 40

let S: CGFloat = 1024
let iconCenter = CGPoint(x: S / 2, y: S / 2)

/// Середины трёх дуг. `outer` — внешний край знака, `width` — толщина дуги.
/// Зазор от толщины: скруглённые концы съедали бы фиксированный зазор.
func spines(width: CGFloat, outer: CGFloat) -> [CGPath] {
    let radius = outer - width / 2
    let gap = width * 1.25 / radius * 180 / .pi
    let opening = max(72, gap * 1.9)
    let top = 90 - rotation - opening / 2
    let available = 360 - opening - gap * 2
    var cursor = top
    return (0..<3).map { i in
        let end = cursor, start = end - available * weights[i]
        cursor = start - gap
        let arc = CGMutablePath()
        arc.addArc(center: iconCenter, radius: radius,
                   startAngle: (90 - start) * .pi / 180, endAngle: (90 - end) * .pi / 180, clockwise: true)
        return arc
    }
}

func outline(_ spine: CGPath, _ width: CGFloat) -> CGPath {
    spine.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// Подмешать белого к цвету — для едва заметного перехода внутри дуги.
func shade(_ color: CGColor, _ amount: CGFloat) -> CGColor {
    let c = color.components ?? [0, 0, 0, 1]
    func mix(_ v: CGFloat) -> CGFloat { v + (1 - v) * amount }
    return CGColor(colorSpace: space, components: [mix(c[0]), mix(c[1]), mix(c[2]), c.count > 3 ? c[3] : 1])!
}

/// Знак в стиле иконок Google (Gemini, Maps, Photos): плоско и чисто.
///
/// Их приёмы, снятые с самих иконок: чисто белое поле без градиента; ни тени,
/// ни блика — ни одного; каждая часть своего цвета, внутри почти ровного, с
/// едва заметным переходом вдоль формы; концы скруглены; знак крупный и
/// занимает большую часть поля. Объём там берётся не от света, а от плотной
/// формы и насыщенного цвета — стоит добавить блик, и иконка сразу читается
/// как глянец из 2010-го, а не как их.
func googleMark(_ ctx: CGContext, width: CGFloat, outer: CGFloat, grayscale: [CGFloat]? = nil) {
    for (index, spine) in spines(width: width, outer: outer).enumerated() {
        let shape = outline(spine, width)
        let bounds = shape.boundingBoxOfPath
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        if let grayscale {
            ctx.setFillColor(gray(grayscale[index]))
            ctx.fill(bounds)
        } else {
            // Переход внутри дуги едва заметный: у них цвет почти ровный, и
            // сильный градиент сразу выдаёт чужую руку.
            let pair = palette[index]
            linear(ctx, [shade(pair[0], 0.06), pair[1]],
                   from: CGPoint(x: bounds.minX, y: bounds.maxY), to: CGPoint(x: bounds.maxX, y: bounds.minY))
        }
        ctx.restoreGState()
    }
}

// MARK: - Иконка

/// Толщина и размер «С» на иконке: крупно, но с воздухом до краёв.
let iconWidth: CGFloat = 120
let iconOuter: CGFloat = 372

// Светлая: белое поле, чуть сереющее книзу.
do {
    let ctx = context(1024, 1024)
    ctx.setFillColor(gray(1)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    googleMark(ctx, width: iconWidth, outer: iconOuter)
    save(ctx, "AppIcon-light.png")
}
// Тёмная: то же на почти чёрном поле — как тёмная тема приложения.
do {
    let ctx = context(1024, 1024)
    linear(ctx, [rgb(0x1C1C1F), rgb(0x0A0A0B)], from: CGPoint(x: 0, y: S), to: CGPoint(x: 0, y: 0))
    googleMark(ctx, width: iconWidth, outer: iconOuter)
    save(ctx, "AppIcon-dark.png")
}
// Tinted: оттенки серого на чёрном, цвет даёт система.
do {
    let ctx = context(1024, 1024)
    ctx.setFillColor(gray(0)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    googleMark(ctx, width: iconWidth, outer: iconOuter, grayscale: [1, 0.85, 0.7])
    save(ctx, "AppIcon-tinted.png")
}

// MARK: - Лаунч-скрин

// Та же «С» размером 150 pt на холсте 180 pt, но тоньше иконки: на весь экран
// толщина иконки тяжелела.
//
// Было 230 — под размер кольца на «Сегодня», и это оказалось неверной меркой:
// кольцо там показывает съеденное за день, ему и положено занимать экран, а
// заставка — это знак приложения, и на 57% ширины он читался не логотипом, а
// увеличенным индикатором загрузки. 150 pt — примерно треть ширины экрана и
// ровно в два с половиной раза больше иконки на домашнем экране, так что
// переход с иконки на заставку читается приближением одного знака, а не
// прыжком. Фон — LaunchBackground,
// заставка (SplashView) продолжает этот кадр тем же знаком. Картинка одна на
// обе темы: плоские дуги одинаково читаются на светлом и на чёрном.
//
// Рисуется тем же знаком, что иконка: если на запуске цвет ведёт себя иначе,
// чем на иконке, с которой только что нажали, это замечают — переход с
// домашнего экрана в приложение читается как один кадр.
// Плотнее прежних 90: рядом с иконкой, откуда только что нажали, тонкий знак
// читался как другой. Всё ещё легче иконки — он тут один на весь экран.
let launchMarkWidth: CGFloat = 105

/// Знак и название: кольцо над словом, как в подписи внизу настроек.
///
/// Раньше на запуске стоял один знак на 150 pt — треть ширины экрана. Знак
/// без имени просит себя узнать, а узнавать на запуске нечего: человек и так
/// только что нажал на иконку. С именем он перестаёт быть загадкой и
/// становится подписью, а подписи незачем занимать треть экрана — поэтому
/// кольцо стало меньше.
///
/// Состав взят у `BrandFooter`, той самой миниатюры в конце настроек: кольцо,
/// под ним слово. Там это работает годами и читается как подпись под письмом.
let launchMarkSize: CGFloat = 96
/// Отношение знака к слову взято у миниатюры буквально: там кольцо 22 pt и
/// подпись 12 pt. Первая попытка поставила слово вдвое мельче, и знак снова
/// забирал всё внимание — то есть делала ровно то, от чего уходили.
/// Кегль надписи и её цвет держим вместе с заставкой: она продолжает этот
/// кадр, и разойтись им нельзя. Второй экземпляр этих чисел —
/// `BrandLockup` в Shared, менять только вместе.
let launchTitleSize: CGFloat = 28
/// Просвет — тоже как там: четыре точки при знаке в двадцать две.
let launchGap: CGFloat = launchMarkSize * 4 / 22
func launch(scale: CGFloat, name: String) {
    // Слово набираем первым: от его ширины зависит ширина холста.
    //
    // Системным шрифтом: скруглённым, полужирным. У скруглённого круглые
    // концы штрихов — те же, что у дуг знака над словом, — и вдвоём они
    // читаются одной вещью. Nunito, стоявший здесь раньше, был плотнее и уже
    // и спорил со знаком.
    //
    // Здесь это шрифт макоси, а на заставке — айоси, но это один и тот же
    // San Francisco: картинка и её продолжение совпадают. Веса и начертание
    // держатся вместе с `BrandLockup`, менять только вместе.
    let plain = NSFont.systemFont(ofSize: launchTitleSize * scale, weight: .semibold)
    let font = (plain.fontDescriptor.withDesign(.rounded)
                .flatMap { NSFont(descriptor: $0, size: launchTitleSize * scale) } ?? plain) as CTFont
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: rgb(0x8E8E93),
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: "Calories", attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

    // Холст по слову, а не наоборот: оно теперь шире знака, и обрезать его
    // полем фиксированной ширины значит однажды его обрезать.
    let width = max(bounds.width + 32 * scale, (launchMarkSize + 32) * scale)
    let height = (launchMarkSize + launchGap) * scale + bounds.height
    let ctx = context(Int(width.rounded(.up)), Int(height.rounded(.up)))

    let factor = (launchMarkSize * scale) / (2 * iconOuter)
    ctx.saveGState()
    ctx.translateBy(x: width / 2, y: height - launchMarkSize * scale / 2)
    ctx.scaleBy(x: factor, y: factor)
    ctx.translateBy(x: -iconCenter.x, y: -iconCenter.y)
    googleMark(ctx, width: launchMarkWidth, outer: iconOuter)
    ctx.restoreGState()

    ctx.textPosition = CGPoint(x: (width - bounds.width) / 2 - bounds.origin.x,
                               y: height - (launchMarkSize + launchGap) * scale
                                  - bounds.height - bounds.origin.y)
    CTLineDraw(line, ctx)

    save(ctx, name)
}
for (scale, suffix) in [(1.0, ""), (2.0, "@2x"), (3.0, "@3x")] {
    launch(scale: scale, name: "LaunchLogo\(suffix).png")
}

// MARK: - Иконка вкладки «Сегодня»

// Та же «С», одноцветным шаблоном — цвет выбранной и невыбранной вкладки даёт
// система. Вектором в PDF, 28×28 pt, как ячейка системного символа в таббаре.
// Тоньше иконки (около 3,7 pt): при толщине иконки дуги спорили весом с
// соседними символами.
do {
    let tabSide: CGFloat = 28
    let tabWidth: CGFloat = 105
    let factor = (tabSide / 2 - 1) / iconOuter
    var box = CGRect(x: 0, y: 0, width: tabSide, height: tabSide)
    let ctx = CGContext(out.appendingPathComponent("TodayTab.pdf") as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.translateBy(x: tabSide / 2, y: tabSide / 2)
    ctx.scaleBy(x: factor, y: factor)
    ctx.translateBy(x: -iconCenter.x, y: -iconCenter.y)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    for spine in spines(width: tabWidth, outer: iconOuter) {
        ctx.addPath(outline(spine, tabWidth))
        ctx.fillPath()
    }
    ctx.endPDFPage()
    ctx.closePDF()
}

// Парное начертание той же вкладки: дуги полые — только их контур.
//
// Нужно затем, что переход между выбранной и невыбранной вкладкой система
// играет сама, но только если есть во что перетекать. Со значком в одном
// начертании она не анимирует ничего: подменять нечем. Контурная «С» — та же
// форма, из которой вынули середину, поэтому заливка и контур совпадают по
// габаритам до точки, и перетекание идёт без рывка.
//
// Стенка около точки при дуге в три с половиной: тоньше — рвётся на экране
// без ретины, толще — внутри не остаётся просвета и полая дуга читается
// сплошной.
do {
    let tabSide: CGFloat = 28
    let tabWidth: CGFloat = 105
    let factor = (tabSide / 2 - 1) / iconOuter
    /// Толщина стенки в единицах холста: 1 pt после уменьшения.
    let wall = 1 / factor
    var box = CGRect(x: 0, y: 0, width: tabSide, height: tabSide)
    let ctx = CGContext(out.appendingPathComponent("TodayTabOutline.pdf") as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.translateBy(x: tabSide / 2, y: tabSide / 2)
    ctx.scaleBy(x: factor, y: factor)
    ctx.translateBy(x: -iconCenter.x, y: -iconCenter.y)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
    ctx.setLineWidth(wall)
    ctx.setLineJoin(.round)
    for spine in spines(width: tabWidth, outer: iconOuter) {
        // Контур дуги, а не сама дуга: берём ту же форму и обводим её край.
        ctx.addPath(outline(spine, tabWidth - wall))
        ctx.strokePath()
    }
    ctx.endPDFPage()
    ctx.closePDF()
}
