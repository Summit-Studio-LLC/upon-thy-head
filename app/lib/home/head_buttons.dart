import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../strings.dart';
import '../theme.dart';
import '../widgets/icons.dart';

/// The top right of home: "more" (the settings) and, once there is a blessing, the toggle between
/// the sky and the list, side by side in one group of liquid glass (package:liquid_glass_widgets),
/// with the app's own glyphs. Neither opens a menu: "more" opens the settings page.
class HeadButtons extends StatelessWidget {
  const HeadButtons({super.key, required this.palette, required this.onMore, required this.list, required this.onList});

  final Palette palette;
  final VoidCallback onMore;

  /// Whether the list is showing; null when there is no list to show (no toggle then).
  final bool? list;
  final VoidCallback onList;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget glyph(Key key, Glyph g) => SizedBox(key: key, width: 24, height: 24, child: GlyphIcon(g, color: p.ink));
    return GlassButtonGroup.icons(
      key: const Key('head-buttons'),
      iconSize: 24,
      // a capsule, as the person switch at the left
      borderRadius: 22,
      itemPadding: const EdgeInsets.all(10),
      items: [
        GlassButtonGroupItem(icon: glyph(const Key('more'), Glyph.more), label: Strings.more, onTap: onMore),
        if (list != null)
          GlassButtonGroupItem(
            icon: glyph(const Key('list'), list! ? Glyph.sky : Glyph.list),
            label: list! ? Strings.showAsSky : Strings.showAsList,
            onTap: onList,
          ),
      ],
    );
  }
}
