#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Подбирает каждой позиции ядра строку из USDA SR Legacy.

Нужно ради микронутриентов: свои числа калорий и макросов у ядра есть, а витамины
и минералы взять неоткуда — их надо принести из USDA. Связь один раз находится
здесь и записывается в `Tools/food_core_usda.tsv`, дальше сборкой каталога
занимается build_food_catalog.py.

Совпадение ищется по названию **и** по числам. Одного названия мало: в USDA
десятки строк «Rice, white, ...», и отличаются они как раз тем, что нас волнует.
Числа же работают проверкой в обе стороны — заодно видно, где мои значения
разошлись с авторитетными.

    python3 Tools/match_usda.py --index <sr_index.json> [--report]
"""

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(ROOT, "Tools", "food_core.txt")
OUT = os.path.join(ROOT, "Tools", "food_core_usda.tsv")

# USDA пишет своими словами. Слева — как говорим мы, справа — как говорят они.
SYNONYMS = {
    "boiled": {"cooked", "boiled"},
    "fried": {"fried", "pan-fried"},
    "grilled": {"grilled", "broiled", "roasted"},
    "dry": {"dry", "dried", "uncooked"},
    "fresh": {"raw", "fresh"},
    "champignon": {"white", "agaricus", "mushrooms"},
    "mushrooms": {"mushrooms"},
    "porcini": {"mushrooms"},
    "shrimp": {"shrimp"},
    "cottage": {"cottage"},
    "hard": {"cheddar", "hard"},
    "loaf": {"bread"},
    "buckwheat": {"buckwheat"},
    "groats": {"groats"},
    "pollock": {"pollock", "pollack"},
    "prunes": {"plums", "prunes"},
    "sunflower": {"sunflower"},
    "peanut": {"peanut", "peanuts"},
    "walnuts": {"walnuts"},
    "chickpeas": {"chickpeas", "garbanzo"},
    "beetroot": {"beets"},
    "corn": {"corn"},
    "sweet": {"sweet"},
    "seeds": {"seeds", "kernels"},
    "juice": {"juice"},
    "skim": {"nonfat", "skim", "fat-free"},
}

# То, что в USDA называется иначе. Не синонимы отдельных слов, а замена всего
# названия целиком: искать «Kiwi» бесполезно, там это «Kiwifruit». Пусто здесь
# для лаваша, кваса, ряженки, брынзы, халвы и пельменей — их в SR Legacy нет
# вовсе, и придумывать им пару значило бы приписать чужие витамины.
ALIASES = {
    "Kiwi": "kiwifruit green raw",
    "Blackcurrant": "currants european black raw",
    "Fresh fig": "figs raw",
    "Cherry tomatoes": "tomatoes red ripe raw",
    "White cabbage": "cabbage raw",
    "Bell pepper": "peppers sweet red raw",
    "Flax seeds": "seeds flaxseed",
    "Cream 10%": "cream fluid light coffee",
    "Cream 33%": "cream fluid heavy whipping",
    "Processed cheese": "cheese pasteurized process american",
    "Fat-free cottage cheese": "cheese cottage nonfat uncreamed dry",
    "Cottage cheese 9%": "cheese cottage creamed large curd",
    "Milk 1.5%": "milk lowfat fluid 1% milkfat",
    "Black coffee": "beverages coffee brewed prepared tap water",
    "Shortbread": "cookies shortbread commercially prepared plain",
    "Donut": "doughnuts cake-type plain sugared",
    "Milkshake": "milk shakes thick vanilla",
    "Smoked sausage": "sausage polish pork",
    "Hake": "fish whiting mixed species raw",
    "Sea bream": "fish snapper mixed species raw",
}

# Слова, которые ничего не сообщают: они есть почти в каждом описании и только
# завышают совпадение.
NOISE = {"and", "or", "with", "without", "the", "of", "in", "all", "types", "raw"}


def tokens(text):
    return [t for t in re.split(r"[^a-z0-9%]+", text.lower()) if t and t not in NOISE]


# Категории USDA → наши. Без этого «Lemon» находится в спортивном напитке со
# вкусом лимона: слово есть, числа близкие, еда другая.
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


# USDA часто называет группой, а не продуктом: «Fish, cod, Atlantic, raw»,
# «Nuts, almonds», «Cheese, mozzarella». Для таких голов достаточно, чтобы наше
# слово нашлось дальше по описанию. «Juice» в этот список намеренно не входит:
# иначе «Apple» снова уедет в «Juice, apple, grape and pear blend».
GROUP_HEADS = {
    "fish", "crustacean", "mollusk", "nut", "seed", "cheese", "mushroom", "oil",
    "bean", "pea", "cereal", "snack", "candie", "candy", "soup", "sausage", "egg",
    "milk", "yogurt", "bread", "roll", "pasta", "rice", "spice", "vegetable",
    "fruit", "game", "beverage", "alcoholic", "syrup", "salad", "pork", "beef",
    "chicken", "turkey", "lamb", "veal", "cream", "butter", "margarine", "flour",
    "wheat", "corn", "oat", "barley", "millet", "potato", "tomato", "onion",
    "squash", "cabbage", "lettuce", "melon",
}

# Не еда для дневника, а институциональные и ресторанные позиции: они забивают
# выдачу и по числам иногда ближе, чем настоящий продукт.
JUNK_CATEGORIES = (
    "Baby Foods", "Fast Foods", "Restaurant Foods",
    "Meals, Entrees, and Side Dishes", "American Indian",
)


def ours(usda_category):
    for prefix, mine in USDA_CATEGORIES:
        if usda_category.startswith(prefix):
            return mine
    return "other"


def stem(word):
    """Грубая нормализация числа. «Blackberries» и «blackberry» обязаны сойтись:
    без этого главное слово не находится и ягоды уезжают в сок."""
    if len(word) > 4 and word.endswith("ies"):
        return word[:-3] + "y"
    if len(word) > 4 and word.endswith(("ches", "shes", "xes", "sses")):
        return word[:-2]
    if len(word) > 3 and word.endswith("s") and not word.endswith("ss"):
        return word[:-1]
    return word


def head_matches(core_tokens, description):
    """Наше слово должно стоять в голове описания — до первой запятой, где USDA
    называет сам продукт. Либо голова должна быть названием группы: тогда
    продукт назван дальше, и это нормально.

    Без этого правила «Apple» находится в «Juice, apple, grape and pear blend»:
    слово на месте, числа близкие, а еда другая."""
    head = {stem(t) for t in tokens(description.split(",")[0])}
    for t in core_tokens:
        variants = {stem(v) for v in SYNONYMS.get(t, {t})}
        if variants & head:
            return True
    return bool(head & GROUP_HEADS)


def name_score(core_tokens, description):
    """Доля слов нашего названия, найденных в описании USDA."""
    have = {stem(t) for t in tokens(description)}
    if not core_tokens:
        return 0.0
    hits = 0
    for t in core_tokens:
        variants = {stem(v) for v in SYNONYMS.get(t, {t})}
        if variants & have:
            hits += 1
    return hits / len(core_tokens)


def macro_distance(core, row):
    """Насколько разошлись числа. Нормируем, чтобы граммы жира и сотни калорий
    весили сопоставимо."""
    energy = abs(core["k"] - row["k"]) / max(core["k"], 40)
    return energy + (abs(core["p"] - row["p"]) + abs(core["f"] - row["f"])) / 25 \
        + abs(core["c"] - row["c"]) / 40


def read_core():
    items = []
    with open(CORE, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = [x.strip() for x in line.split("|")]
            if len(parts) != 8:
                continue
            items.append({"ru": parts[0], "en": parts[1], "k": int(parts[2]),
                          "p": float(parts[3]), "f": float(parts[4]),
                          "c": float(parts[5]), "cat": parts[6]})
    return items


def best_match(item, rows):
    core_tokens = tokens(ALIASES.get(item["en"], item["en"]))
    scored = []
    for row in rows:
        if row["cat"].startswith(JUNK_CATEGORIES):
            continue
        # Категорию используем не равенством, а запретом: у USDA сливочное масло
        # лежит в молочных, а у нас в жирах — равенство отсекло бы правильную
        # строку. А вот напиток вместо еды не годится никогда.
        if item["cat"] != "drinks" and row["cat"].startswith("Beverages"):
            continue
        if not head_matches(core_tokens, row["d"]):
            continue
        score = name_score(core_tokens, row["d"])
        if score < 0.6:
            continue
        scored.append((round(score, 2), macro_distance(item, row), row["d"].count(","), row))
    if not scored:
        return None, 0.0, None
    # Сперва полнота совпадения названия, затем числа, и только потом
    # обобщённость. Числа обязаны стоять раньше числа запятых: иначе у «Boiled
    # white rice» победит короткое «Rice, white, raw» — оно generic, но втрое
    # калорийнее варёного.
    scored.sort(key=lambda x: (-x[0], x[1], x[2]))
    score, distance, _, row = scored[0]
    return row, score, distance


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", required=True, help="сжатый индекс SR Legacy (JSON)")
    parser.add_argument("--report", action="store_true", help="показать таблицу для проверки глазами")
    parser.add_argument("--max-distance", type=float, default=0.6,
                        help="выше этого расхождения чисел совпадение не принимается")
    args = parser.parse_args()

    rows = json.load(open(args.index, encoding="utf-8"))
    core = read_core()

    matched, rejected, dishes = [], [], []
    for item in core:
        # Готовые блюда в USDA искать нечего: борща и сырников там нет.
        # Считать их провалом сопоставления — врать себе про покрытие.
        if item["cat"] == "dishes":
            dishes.append(item)
            continue
        row, score, distance = best_match(item, rows)
        if row is None or distance > args.max_distance:
            rejected.append((item, row, score, distance))
            continue
        matched.append((item, row, score, distance))

    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("# en\tfdcId\tusda_description\tname_score\tmacro_distance\n")
        for item, row, score, distance in matched:
            handle.write(f"{item['en']}\t{row['i']}\t{row['d']}\t{score:.2f}\t{distance:.2f}\n")

    with_micro = sum(1 for _, row, _, _ in matched if row["m"])
    lookable = len(core) - len(dishes)
    print(f"позиций ядра: {len(core)} (из них готовых блюд, которых в USDA нет: {len(dishes)})")
    print(f"искали среди: {lookable}")
    print(f"сопоставлено: {len(matched)} ({len(matched) * 100 // lookable}% от искомых), "
          f"из них с микронутриентами: {with_micro}")
    print(f"без пары: {len(rejected)}")

    if args.report:
        print("\n--- сомнительные и непарные ---")
        for item, row, score, distance in rejected:
            found = row["d"] if row else "—"
            print(f"  {item['ru'][:24]:24} | {item['en'][:28]:28} | {found[:52]:52} "
                  f"| имя {score:.2f} числа {distance if distance else 0:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
