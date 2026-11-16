import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import 'checks.dart';

const _channel = MethodChannel('upon_thy_head/check');
const _lockChannel = MethodChannel('upon_thy_head/lock');

enum _State { waiting, running, done, failed }

class _Row {
  _Row(this.item);
  final PhoneCheckItem item;
  _State state = _State.waiting;
  List<String> lines = const [];
  List<CheckAction> actions = const [];
  String? error;
  final Map<CheckAction, String> said = {};
  Duration took = Duration.zero;
}

/// The phone check (PHONE_CHECK builds only): runs every check in lib/check/checks.dart, each on its
/// own time limit and on its own, shows the answers in plain sentences, and offers the report as
/// text. The report also goes to the app's log between [reportBegin] and [reportEnd], and to
/// Documents/phone-check.txt, for tool/phone.sh.
class PhoneCheckPage extends StatefulWidget {
  const PhoneCheckPage({super.key, required this.palette});
  final Palette palette;

  static Future<void> open(BuildContext context, Palette palette) =>
      Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => PhoneCheckPage(palette: palette)));

  @override
  State<PhoneCheckPage> createState() => PhoneCheckPageState();
}

class PhoneCheckPageState extends State<PhoneCheckPage> implements CheckHost {
  late final List<_Row> _rows = [for (final c in phoneChecks()) _Row(c)];
  Widget? _over;
  bool _running = false;
  bool _copied = false;
  String _version = '';
  DateTime? _started;

  /// The last full report, as copied.
  String report = '';

  @override
  void initState() {
    super.initState();
    _lockChannel.invokeMethod<String>('version').then((v) => _version = v ?? '', onError: (_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) => runAll());
  }

  void _set(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    } else {
      fn();
    }
  }

  @override
  void showOver(Widget? w) {
    if (mounted) setState(() => _over = w);
  }

  /// Every check, one after another. A check that throws or runs past its limit is reported and
  /// the next one runs.
  Future<void> runAll() async {
    if (_running) return;
    _started = DateTime.now();
    for (final r in _rows) {
      r.state = _State.waiting;
    }
    await _run([for (final r in _rows) r.item.number]);
  }

  Future<void> _run(List<int> numbers) async {
    if (_running) return;
    _set(() => _running = true);
    for (final r in _rows.where((r) => numbers.contains(r.item.number))) {
      _set(() {
        r.state = _State.running;
        r.error = null;
        r.lines = const [];
        r.actions = const [];
        r.said.clear();
      });
      final watch = Stopwatch()..start();
      try {
        final o = await r.item.body(this).timeout(r.item.limit);
        r.lines = o.lines;
        r.actions = o.actions;
        r.state = _State.done;
      } on TimeoutException {
        r.error = 'No answer within ${r.item.limit.inSeconds} seconds, so the check stopped waiting.';
        r.state = _State.failed;
        showOver(null);
      } catch (e, s) {
        r.error = '$e\n${s.toString().trim()}';
        r.state = _State.failed;
        showOver(null);
      }
      r.took = watch.elapsed;
      _set(() {});
    }
    _set(() => _running = false);
    await _publish();
  }

  Future<void> _act(_Row r, CheckAction a) async {
    void say(String s) {
      if (mounted) setState(() => r.said[a] = s);
    }

    say('Working…');
    try {
      await a.run(say);
    } catch (e) {
      say('Failed: $e');
    }
    if (a.rerun.isNotEmpty) await _run(a.rerun);
  }

  String _text() {
    final b = StringBuffer()
      ..writeln('Upon Thy Head phone check')
      ..writeln('App $_version, $buildMode build. Started ${_stamp(_started ?? DateTime.now())}.')
      ..writeln();
    for (final r in _rows) {
      b.writeln('${r.item.number}. ${r.item.title}${r.state == _State.failed ? ' (FAILED)' : ''} [${(r.took.inMilliseconds / 1000).toStringAsFixed(1)} s]');
      if (r.state == _State.waiting || r.state == _State.running) b.writeln('   Not finished.');
      for (final l in r.lines) {
        b.writeln('   $l');
      }
      if (r.error != null) {
        for (final l in r.error!.split('\n')) {
          b.writeln('   ! $l');
        }
      }
      b.writeln();
    }
    return b.toString().trimRight();
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// The report into the log (between the markers) and a file in Documents.
  Future<void> _publish() async {
    report = _text();
    final lines = [reportBegin, ...report.split('\n'), reportEnd];
    try {
      await _channel.invokeMethod<void>('log', {'lines': lines});
    } catch (e) {
      debugPrint('phone check: could not log the report: $e');
    }
    try {
      final f = File(p.join((await getApplicationDocumentsDirectory()).path, 'phone-check.txt'));
      await f.writeAsString('$report\n');
    } catch (e) {
      debugPrint('phone check: could not save the report: $e');
    }
  }

  Future<void> _copy() async {
    report = _text();
    await Clipboard.setData(ClipboardData(text: report));
    setState(() => _copied = true);
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.palette;
    final dy = math.max(62.0, MediaQuery.of(context).viewPadding.top) - 62;
    final hint = sans(13, 18, pal.ink3);
    Widget hairline() => Container(height: 1, color: pal.ink.withValues(alpha: .10));
    return ColoredBox(
      color: pal.ground,
      child: Stack(children: [
        Positioned.fill(
          child: SingleChildScrollView(
            key: const Key('check-scroll'),
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: EdgeInsets.fromLTRB(28, 112 + dy, 28, 64),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Phone check', key: const Key('check-title'), style: serif(34, 38, pal.ink, tracking: -.012)),
              const SizedBox(height: 10),
              Text('Checks what only a real iPhone can answer. This page is only in test builds.', style: hint),
              const SizedBox(height: 24),
              hairline(),
              for (final r in _rows) ...[
                Padding(
                  key: Key('check-${r.item.number}'),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Expanded(child: Text('${r.item.number}. ${r.item.title}', style: sans(17, 22, pal.ink))),
                      Text(
                        switch (r.state) {
                          _State.waiting => 'Waiting',
                          _State.running => 'Checking…',
                          _State.done => '${(r.took.inMilliseconds / 1000).toStringAsFixed(1)} s',
                          _State.failed => 'Failed',
                        },
                        key: Key('check-${r.item.number}-state'),
                        style: sans(13, 18, r.state == _State.failed ? pal.danger : (r.state == _State.running ? pal.light : pal.ink3)),
                      ),
                    ]),
                    for (final l in r.lines) ...[
                      const SizedBox(height: 6),
                      Text(l, style: sans(15, 21, pal.ink2)),
                    ],
                    if (r.error != null) ...[
                      const SizedBox(height: 6),
                      Text(r.error!, key: Key('check-${r.item.number}-error'), style: sans(13, 18, pal.danger)),
                    ],
                    for (final a in r.actions) ...[
                      const SizedBox(height: 10),
                      PillBtn(label: a.label, palette: pal, kind: PillKind.tonal, height: 40, fontSize: 15, onTap: _running ? null : () => _act(r, a)),
                      if (r.said[a] != null) ...[
                        const SizedBox(height: 6),
                        Text(r.said[a]!, style: hint),
                      ],
                    ],
                  ]),
                ),
                hairline(),
              ],
              const SizedBox(height: 28),
              PillBtn(
                key: const Key('check-copy'),
                label: _copied ? 'Copied' : 'Copy report',
                palette: pal,
                kind: PillKind.primary,
                onTap: _copy,
              ),
              const SizedBox(height: 12),
              PillBtn(
                key: const Key('check-again'),
                label: _running ? 'Checking…' : 'Run again',
                palette: pal,
                kind: PillKind.quiet,
                onTap: _running ? null : runAll,
              ),
            ]),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 104 + dy,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [pal.ground, pal.ground.withValues(alpha: .7), pal.ground.withValues(alpha: 0)],
                  stops: const [0, .55, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 4,
          top: 54 + dy,
          child: IconBtn(
            key: const Key('check-back'),
            icon: Glyph.older,
            color: pal.ink,
            palette: pal,
            semantics: 'Back to Settings',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        // the sky, while check 7 measures it
        if (_over != null) Positioned.fill(child: _over!),
      ]),
    );
  }
}
