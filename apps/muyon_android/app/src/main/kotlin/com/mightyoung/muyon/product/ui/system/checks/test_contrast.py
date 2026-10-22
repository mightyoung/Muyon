"""Evaluate actual palette literals, not a separate copy of the colors."""
from pathlib import Path
import re
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'FoundationTokens.kt'


def luminance(rgb):
    channels = [(rgb >> shift & 255) / 255 for shift in (16, 8, 0)]
    linear = [c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in channels]
    return sum(c * w for c, w in zip(linear, (.2126, .7152, .0722)))


def contrast(a, b):
    x, y = sorted((luminance(a), luminance(b)))
    return (y + .05) / (x + .05)


class PaletteContrastTest(unittest.TestCase):
    def test_actual_light_and_dark_palette_have_accessible_text_and_boundaries(self):
        self.assertTrue(SOURCE.exists(), 'Foundation palette has not been implemented')
        source = SOURCE.read_text()
        for mode in ('light', 'dark'):
            block = re.search(r'val ' + mode + r' = FoundationPalette\((.*?)\n    \)', source, re.S).group(1)
            palette = {name: int(value, 16) for name, value in re.findall(r'(\w+) = Color\(0xFF([0-9A-Fa-f]{6})\)', block)}
            self.assertEqual(len(palette), 10)
            for background in ('background', 'panel'):
                for foreground in ('text', 'secondary', 'link', 'error'):
                    with self.subTest(mode=mode, pair=(foreground, background)):
                        self.assertGreaterEqual(contrast(palette[foreground], palette[background]), 4.5)
                self.assertGreaterEqual(contrast(palette['border'], palette[background]), 3)
            self.assertGreaterEqual(contrast(palette['onAction'], palette['action']), 4.5)
            self.assertNotIn(palette['background'], (0xFFFFFF, 0x000000))
            self.assertNotIn(palette['panel'], (0xFFFFFF, 0x000000))


if __name__ == '__main__':
    unittest.main()
