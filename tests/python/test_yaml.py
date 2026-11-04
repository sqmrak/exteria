import datetime
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "python", "shim"))

import yaml  # noqa: E402


class SafeLoad(unittest.TestCase):
    def test_reads_the_metainfo_of_a_compiled_plugin(self):
        text = (
            "name: reSwaga\n"
            "description: '{description}'\n"
            "id: meeow_reswaga\n"
            "version: 2.0.2\n"
            "author: '@meeownnews'\n"
            "app_version: '>=12.9.0'\n"
            "compiled: true\n"
            "buildNum: 36\n"
            "buildDate: 2026-09-27\n"
            "pythonVer: 3.11\n"
            "sourceHash: f5f9b60d\n"
            "category:\n"
            "- media\n"
            "- integrations\n"
        )
        self.assertEqual(yaml.safe_load(text), {
            "name": "reSwaga", "description": "{description}", "id": "meeow_reswaga", "version": "2.0.2",
            "author": "@meeownnews", "app_version": ">=12.9.0", "compiled": True, "buildNum": 36,
            "buildDate": datetime.date(2026, 9, 27), "pythonVer": 3.11, "sourceHash": "f5f9b60d",
            "category": ["media", "integrations"]})

    def test_reads_escapes_in_double_quotes(self):
        text = 'description: "\\u0430\\u0443\\u0434\\u0438\\u043e \\"q\\" \\n"\nicon: MeijiPlugins/4\n'
        self.assertEqual(yaml.safe_load(text), {"description": "аудио \"q\" \n", "icon": "MeijiPlugins/4"})

    def test_reads_a_refmap(self):
        text = "metainfo: reSwaga/meta.yml\nmain: reSwaga/src/main.py\nassets: reSwaga/res\n"
        self.assertEqual(yaml.safe_load(text)["main"], "reSwaga/src/main.py")

    def test_reads_nested_blocks_and_comments(self):
        text = (
            "# head\n"
            "a:\n"
            "  b: 1  # tail\n"
            "  c:\n"
            "    - x\n"
            "    - y: 2\n"
            "      z: [1, 'two', {k: v}]\n"
            "d:\n"
            "- 1\n"
            "- ~\n"
            "e: 'it''s'\n"
            "f: a # b\n"
            "g: http://x.y/#frag\n"
        )
        self.assertEqual(yaml.safe_load(text), {
            "a": {"b": 1, "c": ["x", {"y": 2, "z": [1, "two", {"k": "v"}]}]},
            "d": [1, None], "e": "it's", "f": "a", "g": "http://x.y/#frag"})

    def test_reads_block_scalars(self):
        text = "a: |\n  one\n  two\n\nb: >-\n  one\n  two\n\n  three\nc: end\n"
        self.assertEqual(yaml.safe_load(text), {"a": "one\ntwo\n", "b": "one two\nthree", "c": "end"})

    def test_empty_document_is_none(self):
        self.assertIsNone(yaml.safe_load(""))
        self.assertIsNone(yaml.safe_load("# only a comment\n"))

    def test_refuses_what_it_cannot_read(self):
        for text in ("a: &x 1\nb: *x\n", "a: !!str 1\n", "<<: {a: 1}\n", "a: 1\na: 2\n", "a: 1\n---\nb: 2\n",
                     "a: b\n  c\n", "a: [1, 2\n", 'a: "open\n', "a:\n\tb: 1\n", "a: 1\n b: 2\n"):
            with self.subTest(text=text):
                with self.assertRaises(yaml.YAMLError):
                    yaml.safe_load(text)


if __name__ == "__main__":
    unittest.main()
