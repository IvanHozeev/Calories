#!/usr/bin/env python3
"""Проверка идей на истории дневника (этап 4 плана от 12.11).

Идеи из `Docs/ideas-and-ui-2026-11-11.md` предполагают закономерности, которых
может не быть. Прежде чем строить под них экраны, скрипт считает на настоящем
дневнике, есть ли они:

1. Часы срывов: в какие часы набираются лишние калории в дни перебора.
2. Что держит дольше: после каких продуктов следующий приём наступает позже.
3. Перебор по дням недели: есть ли день, в который он случается заметно чаще.

Связь «короткая ночь → больше еды» здесь не проверяется: сна в CSV нет.

Вход — CSV из приложения (Настройки → «Дневник таблицей (CSV)»). Это личные
данные: файл кладётся вне репозитория, и в репозиторий не попадает ни он, ни
отчёт.

    python3 Tools/history_check.py ~/Documents/diary.csv --tz Asia/Jerusalem
"""
from __future__ import annotations

import argparse
import csv
import statistics
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

# Записи ближе этого друг к другу — один приём пищи.
MEAL_GAP = timedelta(minutes=30)
# Дальше этого следующий приём уже не про сытость: ночь, пропущенный день.
MAX_GAP_HOURS = 10.0
# Перебор — день выше личной медианы на эту долю.
OVER_SHARE = 0.25
# Меньше этого — не закономерность, а случай.
MIN_DAYS = 21
MIN_FOOD_MEALS = 5


@dataclass
class Entry:
    at: datetime
    name: str
    calories: int


def read(path: str, tz: ZoneInfo) -> list[Entry]:
    entries = []
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            at = datetime.fromisoformat(row["date"].replace("Z", "+00:00")).astimezone(tz)
            entries.append(Entry(at, row["name"].strip(), int(float(row["calories"] or 0))))
    return sorted(entries, key=lambda e: e.at)


def day_totals(entries: list[Entry]) -> dict:
    totals = defaultdict(int)
    for e in entries:
        totals[e.at.date()] += e.calories
    return totals


def meals(entries: list[Entry]) -> list[list[Entry]]:
    """Записи, разделённые меньше чем MEAL_GAP, — один приём."""
    result: list[list[Entry]] = []
    for e in entries:
        if result and e.at - result[-1][-1].at <= MEAL_GAP:
            result[-1].append(e)
        else:
            result.append([e])
    return result


def binge_hours(entries: list[Entry]) -> list[tuple[int, float]]:
    """Сколько калорий в среднем на час суток в дни перебора сверх обычных дней."""
    totals = day_totals(entries)
    if len(totals) < MIN_DAYS:
        return []
    median = statistics.median(totals.values())
    over_days = {d for d, t in totals.items() if t > median * (1 + OVER_SHARE)}
    normal_days = set(totals) - over_days
    if not over_days or not normal_days:
        return []
    by_hour = {True: defaultdict(int), False: defaultdict(int)}
    for e in entries:
        by_hour[e.at.date() in over_days][e.at.hour] += e.calories
    extra = []
    for hour in range(24):
        over = by_hour[True][hour] / len(over_days)
        normal = by_hour[False][hour] / len(normal_days)
        extra.append((hour, over - normal))
    return sorted(extra, key=lambda x: -x[1])


def fullness(entries: list[Entry]) -> list[tuple[str, float, int]]:
    """Медиана часов до следующего приёма после приёмов с этим продуктом."""
    all_meals = meals(entries)
    gaps = defaultdict(list)
    for meal, following in zip(all_meals, all_meals[1:]):
        hours = (following[0].at - meal[-1].at).total_seconds() / 3600
        if hours > MAX_GAP_HOURS or meal[-1].at.date() != following[0].at.date():
            continue
        for name in {e.name.lower() for e in meal}:
            gaps[name].append(hours)
    rows = [(name, statistics.median(h), len(h)) for name, h in gaps.items() if len(h) >= MIN_FOOD_MEALS]
    return sorted(rows, key=lambda r: -r[1])


WEEKDAYS = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]


def weekday_overshoot(entries: list[Entry]) -> list[tuple[str, float, float, int]]:
    """По дням недели: средние калории, доля дней с перебором и число дней."""
    totals = day_totals(entries)
    if len(totals) < MIN_DAYS:
        return []
    median = statistics.median(totals.values())
    by_day = defaultdict(list)
    for d, t in totals.items():
        by_day[d.weekday()].append(t)
    rows = []
    for wd in range(7):
        values = by_day.get(wd, [])
        if not values:
            continue
        over = sum(t > median * (1 + OVER_SHARE) for t in values) / len(values)
        rows.append((WEEKDAYS[wd], statistics.mean(values), over, len(values)))
    return rows


def report(entries: list[Entry]) -> str:
    totals = day_totals(entries)
    lines = [f"Дней с записями: {len(totals)}, записей: {len(entries)}."]
    if len(totals) < MIN_DAYS:
        lines.append(f"Меньше {MIN_DAYS} дней — для выводов мало.")
        return "\n".join(lines)
    lines.append(f"Медиана дня: {statistics.median(totals.values()):.0f} ккал; "
                 f"перебор — выше на {OVER_SHARE:.0%}.")

    lines.append("\n## 1. Часы срывов (лишние ккал в дни перебора, сверх обычных)")
    top = [h for h in binge_hours(entries) if h[1] > 0][:4]
    lines += [f"- {h:02d}:00–{h:02d}:59: +{extra:.0f} ккал" for h, extra in top] or ["- закономерности нет"]

    lines.append("\n## 2. Что держит дольше (медиана часов до следующего приёма)")
    rows = fullness(entries)
    if rows:
        lines += [f"- {name}: {hours:.1f} ч ({n} раз)" for name, hours, n in rows[:5]]
        lines.append("  …и меньше всего:")
        lines += [f"- {name}: {hours:.1f} ч ({n} раз)" for name, hours, n in rows[-3:]]
    else:
        lines.append(f"- продуктов, съеденных хотя бы {MIN_FOOD_MEALS} раз, мало")

    lines.append("\n## 3. Перебор по дням недели")
    lines += [f"- {wd}: в среднем {mean:.0f} ккал, перебор в {over:.0%} дней ({n})"
              for wd, mean, over, n in weekday_overshoot(entries)]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("csv")
    parser.add_argument("--tz", default="Asia/Jerusalem")
    args = parser.parse_args()
    print(report(read(args.csv, ZoneInfo(args.tz))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
