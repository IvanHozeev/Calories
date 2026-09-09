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
LINKS = os.path.join(ROOT, "Tools", "food_core_usda.tsv")
RECIPES = os.path.join(ROOT, "Tools", "dish_recipes.txt")

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

# Категории, которых в дневнике быть не должно. «Коренные народы Аляски» — это
# лось, морж и морской огурец: прекрасные данные, но не еда этого приложения.
JUNK_CATEGORIES = (
    "Baby Foods", "Fast Foods", "Restaurant Foods", "American Indian",
    "Meals, Entrees, and Side Dishes",
)

# Марки в SR Legacy пишутся заглавными или несут название фирмы. Человеку,
# который ищет «хлеб», «George Weston Bakeries, Thomas English Muffins»
# бесполезен — он только оттесняет вниз настоящий хлеб.
BRAND = re.compile(r"\b[A-Z]{3,}\b|Inc\.|Bakeries|Company|Brands|®|™")


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


def read_links():
    """Связь позиций ядра со строками USDA — её находит match_usda.py.
    Ради витаминов: свои калории и макросы у ядра есть, а микронутриенты
    взять неоткуда."""
    links = {}
    if not os.path.exists(LINKS):
        return links
    with open(LINKS, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#") or not line.strip():
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                links[parts[0]] = int(parts[1])
    return links


def load_usda(path):
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
    return payload.get("SRLegacyFoods", payload if isinstance(payload, list) else [])


def amounts_of(row):
    result = {}
    for entry in row.get("foodNutrients", []):
        nutrient = entry.get("nutrient") or {}
        amount = entry.get("amount")
        if amount is not None:
            result[nutrient.get("id")] = amount
    return result


def micro_of(amounts):
    return {key: round(amounts[usda_id], 3)
            for usda_id, key in MICRO.items() if usda_id in amounts}


def read_usda(rows, terms, limit, taken_names, taken_ids):

    candidates = []
    for row in rows:
        description = (row.get("description") or "").strip()
        if not description or SKIP.search(description) or BRAND.search(description):
            continue
        if (row.get("foodCategory") or {}).get("description", "").startswith(JUNK_CATEGORIES):
            continue
        # Строки, уже отданные ядру, второй раз не берём: иначе рядом с
        # «Куриная грудка варёная» встанет её же английский двойник.
        if int(row["fdcId"]) in taken_ids:
            continue
        amounts = amounts_of(row)
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
        micro = micro_of(amounts)
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


def read_recipes():
    """Рецепты готовых блюд: {название: [(ингредиент, граммы), ...]}."""
    recipes, problems = {}, []
    if not os.path.exists(RECIPES):
        return recipes, problems
    with open(RECIPES, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("|")
            if len(parts) < 2:
                problems.append(f"строка {number}: нет ни одного ингредиента")
                continue
            items = []
            for chunk in parts[1:]:
                name, _, grams = chunk.rpartition(":")
                try:
                    items.append((name.strip(), float(grams)))
                except ValueError:
                    problems.append(f"строка {number}: не разобрал {chunk!r}")
            recipes[parts[0].strip()] = items
    return recipes, problems


def apply_recipes(foods, recipes):
    """Считает блюдам состав по рецептам из продуктов того же каталога.

    Занижение честнее завышения: состав делится на полный вес блюда, а не на
    вес известной части. Иначе неизвестный ингредиент молча получил бы состав
    известных, и блюдо вышло бы богаче, чем оно есть. Доля известного веса
    пишется рядом полем `mc`, и приложение по ней решает, доверять ли числу.
    """
    by_ru = {item["ru"]: item for item in foods if item.get("ru")}
    problems, done = [], 0
    for dish_name, items in recipes.items():
        dish = by_ru.get(dish_name)
        if dish is None:
            problems.append(f"{dish_name!r}: такого блюда нет в ядре")
            continue
        total = sum(grams for _, grams in items)
        if not total:
            problems.append(f"{dish_name!r}: суммарный вес нулевой")
            continue
        if abs(total - 100) > 5:
            problems.append(f"{dish_name!r}: сумма граммов {total:.0f}, "
                            f"а рецепт пишется на сто грамм готового блюда")

        totals, known, kcal = {}, 0.0, 0.0
        for name, grams in items:
            source = by_ru.get(name)
            if source is None:
                problems.append(f"{dish_name!r}: нет ингредиента {name!r}")
                continue
            kcal += source["k"] * grams / 100
            # Вода честно весит и честно ничего не содержит: считать её
            # неизвестной значило бы занижать покрытие супа втрое.
            if source.get("m") or source["k"] == 0:
                known += grams
            for key, value in (source.get("m") or {}).items():
                totals[key] = totals.get(key, 0) + value * grams / 100

        # Калории по рецепту против курируемых: разошлись сильно — значит
        # рецепт описывает не то блюдо, и витамины из него будут не те.
        per100 = kcal * 100 / total
        if dish["k"] and abs(per100 - dish["k"]) / dish["k"] > 0.2:
            problems.append(f"{dish_name!r}: по рецепту {per100:.0f} ккал, "
                            f"в ядре {dish['k']} — расхождение больше пятой части")

        if not totals:
            continue
        dish["m"] = {key: round(value * 100 / total, 4) for key, value in totals.items()}
        coverage = known / total
        if coverage < 0.999:
            dish["mc"] = round(coverage, 3)
        done += 1
    return done, problems


def FoodNameKey(name):
    return re.sub(r"[^a-z0-9]+", " ", name.lower()).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--usda", help="путь к JSON-выгрузке USDA SR Legacy")
    parser.add_argument("--limit", type=int, default=2000,
                        help="сколько позиций в каталоге всего (по умолчанию 2000)")
    parser.add_argument("--core-only", action="store_true",
                        help="взять из USDA только микронутриенты для ядра, "
                             "не досыпая длинный хвост")
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
        rows = load_usda(args.usda)
        by_id = {int(r["fdcId"]): r for r in rows}

        # Сначала витамины в ядро: это главное, ради чего сюда ходят.
        links = read_links()
        linked = 0
        for item in foods:
            usda_id = links.get(item["en"])
            row = by_id.get(usda_id) if usda_id else None
            if row is None:
                continue
            micro = micro_of(amounts_of(row))
            if micro:
                item["m"] = micro
                linked += 1
        covered = len(foods) and linked * 100 // len(foods)
        print(f"Ядро: микронутриенты получили {linked} из {len(foods)} позиций ({covered}%)")

        # Блюда — после ядра: их состав считается из продуктов, которым
        # витамины только что проставили.
        recipes, recipe_problems = read_recipes()
        if recipes:
            done, more = apply_recipes(foods, recipes)
            problems.extend(recipe_problems + more)
            print(f"Блюда: состав посчитан по рецептам для {done} из {len(recipes)}")
            for problem in more + recipe_problems:
                print("  •", problem, file=sys.stderr)

        if args.core_only:
            print("Хвост не добавляем: в SR Legacy это справочник мясника — "
                  "восемьсот вариантов говядины и фазан, а не еда для дневника.")
            room = 0
        else:
            room = max(0, args.limit - len(core))
        taken = {FoodNameKey(item["en"]) for item in core}
        taken_ids = {links[item["en"]] for item in core if item["en"] in links}
        added = read_usda(rows, terms, room, taken, taken_ids) if room else []
        foods.extend(added)
        if added:
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
