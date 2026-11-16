import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// What the sky painter reports each frame: sprites drawn and microseconds
/// spent filling the star buffers.
class StarFillStats {
  int frames = 0, sprites = 0, micros = 0, worstMicros = 0;

  void add(int n, int us) {
    frames++;
    sprites = n;
    micros += us;
    worstMicros = math.max(worstMicros, us);
  }

  void reset() => frames = micros = worstMicros = 0;
}

/// Frame timings over the sky, one-second windows. Also printed to the log
/// every two seconds as `SKYSTATS ...` so they can be collected from a run.
class SkyStatsOverlay extends StatefulWidget {
  const SkyStatsOverlay({super.key, required this.fill});
  final StarFillStats fill;

  @override
  State<SkyStatsOverlay> createState() => _SkyStatsOverlayState();
}

class _SkyStatsOverlayState extends State<SkyStatsOverlay> {
  final List<FrameTiming> _window = [];
  late final Timer _timer;
  final Stopwatch _sw = Stopwatch()..start();
  String _text = 'measuring…';
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _summarise());
  }

  void _onTimings(List<FrameTiming> t) => _window.addAll(t);

  void _summarise() {
    final secs = _sw.elapsedMicroseconds / 1e6;
    _sw.reset();
    final n = _window.length;
    double ms(Duration d) => d.inMicroseconds / 1000;
    var bSum = 0.0, bMax = 0.0, rSum = 0.0, rMax = 0.0, tMax = 0.0;
    for (final f in _window) {
      final b = ms(f.buildDuration), r = ms(f.rasterDuration);
      bSum += b;
      rSum += r;
      bMax = math.max(bMax, b);
      rMax = math.max(rMax, r);
      tMax = math.max(tMax, b + r);
    }
    _window.clear();
    final fill = widget.fill;
    final fillAvg = fill.frames == 0 ? 0 : fill.micros / fill.frames;
    final fps = n / secs;
    String f1(double v) => v.toStringAsFixed(1);
    final text = '${f1(fps)} fps\n'
        'build ${f1(n == 0 ? 0 : bSum / n)} / ${f1(bMax)} ms\n'
        'raster ${f1(n == 0 ? 0 : rSum / n)} / ${f1(rMax)} ms\n'
        'b+r ${f1(n == 0 ? 0 : (bSum + rSum) / n)} / ${f1(tMax)} ms\n'
        'sprites ${fill.sprites}\n'
        'fill ${fillAvg.round()} / ${fill.worstMicros} µs';
    if (++_tick % 2 == 0) {
      debugPrint('SKYSTATS renderer=${ui.ImageFilter.isShaderFilterSupported ? 'impeller' : 'skia'} fps=${f1(fps)} frames=$n buildAvg=${f1(n == 0 ? 0 : bSum / n)} buildMax=${f1(bMax)} '
          'rasterAvg=${f1(n == 0 ? 0 : rSum / n)} rasterMax=${f1(rMax)} totalAvg=${f1(n == 0 ? 0 : (bSum + rSum) / n)} '
          'totalMax=${f1(tMax)} sprites=${fill.sprites} fillAvgUs=${fillAvg.round()} fillMaxUs=${fill.worstMicros}');
    }
    fill.reset();
    if (mounted) setState(() => _text = text);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xB0000000), borderRadius: BorderRadius.circular(6)),
        child: Text(
          _text,
          style: const TextStyle(
            fontFamily: 'Menlo',
            fontFamilyFallback: ['Courier'],
            fontSize: 10.5,
            height: 1.35,
            color: Color(0xFFB8F5B0),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
