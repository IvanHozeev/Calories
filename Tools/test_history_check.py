#!/usr/bin/env python3
"""Проверка history_check.py на искусственном дневнике с заложенными закономерностями.

    python3 Tools/test_history_check.py
"""
import os
import random
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(__file__))
import history_check as hc  # noqa: E402

TZ = ZoneInfo("Asia/Jerusalem")


def synthetic_csv(days=60, seed=7):
    """Обычный день ~2000 ккал. По пятницам вечером срыв в 21–22 часа.
    После «Творог» следующий приём через 5 часов, после «Печенье» через 2."""
    rng = random.Random(seed)
    rows = ["date,name,calories,protein_g,fat_g,carbs_g,grams"]
    start = datetime(2026, 8, 1, tzinfo=TZ)
    for i in range(days):
        day = start + timedelta(days=i)
        morning_food = "Творог" if i % 2 == 0 else "Печенье"
        t = day.replace(hour=8)
        rows.append(f"{t.astimezone(timezone.utc).isoformat()},{morning_food},400,0,0,0,")
        t += timedelta(hours=5 if morning_food == "Творог" else 2)
        rows.append(f"{t.astimezone(timezone.utc).isoformat()},Обед,{800 + rng.randint(-50, 50)},0,0,0,")
        t = day.replace(hour=19)
        rows.append(f"{t.astimezone(timezone.utc).isoformat()},Ужин,800,0,0,0,")
        if day.weekday() == 4:   # пятница
            t = day.replace(hour=21, minute=30)
            rows.append(f"{t.astimezone(timezone.utc).isoformat()},Пицца,1200,0,0,0,")
    f = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
    f.write("\n".join(rows))
    f.close()
    return f.name


class HistoryCheckTests(unittest.TestCase):
    def setUp(self):
        self.entries = hc.read(synthetic_csv(), TZ)

    def test_binge_hour_is_found(self):
        top_hour, extra = hc.binge_hours(self.entries)[0]
        self.assertEqual(top_hour, 21)
        self.assertGreater(extra, 1000)

    def test_fuller_food_ranks_first(self):
        names = [row[0] for row in hc.fullness(self.entries)]
        self.assertLess(names.index("творог"), names.index("печенье"))

    def test_friday_overshoots(self):
        rows = {wd: over for wd, _, over, _ in hc.weekday_overshoot(self.entries)}
        self.assertEqual(rows["Пт"], 1.0)
        self.assertEqual(rows["Пн"], 0.0)

    def test_short_history_says_so(self):
        short = hc.read(synthetic_csv(days=10), TZ)
        self.assertIn("мало", hc.report(short))
        self.assertEqual(hc.binge_hours(short), [])

    def test_report_runs(self):
        text = hc.report(self.entries)
        self.assertIn("Часы срывов", text)
        self.assertIn("21:00", text)


if __name__ == "__main__":
    unittest.main()
