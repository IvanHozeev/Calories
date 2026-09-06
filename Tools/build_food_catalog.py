#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Собирает Calories/Resources/FoodCatalog.json — встроенный каталог продуктов.

Каталог нужен потому, что оба сетевых источника перекошены. Open Food Facts
знает брендовые товары, но требует сети и плохо отвечает на «гречка». USDA знает
состав, но требует ключ с лимитом на ключ, а не на пользователя, — раздать такой
всем нельзя. Встроенный каталог одинаков у всех, работает офлайн и мгновенно.

Два источника данных:

* `Tools/food_core.txt` — курируемое ядро. То, что человек вводит каждый день,
  с русскими названиями и осмысленными порциями. Готовые блюда вроде борща и
  сырников есть только здесь: в USDA их нет.

* USDA SR Legacy (необязательно) — длинный хвост. Данные общественного достояния,
  числа авторитетные. Названия английские; русское появляется только там, где
  словарь `Tools/food_terms_ru.json` уверенно перевёл **все** части названия.
  Полупереведённое «Beef, фарш, raw» хуже честного английского.

Использование:

    python3 Tools/build_food_catalog.py                      # только ядро
    python3 Tools/build_food_catalog.py --usda sr_legacy.json --limit 2000

Файл SR Legacy берётся здесь (раздел «SR Legacy», JSON):
https://fdc.nal.usda.gov/download-datasets.html
"""

import argparse
import json
import os
import re
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(ROOT, "Tools", "food_core.txt")
TERMS = os.path.join(ROOT, "Tools", "food_terms_ru.json")
OUT = os.path.join(ROOT, "Calories", "Resources", "FoodCatalog.json")

CATEGORIES = {"meat", "fish", "dairy", "legumes", "grains", "dishes",
              "produce", "mushrooms", "fats", "sweets", "drinks", "other"}

# Идентификаторы нутриентов в USDA. Совпадают с Micronutrient.usdaNutrientID
# в приложении — если менять, менять в обоих местах.
ENERGY, PROTEIN, FAT, CARBS = 1008, 1003, 1004, 1005
MICRO = {
    1106: "vitaminA", 1162: "vitaminC", 1114: "vitaminD", 1109: "vitaminE",
    1175: "vitaminB6", 1178: "vitaminB12", 1177: "folate", 1087: "calcium",
    1089: "iron", 1090: "magnesium", 1095: "zinc", 1092: "potassium",
    1093: "sodium", 1103: "selenium",
}

# Категории USDA → наши. Слева — префикс описания категории в SR Legacy.
USDA_CATEGORIES = [
    ("Beef", "meat"), ("Pork", "meat"), ("Poultry", "meat"), ("Lamb", "meat"),
    ("Sausages", "meat"), ("Luncheon", "meat"), ("Game", "meat"), ("Veal", "meat"),
    ("Finfish", "fish"), ("Shellfish", "fish"),
    ("Dairy", "dairy"), ("Egg", "dairy"),
    ("Legumes", "legumes"),
    ("Cereal", "grains"), ("Baked", "grains"), ("Pasta", "grains"), ("Grain", "grains"),
    ("Vegetables", "produce"), ("Fruits", "produce"),
    ("Nut and Seed", "fats"), ("Fats and Oils", "fats"),
    ("Sweets", "sweets"), ("Snacks", "sweets"),
    ("Beverages", "drinks"),
]

# Строки, по которым продукт выкидывается целиком: это не еда, которую
# заносят в дневник, а справочные позиции и институциональные рационы.
SKIP = re.compile(
    r"babyfood|infant formula|school lunch|usda commodity|puerto rican|"
    r"formulated bar|meal replacement, |restaurant, |fast foods, .*, from",
    re.IGNORECASE)


def stable_id(name):
    """Идентификатор курируемой позиции — от английского названия, а не от
    номера строки: иначе вставка продукта в середину файла перенумеровала бы
    всё, что ниже, и продукты поменялись бы местами у уже установленного
    приложения. Диапазон 1_000_000+ не пересекается с идентификаторами USDA."""
    return 1_000_000 + zlib.crc32(name.encode("utf-8")) % 1_000_000


# Продукты, у которых калории берутся не только из белков, жиров и углеводов.
# Этиловый спирт даёт 7 ккал на грамм и макросом не является, поэтому у вина
# и водки сверка по 4/9/4 не работает в принципе — это не повод править числа.
# Квас здесь же: в нём около процента спирта — немного, но достаточно,
# чтобы расчёт по макросам не сходился.
ALCOHOL = {"Beer", "Dry red wine", "Dry white wine", "Vodka", "Whiskey", "Kvass"}


def check_macros(name, en, kcal, p, f, c):
    """Сверяет калорийность с макросами: 4/9/4 — грубое приближение, но
    опечатку в разряде оно ловит железно. Это калорийный дневник, и неверное
    число здесь дороже любой другой ошибки.

    Допуск несимметричный намеренно. Вниз — до 0.65: клетчатка входит в
    углеводы, а даёт заметно меньше четырёх килокалорий, поэтому у отрубей и
    цитрусовых настоящая калорийность честно ниже расчётной. Вверх — до 1.2:
    там взяться лишним калориям, кроме опечатки, неоткуда."""
    if en in ALCOHOL:
        return None
    predicted = 4 * p + 9 * f + 4 * c
    if kcal < 25 and predicted < 25:
        return None
    if predicted == 0:
        return f"{name}: {kcal} ккал при нулевых макросах"
    ratio = kcal / predicted
    if not 0.65 <= ratio <= 1.2:
        return (f"{name}: {kcal} ккал против {predicted:.0f} по макросам "
                f"({ratio:.2f}×)")
    return None


def read_core():
    foods, problems, seen = [], [], {}
    with open(CORE, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("|")
            if len(parts) != 8:
                problems.append(f"строка {number}: полей {len(parts)}, а нужно 8")
                continue
            ru, en, kcal, p, f, c, category, grams = (x.strip() for x in parts)
            if category not in CATEGORIES:
                problems.append(f"строка {number}: неизвестная категория {category!r}")
                continue
            try:
                kcal, p, f, c = int(kcal), float(p), float(f), float(c)
            except ValueError:
                problems.append(f"строка {number}: числа не разобрались")
                continue
            complaint = check_macros(ru, en, kcal, p, f, c)
            if complaint:
                problems.append(f"строка {number}: {complaint}")
            if en in seen:
                problems.append(f"строка {number}: {en!r} уже был в строке {seen[en]}")
                continue
            seen[en] = number
            food = {"i": stable_id(en), "ru": ru, "en": en, "k": kcal,
                    "p": p, "f": f, "c": c, "cat": category}
            if grams:
                food["g"] = float(grams)
            foods.append(food)
    return foods, problems


def usda_category(description):
    for prefix, ours in USDA_CATEGORIES:
        if description.startswith(prefix):
            return ours
    return "other"


def translate(description, terms):
    """Переводит название USDA по словарю. USDA пишет названия из частей через
    запятую — «Beef, ground, raw», — поэтому переводится словарь частей, а не
    две тысячи названий целиком. Если хоть одна часть незнакома, возвращаем
    None: лучше честное английское название, чем наполовину русское."""
    pieces = []
    for piece in description.split(","):
        key = piece.strip().lower()
        if not key:
            continue
        if key not in terms:
            return None
        pieces.append(terms[key])
    if not pieces:
        return None
    head = pieces[0]
    return ", ".join([head[0].upper() + head[1:]] + pieces[1:])


def read_usda(path, terms, limit, taken_names):
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
    rows = payload.get("SRLegacyFoods", payload if isinstance(payload, list) else [])

    candidates = []
    for row in rows:
        description = (row.get("description") or "").strip()
        if not description or SKIP.search(description):
            continue
        amounts = {}
        for entry in row.get("foodNutrients", []):
            nutrient = entry.get("nutrient") or {}
            amount = entry.get("amount")
            if amount is not None:
                amounts[nutrient.get("id")] = amount
        if ENERGY not in amounts or PROTEIN not in amounts:
            continue
        if FAT not in amounts or CARBS not in amounts:
            continue
        if FoodNameKey(description) in taken_names:
            continue
        # Чем меньше уточнений через запятую, тем более общий продукт.
        # «Cheese, cheddar» человек ищет, «Cheese, cheddar, reduced fat,
        # shredded, prepackaged» — почти никогда.
        commonness = (description.count(","), len(description))
        candidates.append((commonness, description, row, amounts))

    candidates.sort(key=lambda item: item[0])

    foods = []
    for _, description, row, amounts in candidates[:limit]:
        micro = {}
        for usda_id, key in MICRO.items():
            if usda_id in amounts:
                micro[key] = round(amounts[usda_id], 3)
        food = {
            "i": int(row["fdcId"]),
            "en": description,
            "k": int(round(amounts[ENERGY])),
            "p": round(amounts[PROTEIN], 2),
            "f": round(amounts[FAT], 2),
            "c": round(amounts[CARBS], 2),
            "cat": usda_category((row.get("foodCategory") or {}).get("description", "")),
        }
        russian = translate(description, terms)
        if russian:
            food["ru"] = russian
        if micro:
            food["m"] = micro
        foods.append(food)
    return foods


def FoodNameKey(name):
    return re.sub(r"[^a-z0-9]+", " ", name.lower()).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--usda", help="путь к JSON-выгрузке USDA SR Legacy")
    parser.add_argument("--limit", type=int, default=2000,
                        help="сколько позиций в каталоге всего (по умолчанию 2000)")
    parser.add_argument("--out", default=OUT)
    parser.add_argument("--check", action="store_true",
                        help="только проверить исходные файлы, ничего не писать")
    args = parser.parse_args()

    core, problems = read_core()
    if problems:
        print("Проблемы в Tools/food_core.txt:", file=sys.stderr)
        for problem in problems:
            print("  •", problem, file=sys.stderr)
        if args.check:
            return 1

    foods = list(core)
    if args.usda:
        with open(TERMS, encoding="utf-8") as handle:
            # Ключи с подчёркиванием — пояснения для человека, а не термины.
            terms = {k: v for k, v in json.load(handle).items()
                     if not k.startswith("_")}
        taken = {FoodNameKey(item["en"]) for item in core}
        room = max(0, args.limit - len(core))
        added = read_usda(args.usda, terms, room, taken)
        foods.extend(added)
        translated = sum(1 for item in added if "ru" in item)
        print(f"USDA: добавлено {len(added)}, из них с русским названием {translated}")

    identifiers = [item["i"] for item in foods]
    duplicates = len(identifiers) - len(set(identifiers))
    if duplicates:
        print(f"ОШИБКА: совпало идентификаторов: {duplicates}", file=sys.stderr)
        return 1

    if args.check:
        print(f"Проверено позиций: {len(foods)}, проблем: {len(problems)}")
        return 0

    foods.sort(key=lambda item: item["i"])
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(foods, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
    size = os.path.getsize(args.out)
    print(f"Записано {len(foods)} позиций в {os.path.relpath(args.out, ROOT)} "
          f"({size / 1024:.0f} КБ)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
