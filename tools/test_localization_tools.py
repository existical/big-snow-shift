"""Offline regression checks for preserving attribution and translation markers."""
import json
import unittest

from check_localization import ROOT, flatten, protected_term_errors
from prepare_localization import PROTECTED_TERMS, protect_text, restore_text, validate_translation


class AttributionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.english = flatten(json.loads((ROOT / "localization" / "translations" / "en.json").read_text(encoding="utf-8")))

    def test_each_credited_name_must_be_preserved(self):
        self.assertFalse(protected_term_errors(self.english, PROTECTED_TERMS))
        for term in PROTECTED_TERMS["credits.description"]:
            with self.subTest(term=term):
                altered = dict(self.english)
                altered["credits.description"] = altered["credits.description"].replace(term, "translated-name")
                self.assertTrue(protected_term_errors(altered, PROTECTED_TERMS))
                with self.assertRaises(ValueError):
                    validate_translation("credits.description", self.english["credits.description"], altered["credits.description"])

    def test_generation_hides_and_restores_titles_and_variables(self):
        source = self.english["credits.description"] + " {{count}} / {{count}}"
        replacements = {}
        protected = protect_text("credits.description", source, replacements)
        for term in PROTECTED_TERMS["credits.description"]:
            self.assertNotIn(term, protected)
        self.assertNotIn("{{count}}", protected)
        self.assertEqual(restore_text(protected, replacements), source)
        # The external translator sometimes inserts spaces into numeric tokens.
        spaced = protected
        for token in replacements:
            spaced = spaced.replace(token, " ".join(token))
        self.assertEqual(restore_text(spaced, replacements), source)

    def test_lost_marker_or_token_is_rejected(self):
        with self.assertRaises(ValueError):
            validate_translation("hud.cleared", "{{percent}}% cleared", "Alles schoon")
        with self.assertRaises(ValueError):
            validate_translation("hud.time", "TIME", "987654321000123456789")

    def test_titles_are_not_a_global_ban_on_translating_greetings(self):
        # 'God jul!' is a valid Swedish Christmas greeting outside attribution.
        catalog = dict(self.english)
        catalog["result.wonTitle"] = "God jul!"
        self.assertFalse(protected_term_errors(catalog, PROTECTED_TERMS))


if __name__ == "__main__":
    unittest.main()
