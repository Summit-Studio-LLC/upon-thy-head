import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme.dart';

/// Fades its child in (after [delay]) and out, and lets touches through only
/// while shown. Like the prototype's opacity transitions with a delay.
class Fade extends StatefulWidget {
  const Fade({
    super.key,
    required this.on,
    required this.child,
    this.inDuration = const Duration(milliseconds: 700),
    this.outDuration = const Duration(milliseconds: 550),
    this.delay = Duration.zero,
  });

  final bool on;
  final Widget child;
  final Duration inDuration, outDuration, delay;

  @override
  State<Fade> createState() => _FadeState();
}

class _FadeState extends State<Fade> {
  late bool _shown = widget.on;
  Timer? _timer;

  @override
  void didUpdateWidget(Fade old) {
    super.didUpdateWidget(old);
    if (old.on == widget.on) return;
    _timer?.cancel();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.on || widget.delay == Duration.zero || still) {
      _shown = widget.on;
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return IgnorePointer(
      ignoring: !widget.on,
      child: ExcludeSemantics(
        excluding: !widget.on,
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: still ? Duration.zero : (_shown ? widget.inDuration : widget.outDuration),
          curve: easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
