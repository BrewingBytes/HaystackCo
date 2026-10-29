#!/usr/bin/env bash
# Google Play 16 KB page-size check for an exported AAB (G1).
# Every native library must have ELF LOAD segments aligned to >= 16 KB (2**14)
# and be stored uncompressed + 16 KB-aligned in the APK.
# Usage: tools/check_16kb.sh build/haystack.aab
# Needs: bundletool, ANDROID_HOME (build-tools zipalign, NDK llvm-readelf), a keystore in KS/KS_PASS/KS_ALIAS
# (defaults to the Android debug keystore).
set -euo pipefail
AAB="${1:?usage: check_16kb.sh <file.aab>}"
KS="${KS:-$HOME/.android/debug.keystore}"; KS_PASS="${KS_PASS:-android}"; KS_ALIAS="${KS_ALIAS:-androiddebugkey}"
SDK="${ANDROID_HOME:?set ANDROID_HOME}"
ZIPALIGN=$(ls -d "$SDK"/build-tools/*/ | sort -V | tail -1)zipalign
READELF=$(find "$SDK/ndk" -name llvm-readelf | sort -V | tail -1)
[ -n "$READELF" ] || { echo "llvm-readelf not found under $SDK/ndk"; exit 2; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

bundletool build-apks --bundle="$AAB" --output="$WORK/app.apks" --mode=universal \
  --ks="$KS" --ks-pass="pass:$KS_PASS" --ks-key-alias="$KS_ALIAS" --key-pass="pass:$KS_PASS" >/dev/null
unzip -q -o "$WORK/app.apks" universal.apk -d "$WORK"

echo "== zipalign -P 16 (uncompressed .so aligned to 16 KB)"
"$ZIPALIGN" -c -P 16 -v 4 "$WORK/universal.apk" | grep -E '\.so|Verification' || true
"$ZIPALIGN" -c -P 16 4 "$WORK/universal.apk"

echo "== ELF LOAD alignment"
unzip -q -o "$WORK/universal.apk" 'lib/*' -d "$WORK/x"
fail=0
while IFS= read -r so; do
  # An empty or non-ELF library (e.g. a GDExtension that wasn't built) would read as "no LOAD segments".
  if [ "$(head -c 4 "$so" | od -An -tx1 | tr -d ' \n')" != "7f454c46" ]; then
    echo "FAIL ${so#$WORK/x/} is not an ELF library (empty or missing build)"; fail=1; continue
  fi
  bad=""
  for a in $("$READELF" -lW "$so" | awk '$1=="LOAD"{print $NF}'); do
    [ $((a)) -lt 16384 ] && bad="$bad $a"
  done
  if [ -n "$bad" ]; then echo "FAIL ${so#$WORK/x/} align=$bad"; fail=1; else echo "ok   ${so#$WORK/x/}"; fi
done < <(find "$WORK/x/lib" -name '*.so' | sort)
[ "$fail" -eq 0 ] && echo "16 KB check: PASS" || { echo "16 KB check: FAIL"; exit 1; }
