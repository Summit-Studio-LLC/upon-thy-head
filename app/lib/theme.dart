import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A palette: 60 night, 30 page, 10 light. Lamplight is the chosen default;
/// Vigil is kept as the alternate.
class Palette {
  const Palette({
    required this.ground,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.light,
    required this.danger,
    required this.sky,
    required this.tint,
    required this.orb,
    required this.lights,
  });

  final Color ground, surface, raised, ink, ink2, ink3, light;

  /// For words that throw something away (the prototype's --e3).
  final Color danger;

  /// Base sky colour in linear light, and the tint applied to the Milky Way.
  final List<double> sky, tint;

  /// Three colours each for the recording glow and for a blessing's light.
  final List<List<double>> orb, lights;

  static const lamplight = Palette(
    ground: Color(0xFF0B0907),
    surface: Color(0xFF13100C),
    raised: Color(0xFF1D1913),
    ink: Color(0xFFEFE6D4),
    ink2: Color(0xFFB5AB98),
    ink3: Color(0xFF8A806E),
    light: Color(0xFFF0C987),
    danger: Color(0xFFEC8672),
    sky: [.0030, .0021, .0013],
    tint: [1.07, .98, .85],
    orb: [
      [1, .94, .82],
      [1, .77, .46],
      [.98, .56, .28],
    ],
    lights: [
      [1, .97, .90],
      [1, .80, .50],
      [1, .66, .36],
    ],
  );

  static const vigil = Palette(
    ground: Color(0xFF070A12),
    surface: Color(0xFF0C101A),
    raised: Color(0xFF141927),
    ink: Color(0xFFEEE7D8),
    ink2: Color(0xFFA9ADBB),
    ink3: Color(0xFF7D8297),
    light: Color(0xFFF3D9A4),
    danger: Color(0xFFEE8E7C),
    sky: [.0011, .0016, .0034],
    tint: [1, 1, 1],
    orb: [
      [1, .95, .85],
      [1, .8, .52],
      [.98, .6, .33],
    ],
    lights: [
      [1, .975, .93],
      [1, .83, .57],
      [1, .72, .42],
    ],
  );
}

const _serif = 'Newsreader';

/// Newsreader with its optical size following the text size, as browsers do.
TextStyle serif(double size, double height, Color color, {bool italic = false, double tracking = 0}) => TextStyle(
      fontFamily: _serif,
      fontSize: size,
      height: height / size,
      color: color,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: tracking * size,
      fontVariations: [const FontVariation('wght', 400), FontVariation('opsz', size.clamp(6, 72))],
      decoration: TextDecoration.none,
    );

/// San Francisco on Apple platforms; the platform default elsewhere.
String? get _systemFamily => switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'CupertinoSystemText',
      _ => null,
    };

/// The system face.
TextStyle sans(double size, double height, Color color, {FontWeight weight = FontWeight.w400, double tracking = 0}) =>
    TextStyle(
      fontFamily: _systemFamily,
      fontSize: size,
      height: height / size,
      color: color,
      fontWeight: weight,
      letterSpacing: tracking * size,
      decoration: TextDecoration.none,
    );

const Curve easeOut = Cubic(.22, 1, .36, 1);
