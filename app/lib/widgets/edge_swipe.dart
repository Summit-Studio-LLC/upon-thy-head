import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../not_yet.dart';
import 'sheet.dart';

/// iOS's back swipe for a page with a back chevron (the owner's ruling, 2026-11-16): a drag from
/// the left edge carries the page with the finger, one for one, and the sky shows behind it.
/// Let go past a third of the way, or with a flick to the right, and the page finishes leaving and
/// [onBack] runs, exactly what the chevron does; short of that, it springs back. The release
/// timing is Flutter's own iOS back swipe (CupertinoPageRoute): the time left is in proportion to
/// the distance left, up to 350 ms, on its fast-then-slow curve; shortened with Reduce Motion.
///
/// Only a drag that begins within [edge] points of the left edge, so a page's own horizontal
/// gestures are left alone. Nothing while [enabled] is false (the page not in front) or while a
/// sheet is up. VoiceOver's "go back" (the two-finger scrub) is the same [onBack].
class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({
    super.key,
    required this.enabled,
    required this.onBack,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onBack;
  final Widget child;

  /// How far from the left edge the drag may begin.
  static const edge = 20.0;

  @override
  State<EdgeSwipeBack> createState() => EdgeSwipeBackState();
}

class EdgeSwipeBackState extends State<EdgeSwipeBack>
    with SingleTickerProviderStateMixin {
  /// How far the page has gone, as a fraction of its width.
  late final AnimationController _c = AnimationController(vsync: this);
  double _width = 1;
  bool _dragging = false;

  /// The page finished leaving; it is put back in place when it is next shown.
  bool _gone = false;

  /// Tests: how far the page is across now.
  double get progress => _c.value;

  @override
  void didUpdateWidget(EdgeSwipeBack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled && _gone) {
      _gone = false;
      _c.value = 0;
    }
    if (!widget.enabled && _dragging) {
      // taken away mid-drag (a lock, a file arriving): back in place
      _dragging = false;
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _start(DragStartDetails d) {
    if (!widget.enabled || Sheet.anyUp || _gone) return;
    _dragging = true;
    _c.stop();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _update(DragUpdateDetails d) {
    if (!_dragging) return;
    _c.value = (_c.value + (d.primaryDelta ?? 0) / _width).clamp(0.0, 1.0);
  }

  void _end(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    // as CupertinoPageRoute: a flick of a screen width a second decides by its direction
    final v = d.velocity.pixelsPerSecond.dx / _width;
    _settle(v.abs() >= 1 ? v > 0 : _c.value > 1 / 3);
  }

  void _cancel() {
    if (!_dragging) return;
    _dragging = false;
    _settle(false);
  }

  void _settle(bool leave) {
    final still = MediaQuery.of(context).disableAnimations;
    final left = leave ? 1 - _c.value : _c.value;
    var ms = (350 * left).floor();
    if (still) ms = math.min(ms, 100);
    final run = _c.animateTo(
      leave ? 1 : 0,
      duration: Duration(milliseconds: math.max(ms, 1)),
      curve: Curves.fastLinearToSlowEaseIn,
    );
    if (leave) {
      run.whenCompleteOrCancel(() {
        if (!mounted || _c.value < 1) return;
        _gone = true;
        widget.onBack();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      onDismiss: widget.enabled ? widget.onBack : null,
      child: LayoutBuilder(
        builder: (context, box) {
          _width = math.max(1, box.maxWidth);
          return Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => _c.value == 0
                      ? child!
                      : Transform.translate(
                          offset: Offset(_c.value * _width, 0),
                          child: child,
                        ),
                  child: widget.child,
                ),
              ),
              // Android's own back gesture owns the left edge there (home_screen.dart, `_systemBack`)
              if (widget.enabled && !Phone.android)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: EdgeSwipeBack.edge,
                  // translucent: a tap at the edge still reaches what is under it (the back chevron)
                  child: GestureDetector(
                    key: const Key('edge-swipe'),
                    behavior: HitTestBehavior.translucent,
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragStart: _start,
                    onHorizontalDragUpdate: _update,
                    onHorizontalDragEnd: _end,
                    onHorizontalDragCancel: _cancel,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
