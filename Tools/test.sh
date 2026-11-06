#!/bin/bash
#
# Прогон набора — один и тот же локально и на CI.
#
# Один скрипт на оба места намеренно: зелёный у себя и зелёный на сервере
# должны значить одно и то же. Разные команды в хуке и в workflow расходятся
# через месяц, и выясняется это в худший момент.
#
#   Tools/test.sh          — юниты
#   Tools/test.sh --all    — юниты и UI-тесты
#
set -o pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

SCHEME="Calories"
# Своя папка сборки обязательна. Общая с Xcode даёт «invalid reuse after
# initialization failure» и прогон, в котором выполнено ноль тестов, — без
# единого падения и без намёка на причину.
DERIVED="${CALORIES_DERIVED:-${TMPDIR:-/tmp}/calories-tests-dd}"
# Проектный симулятор: на нём гоняют локально, и он на нужном рантайме.
# На чужой машине его нет — тогда сработает запасной выбор ниже.
DEVICE="${CALORIES_DEVICE:-Calories iOS 27}"
# Минимум, на котором приложение вообще собирается. Ниже него симулятор не
# подойдёт, и лучше сказать это прямо, чем собирать полчаса впустую.
MIN_OS="${CALORIES_MIN_OS:-26.0}"

ONLY_UNIT=(-only-testing:CaloriesTests)
[ "$1" = "--all" ] && ONLY_UNIT=()

echo "▸ Xcode: $(xcodebuild -version | head -1)"

# Устройство ищем по имени, а берём по UDID. По имени xcodebuild молча
# добавляет «OS:latest» и не находит симулятор на другом рантайме — ошибка
# при этом говорит про destination, а не про версию.
udid_of() {
    xcrun simctl list devices available \
        | grep -m1 "^ *$1 (" \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

# Версия рантайма, на котором стоит устройство: simctl печатает их секциями
# «-- iOS 27.0 --», поэтому запоминаем последнюю виденную.
os_of_udid() {
    xcrun simctl list devices available | awk -v want="$1" '
        /^-- / { os = $3 }
        index($0, want) { print os; exit }'
}

UDID="$(udid_of "$DEVICE")"
if [ -z "$UDID" ]; then
    echo "▸ «$DEVICE» не найден, беру первый доступный iPhone"
    UDID="$(xcrun simctl list devices available | grep -m1 -E '^ *iPhone .*\(' \
            | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
fi

if [ -z "$UDID" ]; then
    echo "✘ Ни одного симулятора iPhone. Рантаймы, которые есть:"
    xcrun simctl list runtimes
    exit 1
fi

OS="$(os_of_udid "$UDID")"
# Сравниваем версии числами, а не строками: «9.0» строкой больше «26.0».
if [ -n "$OS" ] && ! awk -v a="$OS" -v b="$MIN_OS" 'BEGIN { exit !(a + 0 >= b + 0) }'; then
    echo "✘ Симулятор на iOS $OS, а приложению нужен $MIN_OS и выше."
    echo "  Молчаливо взять что попало нельзя: сборка упадёт позже и непонятнее."
    xcrun simctl list runtimes
    exit 1
fi
echo "▸ Симулятор: $DEVICE ($UDID), iOS ${OS:-?}"

# Выбор шрифта и размера переживает прогоны и ломает следующий: тест о шрифте
# оставляет приложение с засечками на минимальном размере.
xcrun simctl spawn "$UDID" defaults delete ivankhozeyev.team.Calories app_font 2>/dev/null
xcrun simctl spawn "$UDID" defaults delete ivankhozeyev.team.Calories app_text_size 2>/dev/null

LOG="$DERIVED/last-run.log"
mkdir -p "$DERIVED"

xcodebuild -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" \
    "${ONLY_UNIT[@]}" \
    test > "$LOG" 2>&1
STATUS=$?

# Результат читаем до любых ls и grep: они перетрут $?.
#
# И не грепом по «error:» — xcodebuild печатает фантомное «the following
# command failed with exit code 0 but produced no further output» на вполне
# успешной сборке, и чинить начинаешь несуществующее.
grep -E "✔ Test run|✘ Test|XCTAssert|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" "$LOG" \
    | sort -u | tail -8

if [ $STATUS -ne 0 ]; then
    echo
    echo "✘ Набор красный. Полный лог: $LOG"
    RESULT="$(ls -td "$DERIVED"/Logs/Test/*.xcresult 2>/dev/null | head -1)"
    [ -n "$RESULT" ] && echo "  Разбор: $RESULT"
    exit $STATUS
fi

echo "✔ Набор зелёный"
