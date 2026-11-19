import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/theme.dart';

void main() {
  test('serif falls back to the emoji font of each phone', () {
    final s = serif(18, 24, Palette.lamplight.ink);
    expect(s.fontFamilyFallback, ['Apple Color Emoji', 'Noto Color Emoji']);
  });
}
