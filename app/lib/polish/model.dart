import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'change.dart';
import 'model_check.dart';
import 'model_instructions.dart';

/// A language model that runs on the phone itself and nowhere else. On iPhone and iPad it is Apple's
/// on-device model (ios/Runner/PhoneModel.swift); Android has none yet, and one can be added by
/// answering the same channel from Kotlin, with nothing here changed.
abstract class PhoneModel {
  /// Whether the model can be used now for words in [language] ("en" or "es"). Never throws.
  Future<bool> ready(String language);

  /// The model's version of [text], told [instructions]; null when it refused, failed, or was
  /// cancelled. Each call stands alone: nothing of one is seen by the next.
  Future<String?> polish(String text, {required String language, required String instructions, required String id});

  /// Stop the call [id], if it is still running.
  Future<void> cancel(String id);
}

/// No model on this phone: polish is the rules alone.
class NoModel implements PhoneModel {
  const NoModel();
  @override
  Future<bool> ready(String language) async => false;
  @override
  Future<String?> polish(String text, {required String language, required String instructions, required String id}) async => null;
  @override
  Future<void> cancel(String id) async {}
}

/// The model behind `upon_thy_head/model`. A phone that does not answer the channel (Android today,
/// an iPhone before iOS 26) is a phone without a model.
class ChannelModel implements PhoneModel {
  const ChannelModel();
  static const _channel = MethodChannel('upon_thy_head/model');

  @override
  Future<bool> ready(String language) async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('status', {'language': language});
      return r?['available'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> polish(String text, {required String language, required String instructions, required String id}) async {
    try {
      return await _channel.invokeMethod<String>('polish', {'id': id, 'text': text, 'language': language, 'instructions': instructions});
    } catch (_) {
      return null; // refused, a guardrail, too long, cancelled: this piece gets the rules alone
    }
  }

  @override
  Future<void> cancel(String id) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } catch (_) {}
  }
}

/// The model this phone has. Only iOS answers the channel for now.
PhoneModel phoneModel = Platform.isIOS ? const ChannelModel() : const NoModel();

/// A polish under way, which leaving the page stops.
class PolishWork {
  bool _cancelled = false;
  final _running = <String>{};
  PhoneModel? _model;

  bool get cancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final id in _running) {
      _model?.cancel(id);
    }
  }
}

/// Changes from the phone's model: the spoken words cut into pieces small enough for it, each piece
/// sent on its own, every answer put through [ModelCheck], and what passes placed back at its
/// offset in the spoken words.
class ModelSource {
  ModelSource(this.model, {this.pieceTime = pieceLimit});
  final PhoneModel model;

  /// How long one piece may take here ([pieceLimit], shorter in tests).
  final Duration pieceTime;

  static const name = 'model';

  /// The longest piece, in characters. Apple's model reads 4,096 tokens at once, for the
  /// instructions, the piece and its answer together; at three to four characters a token, 1,200
  /// characters is about 400 tokens in and as many out, beside about 450 of instructions.
  static const pieceChars = 1200;

  /// How long one piece may take. The model writes some tens of words a second; a full piece is
  /// about 250 words.
  static const pieceLimit = Duration(seconds: 25);

  static int _calls = 0;

  /// Changes to [spoken], in order, none overlapping; empty when the model is not there, and for
  /// any piece it refused, failed on, or answered badly.
  ///
  /// [onPiece] hears where the work is, for the light over the words: piece [index] of [pieces]
  /// (where each sits in [spoken]) as it goes to the model, and [index] == pieces.length once
  /// every piece is answered. Not called when there is no model, nor after a cancel.
  Future<List<Change>> find(String spoken, String language,
      {Set<String> names = const {}, PolishWork? work, void Function(int index, List<TextRange> pieces)? onPiece}) async {
    final lang = language == 'es' ? 'es' : 'en';
    if (spoken.trim().isEmpty || !await model.ready(lang)) return const [];
    work?._model = model;
    final instructions = ModelInstructions.of(lang, names: names);
    final out = <Change>[];
    final all = pieces(spoken);
    final ranges = List<TextRange>.unmodifiable([for (final p in all) TextRange(start: p.start, end: p.start + p.text.length)]);
    for (final (i, p) in all.indexed) {
      if (work?.cancelled ?? false) return const [];
      onPiece?.call(i, ranges);
      final id = 'p${_calls++}';
      work?._running.add(id);
      String? answer;
      try {
        answer = await model.polish(p.text, language: lang, instructions: instructions, id: id).timeout(pieceTime);
      } on TimeoutException {
        unawaited(model.cancel(id));
        answer = null;
      } finally {
        work?._running.remove(id);
      }
      if (work?.cancelled ?? false) return const [];
      if (answer == null) continue;
      out.addAll(ModelCheck.changes(p.text, answer, language: lang, names: names, offset: p.start, source: name));
    }
    if (!(work?.cancelled ?? false)) onPiece?.call(ranges.length, ranges);
    return out;
  }

  /// [spoken] cut into pieces of at most [max] characters, each without the spaces at its ends,
  /// with where it starts. Cut at a paragraph if one is near the end of the piece, else at the end
  /// of a sentence, else after a comma (a pause), else between words.
  static List<({int start, String text})> pieces(String spoken, {int max = pieceChars}) {
    final out = <({int start, String text})>[];
    var at = 0;
    while (at < spoken.length) {
      // skip the spaces between pieces
      while (at < spoken.length && spoken[at].trim().isEmpty) {
        at++;
      }
      if (at >= spoken.length) break;
      var end = spoken.length;
      if (end - at > max) end = _cut(spoken, at, at + max);
      final text = spoken.substring(at, end).trimRight();
      if (text.isNotEmpty) out.add((start: at, text: text));
      at = end;
    }
    return out;
  }

  /// Where to end a piece that starts at [from] and may run to [limit].
  static int _cut(String s, int from, int limit) {
    final window = s.substring(from, limit);
    final least = (window.length * .4).floor(); // never a piece of less than 40% of the most
    for (final p in [RegExp(r'\n\s*'), RegExp(r'[.!?…]["”’)]*\s+'), RegExp(r'[,;:]\s+'), RegExp(r'\s+')]) {
      int? best;
      for (final m in p.allMatches(window)) {
        if (m.end >= least) best = m.end;
      }
      if (best != null) return from + best;
    }
    return limit; // one very long word: cut it (the check sees a piece edge, nothing more)
  }
}
