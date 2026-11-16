// The rules for a blessing's tags (lib/review/tags.dart).
//
//   flutter test test/tags_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/review/tags.dart';

void main() {
  test('clean tidies spaces and stray marks, and capitalises only the first letter', () {
    expect(TagRules.clean('  Comfort  '), 'Comfort');
    expect(TagRules.clean('new   job'), 'New job', reason: 'later words are left as typed');
    expect(TagRules.clean('healing'), 'Healing');
    expect(TagRules.clean('éxito en el trabajo'), 'Éxito en el trabajo');
    expect(TagRules.clean('new York'), 'New York');
    expect(TagRules.clean('#Healing'), 'Healing');
    expect(TagRules.clean('Family,'), 'Family');
    expect(TagRules.clean('   '), '');
    expect(TagRules.clean('x' * 60).length, TagRules.maxLength);
  });

  test('add puts a new tag at the end, once, ignoring capitals', () {
    expect(TagRules.add([], 'Comfort'), ['Comfort']);
    expect(TagRules.add(['Comfort'], 'Healing'), ['Comfort', 'Healing']);
    expect(TagRules.add(['Comfort'], 'comfort'), ['Comfort'], reason: 'the same tag in other capitals');
    expect(TagRules.add(['Comfort'], '   '), ['Comfort']);
    expect(TagRules.add(['Comfort'], 'Healing, Family ,healing'), ['Comfort', 'Healing', 'Family']);
    expect(TagRules.add([], 'healing'), ['Healing'], reason: 'capitalised as it is added');
  });

  test('add leaves the list it was given as it was', () {
    final tags = ['Comfort'];
    TagRules.add(tags, 'Healing');
    expect(tags, ['Comfort']);
  });

  test('remove takes a tag off in any capitals', () {
    expect(TagRules.remove(['Comfort', 'Healing'], 'Comfort'), ['Healing']);
    expect(TagRules.remove(['Comfort', 'Healing'], 'healing'), ['Comfort']);
    expect(TagRules.remove(['Comfort'], 'Work'), ['Comfort']);
  });

  test('suggest offers tags from other blessings not already here, filtered by what is typed', () {
    const known = ['Family', 'Healing', 'Comfort', 'Calling', 'Work', 'New job'];
    expect(TagRules.suggest(known, [], ''), ['Family', 'Healing', 'Comfort', 'Calling', 'Work', 'New job']);
    expect(TagRules.suggest(known, ['family', 'Work'], ''), ['Healing', 'Comfort', 'Calling', 'New job']);
    expect(TagRules.suggest(known, [], 'c'), ['Comfort', 'Calling']);
    expect(TagRules.suggest(known, [], 'JOB'), ['New job'], reason: 'a later word may match');
    expect(TagRules.suggest(known, [], 'zz'), isEmpty);
    expect(TagRules.suggest(known, [], '', max: 2), ['Family', 'Healing']);
  });
}
