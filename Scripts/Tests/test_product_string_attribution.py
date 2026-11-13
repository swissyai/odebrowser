import importlib.util
from pathlib import Path
import unittest


class ProductStringAttributionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[2] / "tools/dev/rename-product-strings.py"
        spec = importlib.util.spec_from_file_location("product_strings", path)
        cls.product_strings = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.product_strings)

    def test_required_attribution_survives_product_renaming(self):
        for credit in self.product_strings.ATTRIBUTION:
            self.assertEqual(self.product_strings.rename(credit), credit)

    def test_attribution_exception_cannot_hide_other_product_strings(self):
        for credit in self.product_strings.ATTRIBUTION:
            combined = credit + " Open Crest settings."
            self.assertNotIn("Open Crest settings", self.product_strings.rename(combined))
        self.assertEqual(self.product_strings.rename("Open Crest settings"), "Open Ode settings")
