// Driving a screen the way VoiceOver and TalkBack do: through the semantics tree, never a touch.

import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

SemanticsOwner _owner(WidgetTester t) => t.binding.renderViews.first.owner!.semanticsOwner!;

/// Every node in the tree a screen reader can land on, those scrolled out of view too (it scrolls
/// to them).
List<SemanticsNode> semanticsNodes(WidgetTester t) {
  final out = <SemanticsNode>[];
  void walk(SemanticsNode n) {
    out.add(n);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  final root = _owner(t).rootSemanticsNode;
  if (root != null) walk(root);
  return out;
}

bool _pressable(SemanticsData d) =>
    (d.flagsCollection.isButton || d.flagsCollection.isToggled != Tristate.none) && d.flagsCollection.isEnabled != Tristate.isFalse;

/// The labels of every enabled button and switch on screen that a screen reader cannot press.
List<String> unpressable(WidgetTester t) => [
      for (final n in semanticsNodes(t))
        if (_pressable(n.getSemanticsData()) && !n.getSemanticsData().hasAction(SemanticsAction.tap)) n.getSemanticsData().label,
    ];

/// Every enabled button and switch on screen, by label.
List<String> pressable(WidgetTester t) => [
      for (final n in semanticsNodes(t))
        if (_pressable(n.getSemanticsData())) n.getSemanticsData().label,
    ];

SemanticsNode nodeLabelled(WidgetTester t, Pattern label) {
  final found = [
    for (final n in semanticsNodes(t))
      if (label is RegExp ? label.hasMatch(n.getSemanticsData().label) : n.getSemanticsData().label == label) n,
  ];
  expect(found, isNotEmpty, reason: 'nothing on screen is labelled "$label"; there is: ${semanticsNodes(t).map((n) => n.getSemanticsData().label).where((l) => l.isNotEmpty).toList()}');
  return found.first;
}

/// A screen reader's double-tap on the node labelled [label]: the tap action, as iOS's
/// accessibilityActivate and Android's ACTION_CLICK send it. Fails when the node has none.
Future<void> activate(WidgetTester t, Pattern label, {SemanticsAction action = SemanticsAction.tap}) async {
  final n = nodeLabelled(t, label);
  expect(n.getSemanticsData().hasAction(action), isTrue, reason: '"${n.getSemanticsData().label}" has no $action: a screen reader cannot press it');
  _owner(t).performAction(n.id, action);
  await t.pump();
}

/// Every enabled button on screen pressed once through the semantics tree, each on a fresh screen
/// from [build] (a press may leave the screen). Returns the labels pressed.
Future<List<String>> pressEach(WidgetTester t, Future<void> Function() build) async {
  await build();
  final labels = pressable(t);
  for (final l in labels) {
    // a press may have opened a menu over the page: start again from nothing
    await t.pumpWidget(const SizedBox());
    await build();
    final n = semanticsNodes(t).where((n) => n.getSemanticsData().label == l && _pressable(n.getSemanticsData())).firstOrNull;
    if (n == null) continue;
    expect(n.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: '"$l" cannot be pressed by a screen reader');
    _owner(t).performAction(n.id, SemanticsAction.tap);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }
  return labels;
}
