import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("estimate_budget", Path(__file__).resolve().parents[1] / "scripts/estimate-budget.py")
budget = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(budget)


class BudgetTests(unittest.TestCase):
    def test_profile_fits_budget_without_credits(self):
        result = budget.estimate()
        self.assertEqual(result["operating_hours"], 161)
        self.assertLess(result["total_krw_with_vat"], 50000)

    def test_storage_remains_billable_when_stopped(self):
        short, long = budget.estimate(1), budget.estimate(23)
        for item in ("EBS gp3 30 GiB", "RDS gp3 20 GiB", "RDS master secret"):
            self.assertEqual(short["items_usd"][item], long["items_usd"][item])

    def test_always_on_exceeds_budget(self):
        self.assertGreater(budget.estimate(31, 24)["total_krw_with_vat"], 50000)
