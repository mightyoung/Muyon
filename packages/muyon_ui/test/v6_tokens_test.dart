import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

const lightPalette = {
  'canvas': 0xfffcfcfc,
  'surface': 0xffffffff,
  'sunken': 0xfff1f3f6,
  'rule': 0xffe2e6ec,
  'ruleStrong': 0xffc3cad6,
  'ink': 0xff111827,
  'ink2': 0xff4b5565,
  'ink3': 0xff636c7e,
  'accent': 0xff2458d3,
  'onAccent': 0xffffffff,
  'accentTint': 0xffe8efff,
  'accentDeep': 0xff1b47c2,
  'red': 0xffb8302a,
  'redBg': 0xfffde8e6,
  'green': 0xff17693f,
  'greenBg': 0xffe6f4ec,
  'warn': 0xff8a5a00,
  'warnBg': 0xfffff1d6,
};
const darkPalette = {
  'canvas': 0xff0a0a0a,
  'surface': 0xff141414,
  'sunken': 0xff1f1f1f,
  'rule': 0xff2b2b2b,
  'ruleStrong': 0xff3f3f3f,
  'ink': 0xfff2f2f2,
  'ink2': 0xffc4c4c4,
  'ink3': 0xff9a9a9a,
  'accent': 0xfff0a649,
  'onAccent': 0xff0a0a0a,
  'accentTint': 0xff3a2a12,
  'accentDeep': 0xfff5c27a,
  'red': 0xffff7a70,
  'redBg': 0xff3a1f1d,
  'green': 0xff4cc38a,
  'greenBg': 0xff17301f,
  'warn': 0xffe8c547,
  'warnBg': 0xff2e2a10,
};
double luminance(Color c) {
  double linear(double v) =>
      v <= .04045 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  return .2126 * linear(c.r) + .7152 * linear(c.g) + .0722 * linear(c.b);
}

double contrast(Color a, Color b) =>
    (math.max(luminance(a), luminance(b)) + .05) /
    (math.min(luminance(a), luminance(b)) + .05);
void main() {
  for (final brightness in Brightness.values) {
    test('$brightness matches literal v6 palette', () {
      final actual = MuyonTokens.forBrightness(brightness).colors;
      final expected = brightness == Brightness.dark
          ? darkPalette
          : lightPalette;
      for (final e in expected.entries) {
        expect(actual[e.key], Color(e.value), reason: e.key);
      }
      expect(actual['warn'], isNot(actual['accentDeep']));
    });
    test('$brightness all body pairs meet WCAG 4.5', () {
      final c = MuyonTokens.forBrightness(brightness).colors;
      for (final pair in [
        ('ink', 'canvas'),
        ('ink2', 'canvas'),
        ('ink3', 'canvas'),
        ('ink3', 'sunken'),
        ('onAccent', 'accent'),
        ('accent', 'canvas'),
        ('accentDeep', 'accentTint'),
        ('red', 'surface'),
        ('red', 'redBg'),
        ('green', 'surface'),
        ('green', 'greenBg'),
        ('warn', 'surface'),
        ('warn', 'warnBg'),
        ('warn', 'canvas'),
      ]) {
        expect(c[pair.$1], isNotNull, reason: pair.$1);
        expect(c[pair.$2], isNotNull, reason: pair.$2);
        expect(
          contrast(c[pair.$1]!, c[pair.$2]!),
          greaterThanOrEqualTo(4.5),
          reason: '$pair',
        );
      }
    });
  }
}
