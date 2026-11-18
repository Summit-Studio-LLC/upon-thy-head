import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../theme.dart';
import 'person.dart';

/// "Whose blessing", once there are family members (design B1-07): a row of names that wraps,
/// For me · Emma · James · Passing it along, the chosen one in gold. Choosing one puts the blessing
/// on that ring (or passes it along) at once.
class WhoseChoice extends StatelessWidget {
  const WhoseChoice({super.key, required this.palette, required this.people, required this.value, required this.onChanged});

  final Palette palette;
  final List<Person> people;
  final Whose value;
  final ValueChanged<Whose> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget chip(Whose w, String label, Key key) {
      final on = value == w;
      return Semantics(
        button: true,
        selected: on,
        inMutuallyExclusiveGroup: true,
        label: label,
        excludeSemantics: true,
        onTap: () => onChanged(w),
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(w),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(color: on ? p.light : p.ink.withValues(alpha: .07), borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: sans(15, 20, on ? p.ground : p.ink2, weight: on ? FontWeight.w500 : FontWeight.w400)),
          ),
        ),
      );
    }

    return Column(key: const Key('review-whose'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(Strings.whoFor, style: sans(13, 18, p.ink3)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        chip(Whose.me, Strings.forMeChoice, const Key('review-for-me')),
        for (final person in people) chip(WhosePerson(person.id), person.name, Key('review-person-${person.id}')),
        chip(Whose.passing, Strings.passingAlong, const Key('review-passing')),
      ]),
    ]);
  }
}
