#!/bin/bash
# Сборка Calories одной командой — чтобы её можно было запустить откуда угодно:
# из «Команд» на телефоне по SSH, из удалённого стола, из чата со мной.
#
#   Tools/build.sh            — собрать и прогнать тесты на симуляторе
#   Tools/build.sh phone      — собрать и поставить на айфон по сети
#
# Своя папка сборки намеренно: общая DerivedData ломает сборку, идущую в
# это же время в Xcode, — две сборки дерутся за одну базу.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="${TMPDIR:-/tmp}/calories-build"
SIM="EA9D7E37-491D-4021-9DFF-00844371F9BC"

if [ "${1:-}" = "phone" ]; then
    # Телефон по сети числится «available (paired)», а не «connected»:
    # искали второе — и своего же телефона не находили. А потом искали первое
    # без границы слова — и «unavailable» подходило под «available», так что
    # отключённый телефон считался готовым, и сборка падала простынёй про
    # несовпадение платформ вместо внятного «телефона не видно». Берём любой, кого
    # devicectl готов обслужить.
    #
    # Только настоящее железо: devicectl перечисляет и симуляторы, и сам Mac,
    # и UDID у всех одной формы. Скрипт брал первое попавшееся — то собирал на
    # Mac, то на выключенный симулятор, и падал невнятной простынёй вместо
    # «телефона не видно».
    #
    # Идентификатор ловим в двух формах: старый UUID из CoreDevice и UDID
    # железа, который devicectl начал печатать вместо него. И гасим неудачу
    # grep: под `set -o pipefail` пустой результат убивал скрипт раньше, чем
    # тот успевал сказать, что телефона не видно, — выходило молчание.
    DEVICE=$(xcrun devicectl list devices 2>/dev/null \
        | grep -Ei '(^|[[:space:]])(available|connected)' \
        | grep -i 'physical' \
        | grep -Eo '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}|[0-9A-F]{8}-[0-9A-F]{16}' \
        | head -1 || true)
    if [ -z "$DEVICE" ]; then
        echo "Телефон не виден по сети: включи Wi-Fi и разбуди его."
        exit 1
    fi
    xcodebuild -scheme Calories -destination "platform=iOS,id=$DEVICE" \
        -derivedDataPath "$DERIVED-phone" -allowProvisioningUpdates build \
        > "$DERIVED-phone.log" 2>&1 || { grep -E "error:" "$DERIVED-phone.log" | head -5; exit 1; }
    xcrun devicectl device install app --device "$DEVICE" \
        "$DERIVED-phone/Build/Products/Debug-iphoneos/Calories.app" > /dev/null
    echo "Готово: собрано и поставлено на телефон."
    exit 0
fi

xcodebuild -scheme Calories -destination "platform=iOS Simulator,id=$SIM" \
    -derivedDataPath "$DERIVED" test > "$DERIVED.log" 2>&1 || {
        echo "Не собралось или упали тесты:"
        grep -E "error:|✘ Test " "$DERIVED.log" | sort -u | head -5
        exit 1
    }
grep -E "Test run with" "$DERIVED.log" | tail -1
echo "Готово: собрано, тесты прошли."
