#!/usr/bin/env python3
"""Ищет строки, которые уйдут в релиз по-русски.

Проверка по исходникам регулярками пропускала всё, где есть подстановка:
`Text("из \\(goal) ккал")` в каталоге лежит ключом `из %lld ккал`, и глазами
эти два написания не сводятся. Так в приложении полгода жили пятнадцать
строк, показывавшихся по-русски в английском интерфейсе.

Компилятор же выписывает точные ключи в `.stringsdata` — по одному файлу на
каждый исходник. Сверяем с каталогом их, а не свои догадки.

    python3 Tools/check_localization.py [путь-к-DerivedData]

Без аргумента берёт сборочный каталог Xcode. Если его нет — соберите проект
(любой сборкой, хоть на симулятор) и повторите.

Сборка должна быть свежее исходников, иначе проверка отвечает про вчерашний
код. Так она однажды показала тридцать две «непереведённые» строки, которых
в проекте уже не было: собирали в свою папку, а скрипт читал каталог Xcode
недельной давности. Пустой ответ от устаревшей сборки хуже, чем никакого, —
поэтому несвежую мы не разбираем вовсе, а требуем пересобрать.
"""
import json
import glob
import os
import re
import sys

LANGUAGES = ["en", "es", "pt", "fr", "de", "ar", "he"]
# Каталогов два: у приложения и у виджета. Ключ, переведённый в любом из
# них, на экране будет переведён — таблица одна и та же.
CATALOGS = ["Calories/Localizable.xcstrings", "CaloriesWidget/Localizable.xcstrings"]

# Названия языков в списке выбора намеренно остаются на своём языке.
ALLOWED_RUSSIAN = {"Русский"}


def build_dirs(root: str | None) -> list[str]:
    if root:
        return [root]
    found = glob.glob(os.path.expanduser("~/Library/Developer/Xcode/DerivedData/Calories-*"))
    return sorted(found, key=os.path.getmtime, reverse=True)[:1]


def newest(paths) -> float:
    """Время последней правки среди путей. Ноль, если путей нет."""
    times = []
    for path in paths:
        try:
            times.append(os.path.getmtime(path))
        except OSError:
            pass
    return max(times, default=0.0)


def staleness(roots: list[str]) -> float:
    """На сколько секунд сборка отстала от исходников. Ноль — не отстала.

    Сравниваем по времени правки: `.stringsdata` переписывается, когда файл
    перекомпилировали, и для не тронутых файлов в папке остаются вчерашние.
    Если хоть один исходник новее самого нового `.stringsdata`, ответ скрипта
    описывает не тот код, который лежит в рабочей копии.
    """
    sources = newest(glob.glob("Calories*/**/*.swift", recursive=True)
                     + glob.glob("Shared/**/*.swift", recursive=True))
    built = newest(path for root in roots
                   for path in glob.glob(os.path.join(root, "**", "*.stringsdata"), recursive=True))
    return max(0.0, sources - built)


def keys_from_stringsdata(roots: list[str]) -> dict[str, str]:
    """Ключ → файл, в котором компилятор его встретил."""
    keys: dict[str, str] = {}
    for root in roots:
        for path in glob.glob(os.path.join(root, "**", "*.stringsdata"), recursive=True):
            try:
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
            except (ValueError, OSError):
                continue
            source = os.path.basename(path).replace(".stringsdata", ".swift")
            # Только строки интерфейса: ярлыки Siri и Info.plist живут в
            # своих таблицах, и каталогов у них нет — им своя работа.
            # Только строки интерфейса: ярлыки Siri и Info.plist живут в
            # своих таблицах, и каталогов у них нет — им своя работа.
            for entry in data.get("tables", {}).get("Localizable", []):
                key = entry.get("key")
                if key:
                    keys.setdefault(key, source)
    return keys


def translated(entry) -> bool:
    """Есть ли на этом языке перевод — простой строкой или по числам.

    У множественных форм нет `stringUnit`: вместо него `variations.plural`
    с ветками `one`, `few`, `many`, `other`, и у каждого языка свой набор.
    Пока скрипт искал только простую строку, он объявлял непереведённым
    всё, что склоняется по числу, — а это как раз те строки, где перевод
    стоил дороже всего.
    """
    if not entry:
        return False
    if entry.get("stringUnit", {}).get("value"):
        return True
    plural = entry.get("variations", {}).get("plural", {})
    return any(form.get("stringUnit", {}).get("value") for form in plural.values())


def main() -> int:
    roots = build_dirs(sys.argv[1] if len(sys.argv) > 1 else None)
    if not roots:
        print("Не нашёл сборочный каталог. Соберите проект и повторите.")
        return 2

    found = keys_from_stringsdata(roots)
    if not found:
        print(f"В {roots[0]} нет .stringsdata — соберите проект заново.")
        return 2

    behind = staleness(roots)
    if behind > 0:
        hours = behind / 3600
        print(f"Сборка в {roots[0]}")
        print(f"отстала от исходников на {hours:.1f} ч — проверять по ней нечего.")
        print("Соберите проект в эту же папку и повторите:")
        print("  xcodebuild -scheme Calories -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build")
        print("или передайте свою папку сборки первым аргументом.")
        return 2

    catalog: dict = {}
    for path in CATALOGS:
        with open(path, encoding="utf-8") as f:
            for key, value in json.load(f)["strings"].items():
                merged = catalog.setdefault(key, {"localizations": {}})
                merged["localizations"].update(value.get("localizations") or {})

    missing: dict[str, tuple[str, list[str]]] = {}
    for key, source in sorted(found.items()):
        if not re.search(r"[А-Яа-яЁё]", key) or key in ALLOWED_RUSSIAN:
            continue
        locs = catalog.get(key, {}).get("localizations", {})
        gaps = [lang for lang in LANGUAGES if not translated(locs.get(lang))]
        if gaps:
            missing[key] = (source, gaps)

    print(f"Ключей в сборке: {len(found)}. Без перевода: {len(missing)}.")
    for key, (source, gaps) in missing.items():
        print(f"  {source:30} {''.join(gaps):20} {key[:60]!r}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
