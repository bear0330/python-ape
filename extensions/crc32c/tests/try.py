import unittest

import crc32c


class Crc32cTest(unittest.TestCase):
    def test_known_answer(self):
        self.assertEqual(crc32c.crc32c(b"123456789"), 0xE3069283)

    def test_builtin_module(self):
        self.assertEqual(crc32c.crc32c.__module__, "_crc32c")


if __name__ == "__main__":
    unittest.main()
