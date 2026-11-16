import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'astro.dart';

/// A star bright enough to carry its name on the sky.
class NamedStar {
  const NamedStar(this.name, this.v, this.mag);
  final String name;
  final Vec3 v;
  final double mag;
}

/// The stars, brightest first, with everything that does not change from frame
/// to frame worked out once. Source: HYG database (CC BY-SA), 110,324 stars to
/// magnitude 10.2, packed 6 bytes each (ra u16, dec i16, magnitude u8, B-V u8).
class StarCatalogue {
  StarCatalogue._(this.count, this.xyz, this.rad, this.alpha, this.halo, this.twFreq, this.twPhase, this.rgb, this.named);

  final int count;

  /// Unit vectors, three floats per star.
  final Float32List xyz;

  /// Apparent radius factor and brightness at full exposure, both falling with magnitude.
  final Float32List rad, alpha;

  /// 0 for most stars; rises to 1 for the very brightest, which get a soft halo.
  final Float32List halo;

  /// Each star twinkles at its own rate and phase.
  final Float32List twFreq, twPhase;

  /// Colour from the star's B-V index, 0xRRGGBB.
  final Int32List rgb;

  final List<NamedStar> named;

  static Future<StarCatalogue> load() async {
    final data = await rootBundle.load('assets/sky/stars.bin');
    final n = data.lengthInBytes ~/ 6;
    final xyz = Float32List(n * 3);
    final rad = Float32List(n), alpha = Float32List(n), halo = Float32List(n);
    final twFreq = Float32List(n), twPhase = Float32List(n);
    final rgb = Int32List(n);
    for (var i = 0; i < n; i++) {
      final o = i * 6;
      final ra = data.getUint16(o, Endian.little) / 65536 * tau;
      final dec = data.getInt16(o + 2, Endian.little) / 32767 * math.pi / 2;
      final mag = data.getUint8(o + 4) / 20 - 2;
      final bv = data.getUint8(o + 5) / 100 - .5;
      final x = math.cos(dec) * math.cos(ra), y = math.cos(dec) * math.sin(ra), z = math.sin(dec);
      xyz[i * 3] = x;
      xyz[i * 3 + 1] = y;
      xyz[i * 3 + 2] = z;
      final lum = math.pow(10, .4 * (6 - mag)).toDouble();
      rad[i] = .30 + .16 * math.pow(lum, .30);
      alpha[i] = .66 * math.pow(lum, .6);
      halo[i] = ((lum - 5) / 110).clamp(0, 1);
      final f = mag * 7.31;
      twFreq[i] = 1.3 + (f - f.floorToDouble()) * 2.6;
      twPhase[i] = x * 311 + y * 173;
      rgb[i] = _bvColor(bv);
    }
    final raw = jsonDecode(await rootBundle.loadString('assets/sky/named.json')) as List;
    final named = <NamedStar>[
      for (final s in raw)
        if ((s[3] as num) < 1.7)
          NamedStar(s[0] as String, Vec3.radec((s[1] as num) / 24 * tau, (s[2] as num) * deg), (s[3] as num).toDouble()),
    ];
    return StarCatalogue._(n, xyz, rad, alpha, halo, twFreq, twPhase, rgb, named);
  }

  /// B-V colour index to a gently saturated star colour.
  static int _bvColor(double bv) {
    bv = bv.clamp(-.4, 2);
    final temp = 4600 * (1 / (.92 * bv + 1.7) + 1 / (.92 * bv + .62)), t = temp / 100;
    double r, g, b;
    if (t <= 66) {
      r = 255;
      g = 99.47 * math.log(t) - 161.12;
      b = t <= 19 ? 0 : 138.52 * math.log(t - 10) - 305.04;
    } else {
      r = 329.7 * math.pow(t - 60, -.1332);
      g = 288.12 * math.pow(t - 60, -.0755);
      b = 255;
    }
    final c = [r.clamp(0, 255) / 255, g.clamp(0, 255) / 255, b.clamp(0, 255) / 255];
    final m = c.reduce(math.max);
    const s = .62;
    int ch(double v) => ((1 - s + s * v / m) * 255).round().clamp(0, 255);
    return ch(c[0]) << 16 | ch(c[1]) << 8 | ch(c[2]);
  }
}

/// Where each kind of star sprite sits in the atlas.
class StarAtlas {
  StarAtlas(this.image);
  final ui.Image image;

  /// A wide Gaussian for bright stars: cell 64 px, sigma 10 px.
  static const double bigL = 0, bigT = 0, bigSize = 64, bigSigma = 10;

  /// A small Gaussian for the many faint stars: cell 16 px, sigma 2.5 px.
  static const double smallL = 72, smallT = 0, smallSize = 16, smallSigma = 2.5;

  /// The soft halo around the brightest stars: cell 128 px, 5 px per sigma.
  static const double haloL = 0, haloT = 72, haloSize = 128, haloSigma = 5;

  static Future<StarAtlas> build() async {
    const w = 128, h = 200;
    final px = Uint8List(w * h * 4);
    void put(int x, int y, double v) {
      final b = (v.clamp(0, 1) * 255).round(), o = (y * w + x) * 4;
      px[o] = px[o + 1] = px[o + 2] = px[o + 3] = b; // white, premultiplied
    }

    void gaussian(int l, int t, int size, double sigma) {
      final c = size / 2, edge = size / 2;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final dx = x + .5 - c, dy = y + .5 - c, d = math.sqrt(dx * dx + dy * dy);
          final r = d / sigma;
          put(l + x, t + y, math.exp(-.5 * r * r) * _fade(d / edge));
        }
      }
    }

    gaussian(bigL.toInt(), bigT.toInt(), bigSize.toInt(), bigSigma);
    gaussian(smallL.toInt(), smallT.toInt(), smallSize.toInt(), smallSigma);
    const hs = 128;
    for (var y = 0; y < hs; y++) {
      for (var x = 0; x < hs; x++) {
        final dx = x + .5 - hs / 2, dy = y + .5 - hs / 2, d = math.sqrt(dx * dx + dy * dy);
        final r = d / haloSigma, u = d / (hs / 2);
        final win = 1 - _smooth(.35, 1, u);
        put(haloL.toInt() + x, haloT.toInt() + y, 1 / (1 + .22 * r * r) * win);
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(px);
    final desc = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    return StarAtlas(frame.image);
  }

  static double _smooth(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// Takes the last sliver of a sprite to exactly zero so its square edge never shows.
  static double _fade(double u) => 1 - _smooth(.86, 1, u);
}
