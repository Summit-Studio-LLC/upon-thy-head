import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'astro.dart';
import 'catalogue.dart';
import 'figures.dart';
import 'sky_engine.dart';
import 'sky_painter.dart';

/// Loads the star catalogue, the Milky Way and the shaders.
Future<SkyAssets> loadSkyAssets() async {
  final results = await Future.wait<Object>([
    StarCatalogue.load(),
    StarAtlas.build(),
    ui.FragmentProgram.fromAsset('shaders/sky.frag'),
    ui.FragmentProgram.fromAsset('shaders/light.frag'),
    _loadImage('assets/sky/milkyway_4k.jpg'),
    _loadImage('assets/sky/milkyway_soft.png'),
    Figures.load(),
  ]);
  return SkyAssets(
    stars: results[0] as StarCatalogue,
    atlas: results[1] as StarAtlas,
    skyProgram: results[2] as ui.FragmentProgram,
    lightProgram: results[3] as ui.FragmentProgram,
    milkyWay: results[4] as ui.Image,
    milkyWaySoft: results[5] as ui.Image,
    figures: results[6] as Figures,
  );
}

Future<ui.Image> _loadImage(String asset) async {
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

/// The sky, filling whatever space it is given. Drag to look around, pinch to
/// zoom, tap a light to turn to it.
class SkyWidget extends StatefulWidget {
  const SkyWidget({
    super.key,
    required this.engine,
    required this.assets,
    required this.palette,
    required this.line,
    this.interactive = true,
    this.showLabels = true,
    this.onTapFocused,
    this.onStats,
  });

  final SkyEngine engine;
  final SkyAssets assets;
  final Palette palette;
  final List<Vec3> line;
  final bool interactive, showLabels;

  /// Tapping the light that is already in focus.
  final VoidCallback? onTapFocused;
  final void Function(int stars, int micros)? onStats;

  @override
  State<SkyWidget> createState() => _SkyWidgetState();
}

class _SkyWidgetState extends State<SkyWidget> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  Duration _last = Duration.zero;
  SkyPainter? _painter;
  double _dpr = 0;

  // gesture state
  double _startFov = 90;
  Offset _lastFocal = Offset.zero;
  bool _down = false, _pinched = false;
  int _pointers = 0;
  Duration _lastMove = Duration.zero;
  final Stopwatch _clock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = _last == Duration.zero ? 0.0 : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, .05);
      _last = elapsed;
      widget.engine.step(dt);
      _frame.value++;
    })
      ..start();
  }

  @override
  void didUpdateWidget(SkyWidget old) {
    super.didUpdateWidget(old);
    if (old.engine != widget.engine || old.palette != widget.palette || old.showLabels != widget.showLabels || old.line != widget.line) {
      _painter = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  // Called again whenever a finger lands or lifts mid-gesture: re-base there
  // so neither the zoom nor the look point jumps.
  void _onScaleStart(ScaleStartDetails d) {
    _startFov = widget.engine.goalFov;
    _lastFocal = d.localFocalPoint;
    _lastMove = _clock.elapsed;
    if (!_down) widget.engine.dragStart();
    _down = true;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final e = widget.engine;
    final now = _clock.elapsed;
    final dt = (now - _lastMove).inMicroseconds / 1e6;
    _lastMove = now;
    final delta = d.localFocalPoint - _lastFocal;
    _lastFocal = d.localFocalPoint;
    if (delta != Offset.zero) e.dragBy(delta, dt);
    if (d.pointerCount > 1 && d.scale > 0) {
      e.pinch(_startFov / d.scale, d.localFocalPoint);
      _pinched = true;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (d.pointerCount > 0) return; // a finger lifted; the gesture goes on with the rest
    _finish();
  }

  // The recognizer sends no final onEnd when the last fingers of a pinch lift
  // close together, so raw pointer counts end the gesture too.
  void _onPointerDown(PointerDownEvent _) => _pointers++;

  void _onPointerUp(PointerEvent _) {
    _pointers = (_pointers - 1).clamp(0, 99);
    if (_pointers == 0) _finish();
  }

  void _finish() {
    if (!_down) return;
    _down = false;
    // a pinch never flings; a drag flings only if the finger was still moving when it lifted
    final still = _pinched || (_clock.elapsed - _lastMove).inMilliseconds > 90;
    _pinched = false;
    widget.engine.dragEnd(still: still);
  }

  void _onTapUp(TapUpDetails d) {
    final e = widget.engine;
    final i = e.hit(d.localPosition);
    if (i < 0) return;
    if (i == e.focus && !e.free) {
      widget.onTapFocused?.call();
    } else {
      e.setFocus(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    widget.engine.reduceMotion = mq.disableAnimations;
    if (_painter == null || _dpr != mq.devicePixelRatio) {
      _dpr = mq.devicePixelRatio;
      _painter = SkyPainter(
        engine: widget.engine,
        assets: widget.assets,
        palette: widget.palette,
        dpr: _dpr,
        showLabels: widget.showLabels,
        line: widget.line,
        repaint: _frame,
        onStats: widget.onStats,
      );
    }
    final paint = RepaintBoundary(child: CustomPaint(painter: _painter, size: Size.infinite, isComplex: true, willChange: true));
    if (!widget.interactive) return paint;
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onTapUp: _onTapUp,
        child: paint,
      ),
    );
  }
}
