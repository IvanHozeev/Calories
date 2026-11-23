# Иконка «Резина»

`rubber.html` рисует три дуги кольца как объёмные резиновые детали: свет сверху слева,
толщина — 16 сдвинутых копий темнее, мягкая тень под знаком. Тот же приём, что у иконки
GymLogger, только на дугах. Режим — в адресе после `#`, в виде `<вариант>-<режим>`:
вариант `1` — «Три макроса» (выбран), `2` — пастель кольца, `3` — со стальным шаром;
режимы `light`, `dark`, `tinted`, `mark` (только знак на прозрачном, для Icon Composer),
`markdark` (то же с более глубокой тенью — для тёмного оформления).

`render.swift` открывает страницу в WKWebView и пишет PNG 1024×1024. Путь к странице —
абсолютный:

```sh
swiftc -O Tools/IconRender/render.swift -o /tmp/icon-render
/tmp/icon-render "$PWD/Tools/IconRender/rubber.html" 1-light /tmp/AppIcon-light.png
```

Куда что идёт:
- `1-mark` → `Calories/AppIcon.icon/Assets/Mark.png`, `1-markdark` → `MarkDark.png`
  (iOS 26: слой без стекла и без системной тени — свет и тень уже нарисованы; фон — градиент
  в `icon.json`);
- `1-light`, `1-dark`, `1-tinted` → `Assets.xcassets/AppIcon.appiconset/AppIcon-*.png`.

Подводный камень: `AppIcon.icon` и `AppIcon.appiconset` называются одинаково, и iOS 26 берёт
именно `.icon` — PNG из набора там не показываются. Менять нужно оба.

## Экран запуска

Раскладка — `Calories/LaunchScreen.storyboard`: резиновое кольцо по центру
(`LaunchLogo`, делает `launch_logo.swift`) и подпись «from Vanya Hozeyev» на 24 pt выше нижней
безопасной зоны (`LaunchFooter`, делает `footer.swift`) — как у GymLogger и Budget. Слова
«Calories» на запуске и на заставке нет. Подпись — картинка, потому что раскладка не умеет ни
скруглённого шрифта, ни градиента в буквах; имя залито цветами дуг иконки. Заставка
(`SplashView`) повторяет раскладку до точки, размеры подписи лежат и там, и в storyboard.
