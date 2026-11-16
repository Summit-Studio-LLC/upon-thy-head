#!/bin/bash
# A frame strip from a film: frames every <step> ms from <start> seconds, side by side, each
# marked with its time from the first. For the first run's moves, read the start off the film.
set -euo pipefail
film="$1"; out="$2"; from="$3"; step="$4"; n="$5"; w="${6:-268}"
d="$(mktemp -d)"; frames=()
for i in $(seq 0 $((n - 1))); do
  ts="$(python3 -c "print(f'{$from + $i * $step / 1000:.3f}')")"
  ffmpeg -y -loglevel error -ss "$ts" -i "$film" -frames:v 1 -vf "scale=$w:-2" "$d/$i.png"
  magick "$d/$i.png" -gravity southwest -fill white -pointsize 18 -annotate +8+8 "+$((i * step)) ms" "$d/$i.png"
  frames+=("$d/$i.png")
done
magick "${frames[@]}" +append "$out"
rm -rf "$d"
