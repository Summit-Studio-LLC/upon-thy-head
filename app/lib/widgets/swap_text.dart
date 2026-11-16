import 'dart:async';

import 'package:flutter/widgets.dart';

/// Text that, given new words, lets the old ones fade out and the new ones fade in, 140 ms each
/// (the prototype's `swapText`). With Reduce Motion, or [instant], the new words simply appear.
class SwapText extends StatefulWidget {
  const SwapText(this.text, {super.key, required this.style, this.textKey, this.textAlign, this.instant = false});
  final String text;
  final TextStyle style;
  final Key? textKey;
  final TextAlign? textAlign;
  final bool instant;

  static const half = Duration(milliseconds: 140);

  @override
  State<SwapText> createState() => _SwapTextState();
}

class _SwapTextState extends State<SwapText> {
  late String _shown = widget.text;
  bool _hidden = false;
  Timer? _timer;

  @override
  void didUpdateWidget(SwapText old) {
    super.didUpdateWidget(old);
    if (widget.text == old.text) return;
    _timer?.cancel();
    if (widget.instant || MediaQuery.maybeDisableAnimationsOf(context) == true || widget.text == _shown && !_hidden) {
      _shown = widget.text;
      _hidden = false;
      return;
    }
    _hidden = true;
    _timer = Timer(SwapText.half, () {
      if (mounted) {
        setState(() {
          _shown = widget.text;
          _hidden = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _hidden ? 0 : 1,
        duration: SwapText.half,
        child: Text(_shown, key: widget.textKey, style: widget.style, textAlign: widget.textAlign),
      );
}
