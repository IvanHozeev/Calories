#!/usr/bin/env python3
"""Проверка каталога локализации на осиротевшие ключи.

Использование: python3 Tools/check_orphan_keys.py

Скрипт читает Calories/Localizable.xcstrings, извлекает все ключи,
используемые в коде Swift (String(localized:), String(format: String(localized: ...)),
String(localized: String.LocalizationValue(...)), и сообщает ключи из каталога,
которых нет в коде.

Для ключей со спецификаторами (%lld, %d, %f, %g, %@, %1$@, %2$lld и т.д.)
спецификатор заменяется на .* перед поиском, так как в коде ключ используется
через интерполяцию \(variable), которую Xcode извлекает как спецификатор формата.
"""

import json
import re
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(ROOT, 'Calories', 'Localizable.xcstrings')


def collect_code_files(root):
    """Собирает все .swift файлы в проекте."""
    files = []
    for dirpath, _, filenames in os.walk(os.path.join(root, 'Calories')):
        for f in filenames:
            if f.endswith('.swift'):
                files.append(os.path.join(dirpath, f))
    return files


def extract_used_keys(code_files):
    """Извлекает все ключи локализации, используемые в коде Swift."""
    used = set()

    for f in code_files:
        try:
            with open(f, encoding='utf-8') as fh:
                text = fh.read()
        except Exception:
            continue

        # String(localized: "ключ")
        for m in re.finditer(r'String\(localized:\s*"([^"]*)"', text):
            used.add(m.group(1))

        # String(format: String(localized: "ключ"), ...)
        for m in re.finditer(r'String\(format:\s*String\(localized:\s*"([^"]*)"', text):
            used.add(m.group(1))

        # String(localized: String.LocalizationValue("ключ"))
        for m in re.finditer(
            r'String\(localized:\s*String\.LocalizationValue\(\s*"([^"]*)"\s*\)',
            text,
        ):
            used.add(m.group(1))

    return used


def make_pattern(key: str) -> str:
    """Заменяет спецификаторы формата (%lld, %d, %f, %g, %@, %1$@ и т.д.)
    на .* и экранирует остальную строку для использования в regex."""
    parts = re.split(r'(%[\d$]*[dlufgsx])', key)
    result = ''
    for part in parts:
        if re.fullmatch(r'%[\d$]*[dlufgsx]', part):
            result += '.*'
        else:
            result += re.escape(part)
    return result


def main():
    with open(CATALOG_PATH, encoding='utf-8') as f:
        catalog = json.load(f)

    catalog_keys = set(catalog['strings'].keys())
    code_files = collect_code_files(ROOT)
    used_keys = extract_used_keys(code_files)

    unused = []
    for key in sorted(catalog_keys):
        if key in used_keys:
            continue
        if '%' in key:
            pattern = make_pattern(key)
            # Читаем все кодовые файлы в одну строку для поиска
            all_code = ''
            for f in code_files:
                try:
                    with open(f, encoding='utf-8') as fh:
                        all_code += fh.read()
                except Exception:
                    continue
            if re.search(pattern, all_code):
                used_keys.add(key)
                continue
        unused.append(key)

    print(f'Всего ключей в каталоге: {len(catalog_keys)}')
    print(f'Всего ключей найдено в коде: {len(used_keys)}')
    print(f'Ключей в каталоге, не найденных в коде: {len(unused)}')
    print()

    for key in unused:
        print(repr(key))

    return len(unused)


if __name__ == '__main__':
    sys.exit(main())
