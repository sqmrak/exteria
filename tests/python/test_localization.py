import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCALIZATION = ROOT / "resources" / "localization"
# one entry per line, as the old parser of ios 5 and 6 wants it: a stray quote or a missing semicolon drops the whole file there and every text becomes its key
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)";$')
PLACEHOLDER = re.compile(r'%(?:\d+\$)?[-+#0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|j|t)?([@dDuUxXoOfeEgGcCsSpaAF%])')


def read(path):
    entries = []
    problems = []
    in_comment = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        text = line.strip()
        if in_comment:
            in_comment = "*/" not in text
            continue
        if not text or text.startswith("//"):
            continue
        if text.startswith("/*"):
            in_comment = "*/" not in text
            continue
        match = ENTRY.match(text)
        if not match:
            problems.append("%s:%d: not a key = value; line" % (path.parent.name, number))
            continue
        entries.append((match.group(1), match.group(2), number))
    return entries, problems


def placeholders(value):
    return sorted(kind for kind in PLACEHOLDER.findall(value) if kind != "%")


class LocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.languages = {}
        cls.problems = []
        for folder in sorted(LOCALIZATION.glob("*.lproj")):
            entries, problems = read(folder / "Localizable.strings")
            cls.problems += problems
            cls.languages[folder.name] = entries

    def test_the_bundle_has_english_and_the_languages_of_the_picker(self):
        self.assertTrue({"en.lproj", "ru.lproj", "sqmrak.lproj"} <= set(self.languages))

    def test_every_line_parses(self):
        self.assertEqual(self.problems, [])

    def test_no_key_is_given_twice(self):
        for name, entries in self.languages.items():
            seen = {}
            for key, _, number in entries:
                with self.subTest(language=name, key=key):
                    self.assertNotIn(key, seen, "%s:%d repeats line %d" % (name, number, seen.get(key, 0)))
                seen[key] = number

    def test_every_language_has_the_keys_of_english(self):
        english = {key for key, _, _ in self.languages["en.lproj"]}
        for name, entries in self.languages.items():
            keys = {key for key, _, _ in entries}
            with self.subTest(language=name):
                # a language may have more keys than English: Russian has the plural forms English does not
                self.assertEqual(sorted(english - keys), [], "keys missing from %s" % name)

    def test_placeholders_match_english(self):
        english = {key: value for key, value, _ in self.languages["en.lproj"]}
        for name, entries in self.languages.items():
            for key, value, number in entries:
                if key not in english:
                    continue
                with self.subTest(language=name, key=key):
                    self.assertEqual(placeholders(value), placeholders(english[key]), "%s:%d" % (name, number))

    def test_no_text_is_empty(self):
        for name, entries in self.languages.items():
            for key, value, number in entries:
                with self.subTest(language=name, key=key):
                    self.assertTrue(value.strip() or key in {k for k, v, _ in self.languages["en.lproj"] if not v.strip()}, "%s:%d is empty" % (name, number))


if __name__ == "__main__":
    unittest.main()
