import unittest

import markupsafe


class MarkupSafeTest(unittest.TestCase):
    def test_escape(self):
        self.assertEqual(str(markupsafe.escape("<tag &>")), "&lt;tag &amp;&gt;")

    def test_speedups_module(self):
        self.assertEqual(markupsafe._escape_inner.__module__, "_markupsafe__speedups")


if __name__ == "__main__":
    unittest.main()
