import SwiftUI

/// Заголовок экрана: название и строка контекста над ним.
///
/// Системный инлайн-заголовок стоит мелким по центру шапки и умеет только
/// название. А экрану обычно нужна ещё строка: какая это неделя, какой день,
/// какая фаза. Она лежала карточкой ниже и повторяла то, что и так ясно из
/// заголовка.
///
/// Живёт в шапке, в слоте `principal`. Слот — это уже промежуток между
/// кнопками: он начинается после «назад» и кончается перед теми, что справа.
/// Но своей ширины он не предлагает и центрует всё, что уже него. Поэтому
/// заголовку выдаётся ровно ширина промежутка и велено стоять у его левого
/// края — см. `inBar`.
///
/// Тише, чем у соседнего приложения: там чёрный вес и фирменный цвет надписи
/// сверху, здесь обычный жирный — у Calories язык спокойнее, и кричать
/// заголовком тут нечем.
struct ScreenTitle: View {
    let title: String
    /// Строка над названием: даты, неделя плана, день недели.
    var eyebrow: String? = nil
    /// Строка под названием — там, где название общее, а уточнение частное:
    /// «Сегодня» и какое именно сегодня.
    var subtitle: String? = nil
    /// В шапке, а не в содержимом: две плотные строки в сорок четыре точки.
    /// Перестаёт быть крупным — и взамен перестаёт уезжать прокруткой.
    var isCompact = false
    /// Сколько строк отдать названию в шапке. Две, помельче, — тем, что иначе
    /// приедут туда многоточием.
    var compactLines = 1
    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 0 : 2) {
            if let eyebrow {
                Text(verbatim: eyebrow.uppercased())
                    .font(.app(.caption2, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
            // Ступенью ниже корневой вкладки и выше заголовков секций.
            //
            // Лестница сверху вниз: вкладка `title2`, экран, открытый
            // переходом, — `title3`, заголовок секции в списке — системные
            // пятнадцать точек. Экран, лежащий глубже, крупнее того, откуда
            // в него вошли, быть не может; раньше было ровно так.
            Text(verbatim: title)
                .font(.app(isCompact ? (compactLines > 1 ? .headline : .title3) : .largeTitle,
                           weight: .bold))
                .lineLimit(isCompact ? compactLines : 2)
                .minimumScaleFactor(0.7)
                // Заголовком бывает название записи, а оно бывает на иврите:
                // без этого оно уезжало к правому краю шапки.
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, isCompact ? 0 : 4)
        .padding(.bottom, isCompact ? 0 : 2)
        .accessibilityElement(children: .combine)
        // Именем панели становится имя того, что в ней стоит. Собранная из двух
        // строк подпись делала панель «13 ОКТЯБРЯ, РАЗБОР ДНЯ» — найти шапку по
        // названию экрана после этого было нечем, ни тесту, ни человеку.
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: eyebrow ?? subtitle ?? ""))
        .accessibilityAddTraits(.isHeader)
    }

    /// «6 – 12 октября»: неделя, о которой речь. Месяц пишется один раз, когда
    /// оба конца в нём же.
    static func weekRange(from start: Date, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        let from = start.formatted(sameMonth ? .dateTime.day() : .dateTime.day().month(.wide))
        return "\(from) – \(end.formatted(.dateTime.day().month(.wide)))"
    }
}

/// Ширина окна, в котором живёт шапка.
///
/// Не `UIScreen.main`: с iOS 26 он объявлен устаревшим и в iOS 27 остался
/// только ради совместимости. Дело не в предупреждении компилятора — экран и
/// окно перестали совпадать: на айпаде в Stage Manager и в разделённом экране
/// окно уже́ экрана, и заголовок, посчитанный по экрану, уезжал под кнопки.
///
/// Берём активную сцену, как и советует Apple взамен: сначала ключевое окно,
/// потом экран сцены, и только если нет ни того ни другого — ширина iPhone,
/// на которой заголовки и выверялись.
enum BarWidth {
    static var current: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let window = scene?.keyWindow?.bounds.width, window > 0 { return window }
        return scene?.screen.bounds.width ?? 393
    }

    /// Ширина кнопки-надписи в шапке — «Отмена» и ей подобных.
    ///
    /// Шеврон «назад» всегда сорок четыре точки, а надпись — столько, сколько
    /// в ней букв: «Отмена» заметно шире шеврона, а по-немецки шире ещё. Пока
    /// под неё отводили те же сорок четыре, заголовок листа начинался под
    /// кнопкой и приезжал обрезанным слева — «вой продукт» вместо «Свой
    /// продукт».
    ///
    /// Поэтому меряем саму надпись тем же шрифтом, которым её рисует панель,
    /// и добавляем поля капсулы.
    /// Шрифты живут на главной очереди, а шапка строится только там —
    /// `inBar` вызывается из тела вьюхи и ниоткуда больше.
    /// Ширина названия экрана тем шрифтом, которым его рисует шапка.
    ///
    /// Нужна, чтобы не задавать рамку там, где название и так помещается:
    /// широкая рамка в левом слоте выталкивает кнопки справа в «ещё», а то и
    /// вытесняет сам заголовок. Меряем — и рамку ставим только длинным, тем,
    /// которым нужен перенос.
    nonisolated static func titleWidth(_ title: String, size: CGFloat = 22) -> CGFloat {
        MainActor.assumeIsolated {
            var font = UIFont.systemFont(ofSize: size, weight: .bold)
            if let name = AppFont.customName(for: .bold), let custom = UIFont(name: name, size: size) {
                font = custom
            } else if let design = AppFont.current.systemDesign,
                      let descriptor = font.fontDescriptor.withDesign(design) {
                font = UIFont(descriptor: descriptor, size: size)
            }
            return (title as NSString).size(withAttributes: [.font: font]).width
        }
    }

    nonisolated static func textButton(_ title: String) -> CGFloat {
        MainActor.assumeIsolated {
            let font = UIFont.preferredFont(forTextStyle: .body)
            let text = (title as NSString).size(withAttributes: [.font: font]).width
            return max(44, text.rounded(.up) + 32)
        }
    }
}

extension View {
    /// Ширина промежутка между кнопками шапки — та, которую заголовок забирает
    /// себе, чтобы встать у его левого края, а не по центру.
    ///
    /// Отдельный отступ под «назад» сверх этого — ровно то, что отодвигало
    /// каждый заголовок вправо: слот и так начинается после кнопки. А взять всю
    /// панель целиком — наоборот, увести его за левый край.
    func inBar(back: Bool = true, cancelTitle: String? = nil, trailingButtons: Int = 0) -> some View {
        let leading = cancelTitle.map(BarWidth.textButton) ?? (back ? 44 : 0)
        let width = BarWidth.current - 48
            - leading
            - CGFloat(trailingButtons) * 46
        return frame(width: max(120, width), alignment: .leading)
    }

    /// Заголовок-строка списка: без подложки, разделителя и отступов ячейки.
    func asScreenTitleRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
    }

    /// Название корневой вкладки — тем же кеглем, что и на «Сегодня».
    ///
    /// Системный `.inlineLarge`, который стоял на «Профиле» и «Рационе»,
    /// рисует заголовок заметно крупнее. На «Сегодня» так сделать нельзя:
    /// крупный системный заголовок держит слева самого себя и не пускает
    /// перед собой знак дня, поэтому шапка там собрана вручную из `.title3`.
    /// Вкладки из-за этого разъехались по размеру, и переход между ними
    /// читался как переход между приложениями.
    ///
    /// Верх лестницы заголовков: вкладка `title2`, экран, открытый из неё
    /// переходом, — `title3`, заголовок секции — системные пятнадцать точек.
    ///
    /// От `screenTitle` отличается двумя вещами: кегль на ступень крупнее —
    /// ровно тот, что на «Сегодня», — и место в шапке не среднее, а левое.
    ///
    /// Средний слот к левому краю не прижать. Тулбар меряет его содержимое и
    /// ставит рамку по центру того, что осталось от кнопок: `maxWidth:
    /// .infinity` он не расширяет, а `inBar` с числовой шириной промахивается
    /// — он считает промежуток по числу кнопок, по сорок шесть точек на
    /// каждую, а на вкладках они собраны в одну стеклянную капсулу. Выходило
    /// то «Профиль» посреди шапки, то «Рацион» за её левым полем.
    ///
    /// В левом слоте прижимать нечего: он и есть левый край. Подложку ему
    /// гасим — иначе iOS 26 нарисует под названием стекло, будто это кнопка.
    ///
    /// Длинное имя переносится на вторую строку, а не ужимается в одну.
    /// «Рыба и морепродукты» в строку не влезала, и шапка отбирала место у
    /// кнопок справа — три из них сворачивались в «ещё». Две строки стоят
    /// шапке высоты, которой у неё в избытке, и ничего ни у кого не отнимают.
    ///
    /// - Parameter trailingRoom: сколько точек справа занято кнопками
    ///   вместе с их полем до края. В точках, а не в числе кнопок: на
    ///   вкладках они собраны в одну стеклянную капсулу, и её ширина — не
    ///   сумма кнопок. Из него считается ширина заголовка: в левом слоте её
    ///   надо задать числом, иначе слот выдаёт минимум и имя приезжает одной
    ///   буквой с многоточием. Недосчитать тоже нельзя — «морепродукты» в
    ///   сто шестьдесят одну точку не влезали, хотя места было сто
    ///   восемьдесят девять.
    /// - Parameter rising: откуда въезжает новое имя. `true` — снизу, как
    ///   секция, к которой доехали, листая вниз; `false` — сверху.
    func tabTitle(_ title: String, trailingRoom: CGFloat = 0, rising: Bool = true) -> some View {
        softScrollEdge()
            .navigationTitle(title)
            .hiddenNavigationTitle()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(verbatim: title)
                        .font(.app(.title2, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .modifier(TitleRoom(title: title, trailingRoom: trailingRoom))
                        // Имя меняется на прокрутке — на каждой границе
                        // секции. Подменять его встык значит мигать посреди
                        // жеста.
                        // Перетекание вбок показывало бы движение, которого
                        // не было: список едет вверх и вниз. Новое имя
                        // приходит с той стороны, откуда приехала его
                        // секция, а старое уходит в противоположную.
                        .id(title)
                        .transition(.asymmetric(
                            insertion: .move(edge: rising ? .bottom : .top).combined(with: .opacity),
                            removal: .move(edge: rising ? .top : .bottom).combined(with: .opacity)))
                        .animation(.easeInOut(duration: 0.2), value: title)
                }
                .withoutSharedBackground()
            }
    }

    /// Заголовок экрана в шапке: название и строка контекста над ним.
    ///
    /// Системный заголовок при этом прячется — два заголовка в одной шапке
    /// спорят за одно место, и побеждает не тот, что нужен.
    /// - Parameter cancelTitle: надпись кнопки слева, когда там не шеврон, а
    ///   слово: у листа это «Отмена». Нужна, чтобы заголовок знал, сколько
    ///   места занято, — по букве, а не по догадке.
    func screenTitle(_ title: String,
                     eyebrow: String? = nil,
                     lines: Int = 1,
                     backButton: Bool = true,
                     cancelTitle: String? = nil,
                     trailingButtons: Int = 0) -> some View {
        softScrollEdge()
            .navigationTitle(title)
            .hiddenNavigationTitle()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ScreenTitle(title: title, eyebrow: eyebrow,
                                isCompact: true, compactLines: lines)
                        .inBar(back: backButton, cancelTitle: cancelTitle,
                               trailingButtons: trailingButtons)
                }
            }
    }

    /// Заголовок экрана в левом слоте шапки вместо центрального (.principal).
    ///
    /// При активном поиске iOS скрывает .principal, чтобы отдать центр под
    /// строку поиска, и тайтл пропадает. Размещение в .topBarLeading не
    /// скрывается — как на корневых вкладках («Сегодня», «Рацион»).
    func topBarTitle(_ title: String,
                     eyebrow: String? = nil,
                     lines: Int = 1,
                     backButton: Bool = true,
                     cancelTitle: String? = nil,
                     trailingButtons: Int = 0) -> some View {
        softScrollEdge()
            .navigationTitle(title)
            .hiddenNavigationTitle()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ScreenTitle(title: title, eyebrow: eyebrow,
                                isCompact: true, compactLines: lines)
                        .inBar(back: backButton, cancelTitle: cancelTitle,
                               trailingButtons: trailingButtons)
                }
                .withoutSharedBackground()
            }
    }
}


/// Ширина названия в шапке: своя, пока оно помещается в строку, и ровно по
/// свободному месту, когда нет.
///
/// Рамку нельзя ставить всегда. Левый слот тулбара рамку уважает, и широкая
/// отнимает место у кнопок справа: три кнопки «Рациона» сворачивались в
/// «ещё», а на «Профиле» пропадал и сам заголовок. Но и без рамки нельзя:
/// слот предлагает минимум ширины, и длинное имя приезжает одной буквой с
/// многоточием.
private struct TitleRoom: ViewModifier {
    let title: String
    let trailingRoom: CGFloat

    func body(content: Content) -> some View {
        // Шестнадцать точек поля слева, восемь зазора до кнопок — остальное
        // заголовку.
        let room = max(120, BarWidth.current - 24 - 8 - trailingRoom)
        // Две точки запаса: мерка и вёрстка округляют по-разному, и имя
        // ровно в край уехало бы в перенос из-за десятой доли точки.
        let fits = BarWidth.titleWidth(title) + 2 <= room
        return content
            .fixedSize(horizontal: fits, vertical: true)
            .frame(width: fits ? nil : room, alignment: .leading)
    }
}

extension View {
    /// Шапка размывает содержимое под собой, а не отрезает его.
    ///
    /// По умолчанию iOS 26 режет прокрученное под шапкой прямой линией: под
    /// ней проходит шов, а строки обрываются по линейке, и это читается как
    /// второй бар. Экран со своим заголовком — всегда список или прокрутка,
    /// поэтому край задаётся здесь, вместе с заголовком, а не по разу на
    /// каждом экране: так его неоткуда забыть.
    fileprivate func softScrollEdge() -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
    }
}
