#!/bin/bash
# The Android launcher icon, made from the chosen icon (design/icon/final/), with ImageMagick.
#
#   tool/android_icons.sh
#
# An adaptive icon (android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml):
# - background: the app's ground colour, #0B0907 (values/colors.xml);
# - foreground: icon-1024.png (whose own ground is #0B0907) at 80 % of the 108 dp layer. The
#   mark's farthest point from the centre is the arch's faded tip, 383 px of 1024 out, so at 80 %
#   it sits 32.4 dp from the centre: inside the 33 dp safe circle every launcher mask keeps;
# - monochrome (Android 13 themed icons): icon-1024-tinted.png turned into white with its
#   brightness as the opacity, at the same size and place, so the system can tint it.
# Plus the old square ic_launcher.png, which Android 13 and later never show, and the
# notification's small icon (drawable-*/ic_notification.png, 24 dp): the same white mark, trimmed
# to its edges and filling 22 dp of it, for the recording notification (RecordingService.kt).
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=../design/icon/final
RES=android/app/src/main/res
for pair in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  d=${pair%%:*}
  k=${pair##*:}
  c=$(awk "BEGIN{print int(108*$k+.5)}")   # the layer, 108 dp
  w=$(awk "BEGIN{print int(108*$k*.8+.5)}") # the artwork in it
  l=$(awk "BEGIN{print int(48*$k+.5)}")     # the old icon, 48 dp
  mkdir -p "$RES/mipmap-$d"
  magick -size "${c}x${c}" xc:'#0B0907' \( "$SRC/icon-1024.png" -resize "${w}x${w}" \) \
    -gravity center -composite -strip "$RES/mipmap-$d/ic_launcher_foreground.png"
  magick \( -size "${w}x${w}" xc:white \) \
    \( "$SRC/icon-1024-tinted.png" -resize "${w}x${w}" -colorspace Gray -level 4%,100% \) \
    -alpha off -compose CopyOpacity -composite \
    -background none -gravity center -extent "${c}x${c}" -strip "$RES/mipmap-$d/ic_launcher_monochrome.png"
  magick "$SRC/icon-1024.png" -resize "${l}x${l}" -strip "$RES/mipmap-$d/ic_launcher.png"
  n=$(awk "BEGIN{print int(24*$k+.5)}")     # the notification icon, 24 dp
  a=$(awk "BEGIN{print int(22*$k+.5)}")     # the mark in it
  mkdir -p "$RES/drawable-$d"
  magick \( -size 1024x1024 xc:white \) \
    \( "$SRC/icon-1024-tinted.png" -colorspace Gray -level 4%,100% \) \
    -alpha off -compose CopyOpacity -composite -compose Over -trim +repage \
    -resize "${a}x${a}" -background none -gravity center -extent "${n}x${n}" -strip "$RES/drawable-$d/ic_notification.png"
done
echo "icons written to $RES/mipmap-*"
