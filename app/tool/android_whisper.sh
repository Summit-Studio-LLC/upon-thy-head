#!/bin/bash
# Builds the native libraries that write the words on Android (docs/android-plan.md 3.5, tasks 8
# to 10): whisper.cpp at a pinned commit, linked statically with android/app/src/main/cpp/
# uth_whisper.cpp into one library per ABI, aligned for 16 KB pages (8.5), into
# android/app/src/main/jniLibs/. The libraries are committed, so an ordinary `flutter build` needs
# neither the NDK's C++ build nor the whisper.cpp source; run this only to change them.
#
#   tool/android_whisper.sh            # source: $WHISPER_SRC, default ~/Development/scratch-uth-speech/whisper.cpp
#
# Three libraries:
#   arm64-v8a/libuth_whisper_v82.so  ARMv8.2 with dot product and half floats (the build measured
#                                    in 3.5; nearly every arm64 phone sold with Android 13 or later)
#   arm64-v8a/libuth_whisper.so      plain ARMv8, for the few without them (Cortex-A53-only phones);
#                                    WhisperNative.kt picks by /proc/cpuinfo
#   x86_64/libuth_whisper.so         Chromebooks and x86 emulators (not testable on this Mac)
# No 32-bit library: a phone without 64-bit apps gets "the words cannot be written on this phone".
set -euo pipefail
cd "$(dirname "$0")/.."
# whisper.cpp, 2026-11-16 (1.9.5-dev): the build measured in android-plan.md 3.5.
# Set WHISPER_PIN to the full 40-char commit SHA (or update PIN once recorded from the clone) so
# short-hash collisions are impossible; when PIN is 40 hex chars an exact match is required.
PIN=${WHISPER_PIN:-aba02de}
SRC=${WHISPER_SRC:-$HOME/Development/scratch-uth-speech/whisper.cpp}
DEFAULT_SDK=$([[ $(uname -s) == Darwin ]] && echo "$HOME/Library/Android/sdk" || echo "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}")
NDK=${ANDROID_NDK:-$DEFAULT_SDK/ndk/28.2.13676358}
WORK=${WHISPER_BUILD:-$HOME/Development/scratch-uth-speech/build-uth}
OUT=android/app/src/main/jniLibs
GLUE=$PWD/android/app/src/main/cpp/uth_whisper.cpp
if [[ -d "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin" ]]; then
  LLVM="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
elif [[ -d "$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin" ]]; then
  LLVM="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
else
  echo "no LLVM prebuilt toolchain found under $NDK/toolchains/llvm/prebuilt (expected linux-x86_64 or darwin-x86_64)"
  exit 1
fi
[[ -d $SRC/.git ]] || { echo "no whisper.cpp at $SRC (git clone https://github.com/ggml-org/whisper.cpp; git checkout $PIN)"; exit 1; }
have=$(git -C "$SRC" rev-parse --verify HEAD)
[[ $have =~ ^[0-9a-f]{40}$ ]] || { echo "invalid HEAD commit SHA at $SRC: $have"; exit 1; }
if (( ${#PIN} == 40 )); then
  [[ $have == "$PIN" ]] || { echo "whisper.cpp at $SRC is $have, not $PIN"; exit 1; }
else
  [[ $have == "$PIN"* ]] || { echo "whisper.cpp at $SRC is $have, does not match prefix $PIN"; exit 1; }
  echo "note: verified prefix $PIN against full commit $have (update PIN to full 40-char SHA)"
fi
[[ -z $(git -C "$SRC" status --porcelain --untracked-files=no) ]] || { echo "whisper.cpp at $SRC has local changes"; exit 1; }

build() { # name abi arch-flags
  local name=$1 abi=$2 arch=$3 b=$WORK/$1-$2
  echo "== $name ($abi${arch:+, $arch})"
  cmake -S "$SRC" -B "$b" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" -DANDROID_ABI=$abi -DANDROID_PLATFORM=android-33 \
    -DANDROID_STL=c++_static -DBUILD_SHARED_LIBS=OFF -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF \
    ${arch:+-DGGML_CPU_ARM_ARCH=$arch} -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF \
    -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections" -DCMAKE_CXX_FLAGS="-ffunction-sections -fdata-sections" >/dev/null
  cmake --build "$b" --target whisper ggml ggml-base ggml-cpu -j 8 >/dev/null
  local cxx="$LLVM/clang++"
  local target=$([[ $abi == arm64-v8a ]] && echo aarch64-linux-android33 || echo x86_64-linux-android33)
  mkdir -p "$OUT/$abi"
  "$cxx" --target=$target -O3 -fPIC -shared -std=c++17 ${arch:+-march=$arch} \
    -I"$SRC/include" -I"$SRC/ggml/include" "$GLUE" \
    -Wl,--whole-archive "$b/src/libwhisper.a" -Wl,--no-whole-archive \
    "$b/ggml/src/libggml.a" "$b/ggml/src/libggml-cpu.a" "$b/ggml/src/libggml-base.a" \
    -static-libstdc++ -llog -lm -ldl \
    -Wl,--gc-sections -Wl,--exclude-libs,ALL -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 \
    -Wl,--version-script=<(printf '{ global: Java_*; local: *; };') \
    -o "$OUT/$abi/$name.so"
  "$LLVM/llvm-strip" --strip-unneeded "$OUT/$abi/$name.so"
  ls -l "$OUT/$abi/$name.so" | awk '{print "   ", $5, "bytes"}'
}
build libuth_whisper_v82 arm64-v8a armv8.2-a+dotprod+fp16
build libuth_whisper arm64-v8a armv8-a
build libuth_whisper x86_64 ""
# every LOAD segment aligned at 16 KB or more (Google Play, android-plan.md 8.5)
for f in "$OUT"/*/*.so; do
  bad=$("$LLVM/llvm-readelf" -lW "$f" | awk '$1=="LOAD"{print $NF}' | while read a; do if (( a < 16384 )); then echo "$a"; fi; done)
  [[ -z $bad ]] && echo "16 KB: ok  $f" || { echo "16 KB: NOT ALIGNED $f ($bad)"; exit 1; }
done
