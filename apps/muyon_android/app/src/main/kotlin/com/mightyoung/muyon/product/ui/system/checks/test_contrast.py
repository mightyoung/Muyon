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


class MaterialRoleRegressionTest(unittest.TestCase):
    # Used by native workflow chips, research panels and Material fallback widgets.
    pairs = {
        'primary': 'onPrimary', 'primaryContainer': 'onPrimaryContainer',
        'secondary': 'onSecondary', 'secondaryContainer': 'onSecondaryContainer',
        'tertiary': 'onTertiary', 'tertiaryContainer': 'onTertiaryContainer',
        'background': 'onBackground', 'surface': 'onSurface',
        'surfaceVariant': 'onSurfaceVariant', 'inverseSurface': 'inverseOnSurface',
        'error': 'onError', 'errorContainer': 'onErrorContainer',
    }
    surfaces = ('surfaceDim', 'surfaceBright', 'surfaceContainerLowest',
                'surfaceContainerLow', 'surfaceContainer', 'surfaceContainerHigh',
                'surfaceContainerHighest')

    def test_material_fallback_roles_are_explicit_neutral_and_contrasting(self):
        source = SOURCE.read_text()
        block = re.search(r'colorScheme = scheme.copy\((.*?)\n            \)', source, re.S).group(1)
        mappings = dict(re.findall(r'(\w+) = (p\.\w+|Color.Transparent|FoundationTokens.light.text)', block))
        expected = set(self.pairs) | set(self.pairs.values()) | set(self.surfaces) | {
            'inversePrimary', 'outline', 'outlineVariant', 'surfaceTint', 'scrim'}
        self.assertFalse(expected - mappings.keys(), f'Unmapped Material roles: {sorted(expected - mappings.keys())}')
        neutral = {'p.background', 'p.panel', 'p.text', 'p.secondary', 'p.border', 'p.action', 'p.onAction'}
        for role in expected - {'error', 'onError', 'errorContainer', 'onErrorContainer', 'surfaceTint', 'scrim'}:
            self.assertIn(mappings[role], neutral, role)
        self.assertEqual(mappings['surfaceTint'], 'Color.Transparent')
        self.assertEqual(mappings['scrim'], 'FoundationTokens.light.text')
        for mode in ('light', 'dark'):
            palette_block = re.search(r'val ' + mode + r' = FoundationPalette\((.*?)\n    \)', source, re.S).group(1)
            palette = {name: int(value, 16) for name, value in re.findall(r'(\w+) = Color\(0xFF([0-9A-Fa-f]{6})\)', palette_block)}
            colors = {role: palette[token[2:]] for role, token in mappings.items() if token.startswith('p.')}
            for background, foreground in self.pairs.items():
                with self.subTest(mode=mode, pair=(foreground, background)):
                    self.assertGreaterEqual(contrast(colors[foreground], colors[background]), 4.5)
            for background in self.surfaces:
                self.assertIn(mappings[background], {'p.background', 'p.panel'})
                self.assertGreaterEqual(contrast(colors['onSurface'], colors[background]), 4.5)
                self.assertGreaterEqual(contrast(colors['outline'], colors[background]), 3)
            self.assertGreaterEqual(contrast(colors['inversePrimary'], colors['inverseSurface']), 4.5)


if __name__ == '__main__':
    unittest.main()
