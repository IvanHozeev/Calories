#!/usr/bin/env python3
"""Поиск дубликатов переводов в Localizable.xcstrings.

Находит английские ключи, у которых одинаковые переводы на других языках,
но разные ключи в каталоге. Например:
- «Белки» и «Белок» могут иметь одинаковый перевод на английском «Protein»
- «Взвеситься» и «Записать вес» могут иметь одинаковый перевод «Log weight»

Использование: python3 Tools/check_duplicate_translations.py
"""

import json
import re
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(ROOT, 'Calories', 'Localizable.xcstrings')
REPORT_PATH = os.path.join(ROOT, 'Docs', 'duplicate-strings.md')

LANGUAGES = ['ar', 'de', 'en', 'es', 'fr', 'he', 'pt', 'ru']


def main():
    with open(CATALOG_PATH, encoding='utf-8') as f:
        catalog = json.load(f)

    strings = catalog['strings']
    catalog_keys = set(strings.keys())
    print(f'Всего ключей в каталоге: {len(catalog_keys)}')

    # Для каждого языка собираем mapping: перевод -> список ключей
    lang_to_values = {}
    for lang in LANGUAGES:
        lang_to_values[lang] = {}
        for key, entry in strings.items():
            loc = entry.get('localizations', {})
            if lang in loc:
                value = loc[lang].get('stringUnit', {}).get('value', '')
                if value not in lang_to_values[lang]:
                    lang_to_values[lang][value] = []
                lang_to_values[lang][value].append(key)

    # Находим дубликаты: когда один перевод соответствует нескольким ключам
    duplicates = {}
    for lang, keys_by_value in lang_to_values.items():
        for value, keys in keys_by_value.items():
            if len(keys) > 1:
                for key in keys:
                    if key not in duplicates:
                        duplicates[key] = {}
                    duplicates[key][lang] = keys

    print(f'Ключей с дубликатами переводов: {len(duplicates)}')

    # Выводим отчёт
    lines = []
    lines.append('# Дубликаты переводов в Localizable.xcstrings')
    lines.append('')
    lines.append(f'Всего ключей в каталоге: {len(catalog_keys)}')
    lines.append(f'Ключей с дубликатами переводов: {len(duplicates)}')
    lines.append('')
    lines.append('Каждый ключ имеет одинаковый перевод на одном или нескольких языках, '
                 'но отличается от других ключей с таким же переводом.')
    lines.append('')
    lines.append('| Ключ | Язык | Значение | Другие ключи с таким же переводом |')
    lines.append('|------|--------|----------|-----------------------------------|')

    for key in sorted(duplicates.keys()):
        langs = duplicates[key]
        for lang in sorted(langs.keys()):
            keys = sorted(langs[lang])
            value = catalog['strings'][keys[0]]['localizations'][lang].get('stringUnit', {}).get('value', '')
            other_keys = [k for k in keys if k != key]
            other_keys_str = ', '.join(repr(k) for k in other_keys)
            escaped_key = key.replace('|', '\\|')
            escaped_value = value.replace('|', '\\|')
            escaped_proof = other_keys_str.replace('|', '\\|')
            lines.append(f'| {escaped_key} | {lang} | {escaped_value} | {escaped_proof} |')

    lines.append('')
    lines.append('---')
    lines.append('')
    lines.append(f'Всего ключей в каталоге: {len(catalog_keys)}')
    lines.append(f'Ключей с дубликатами переводов: {len(duplicates)}')

    with open(REPORT_PATH, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f'Отчёт сохранён в {REPORT_PATH}')
    return len(duplicates)


if __name__ == '__main__':
    sys.exit(main())
PYEOF
python3 /Users/ivankhozeyev/Desktop/Apps/Calories/Tools/check_duplicate_translations.py 2>&1 | head -120