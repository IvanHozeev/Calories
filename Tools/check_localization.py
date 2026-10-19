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
            for entry in data.get("tables", {}).get("Localizable", []):
                if True:
                    key = entry.get("key")
                    if key:
                        keys.setdefault(key, source)
    return keys


def main() -> int:
    roots = build_dirs(sys.argv[1] if len(sys.argv) > 1 else None)
    if not roots:
        print("Не нашёл сборочный каталог. Соберите проект и повторите.")
        return 2

    found = keys_from_stringsdata(roots)
    if not found:
        print(f"В {roots[0]} нет .stringsdata — соберите проект заново.")
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
        gaps = [lang for lang in LANGUAGES
                if not locs.get(lang, {}).get("stringUnit", {}).get("value")]
        if gaps:
            missing[key] = (source, gaps)

    print(f"Ключей в сборке: {len(found)}. Без перевода: {len(missing)}.")
    for key, (source, gaps) in missing.items():
        print(f"  {source:30} {''.join(gaps):20} {key[:60]!r}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
