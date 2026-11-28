#!/usr/bin/env bash
# Builds the Amazon Appstore APK of OrbGuard: a build that sells nothing.
#
# Amazon rejected the sister app OrbVPN nine times. Its scanner flags an
# ad-network or Firebase library that is merely present in the APK, reads
# ad-network names in the Dart snapshot as the SDKs themselves, and Amazon
# rejects any purchase path outside its own, any pointer to paying
# elsewhere, and account creation in an app without Amazon's billing. So
# this build:
#
#   1. points the ad plugins (unity_ads_plugin, adivery, yandex_mobileads),
#      the Firebase plugins and the store purchase plugins at pure-Dart
#      stand-ins in amazon/stubs/ through a temporary pubspec_overrides.yaml.
#      None of them has native code, so none of the SDKs reaches the APK.
#      It also points package:mime (dio and share_plus look up file types
#      with it) at a copy without its one ad-network name, the
#      "application/vnd.unity" type for .unityweb files;
#   2. drops the Google services Gradle plugin, any Firebase or GMS ads
#      dependency, the AD_ID and BILLING permissions, and the entries in
#      SupplyChainChannelHandler.kt that map native libraries to Unity
#      and Firebase packages (other apps' libraries it recognises);
#   3. removes app-ads.txt, wherever it is;
#   4. builds a release APK with --dart-define=ORB_AMAZON_BUILD=true, which
#      turns on kAmazonBuild (lib/utils/amazon_build.dart): no plans,
#      prices, ads, credits to earn, store or site to pay at, and no
#      account creation;
#   5. checks the APK with amazon/verify_amazon_apk.py;
#   6. puts every file it changed back, even when a step fails.
#
# The APK is signed with the upload keystore named in android/key.properties,
# as every release build is. That file must exist: without it Gradle signs
# with the debug key, which no store accepts. Nothing here prints it.
#
# Usage: amazon/build_amazon_apk.sh [--out DIR] [--build-number N]
#   --out DIR         where the APK goes (default: build/amazon)
#   --build-number N  a versionCode for this build only; the version name
#                     stays the one in pubspec.yaml
#
# Run it from anywhere; it works in the app/ directory it lives in.

set -uo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR" || exit 1

OUT_DIR="$APP_DIR/build/amazon"
BUILD_NUMBER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    -h|--help) sed -n '2,39p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$OUT_DIR" && OUT_DIR="$(cd "$OUT_DIR" && pwd)"

die() { echo "!!! $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight: nothing is changed until all of this holds.
# ---------------------------------------------------------------------------
[ -f android/key.properties ] ||
  die "android/key.properties is missing: the APK would be signed with the debug key."
STORE_FILE="$(sed -n 's/^storeFile=//p' android/key.properties | head -1)"
case "$STORE_FILE" in
  /*) ;;
  *) STORE_FILE="android/app/$STORE_FILE" ;;
esac
[ -f "$STORE_FILE" ] || die "the keystore named in android/key.properties is missing."

SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
BUILD_TOOLS="$(ls -d "$SDK_DIR"/build-tools/* 2>/dev/null | sort -V | tail -1)"
[ -x "$BUILD_TOOLS/aapt2" ] && [ -x "$BUILD_TOOLS/apksigner" ] ||
  die "no Android build-tools with aapt2 and apksigner under $SDK_DIR."
command -v flutter >/dev/null || die "flutter is not on PATH."
command -v python3 >/dev/null || die "python3 is not on PATH."

# The JDK's TLS 1.3 fails Gradle downloads on some networks with
# "Tag mismatch"; TLS 1.2 does not. A value already set is kept.
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--Djdk.tls.client.protocols=TLSv1.2 -Dhttps.protocols=TLSv1.2}"

MANIFEST=android/app/src/main/AndroidManifest.xml
APP_GRADLE=android/app/build.gradle.kts
SETTINGS_GRADLE=android/settings.gradle.kts
SUPPLY_CHAIN_KT=android/app/src/main/kotlin/com/orb/guard/SupplyChainChannelHandler.kt
OVERRIDES=pubspec_overrides.yaml
# Every file this script edits, writes or deletes. pubspec.lock is kept so
# the restore resolves exactly the versions there were before. The plugin
# registrants are tracked by git and flutter pub get rewrites them.
TOUCHED=(
  "$MANIFEST" "$APP_GRADLE" "$SETTINGS_GRADLE" "$SUPPLY_CHAIN_KT" pubspec.yaml pubspec.lock
  "$OVERRIDES" app-ads.txt assets/app-ads.txt android/app/src/main/assets/app-ads.txt
  linux/flutter/generated_plugin_registrant.cc linux/flutter/generated_plugin_registrant.h
  linux/flutter/generated_plugins.cmake macos/Flutter/GeneratedPluginRegistrant.swift
  windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugin_registrant.h
  windows/flutter/generated_plugins.cmake
)

BACKUP="$(mktemp -d "${TMPDIR:-/tmp}/orbguard-amazon.XXXXXX")"
RESTORED=0

restore() {
  [ "$RESTORED" = 1 ] && return
  RESTORED=1
  echo "=== restoring every changed file ==="
  local f
  for f in "${TOUCHED[@]}"; do
    if [ -e "$BACKUP/files/$f" ]; then
      mkdir -p "$(dirname "$f")"
      cp -p "$BACKUP/files/$f" "$f"
    else
      rm -f "$f"
    fi
  done
  echo "=== flutter pub get (back to the normal plugins) ==="
  flutter pub get >"$BACKUP/pub-get-restore.log" 2>&1 ||
    echo "!!! flutter pub get failed while restoring; see $BACKUP/pub-get-restore.log" >&2
  if git -C "$APP_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    local changed
    changed="$(git -C "$APP_DIR" status --porcelain -- "${TOUCHED[@]}" 2>/dev/null)"
    [ -z "$changed" ] || { echo "!!! still changed after restore:" >&2; echo "$changed" >&2; }
  fi
  rm -rf "$BACKUP"
  echo "restored."
}
trap restore EXIT
trap 'exit 130' INT TERM

echo "=== backing up the files this build changes ==="
for f in "${TOUCHED[@]}"; do
  if [ -e "$f" ]; then
    mkdir -p "$BACKUP/files/$(dirname "$f")"
    cp -p "$f" "$BACKUP/files/$f"
  fi
done

# ---------------------------------------------------------------------------
# 1. The plugins with native SDKs become pure-Dart stand-ins.
# ---------------------------------------------------------------------------
echo "=== 1) package:mime without the Unity media type ==="
# The copy lives in the backup folder, so the restore deletes it.
[ -f .dart_tool/package_config.json ] || flutter pub get >/dev/null 2>&1 ||
  die "flutter pub get failed before the build."
MIME_SRC="$(python3 - <<'PY'
import json
from urllib.parse import unquote, urlparse
packages = json.load(open(".dart_tool/package_config.json"))["packages"]
root = next(p["rootUri"] for p in packages if p["name"] == "mime")
print(unquote(urlparse(root).path) if root.startswith("file:") else root)
PY
)"
[ -f "$MIME_SRC/pubspec.yaml" ] || die "package:mime is not where the package config says."
MIME_COPY="$BACKUP/mime"
cp -R "$MIME_SRC" "$MIME_COPY" && chmod -R u+w "$MIME_COPY" || die "could not copy package:mime."
python3 - "$MIME_COPY/lib" <<'PY' || die "could not edit the package:mime copy."
import pathlib, re, sys
# Only map entries such as 'unityweb': 'application/vnd.unity', go.
entry = re.compile(r"^\s*'[^']*unity[^']*'\s*:\s*'[^']*'\s*,\s*$", re.IGNORECASE)
for path in pathlib.Path(sys.argv[1]).rglob("*.dart"):
    lines = path.read_text().splitlines(keepends=True)
    kept = [line for line in lines if not entry.match(line)]
    if len(kept) != len(lines):
        path.write_text("".join(kept))
PY
! grep -rqi 'unity' "$MIME_COPY/lib" || die "package:mime still names Unity."

echo "=== 1) pubspec_overrides.yaml: ad, Firebase and purchase plugins -> amazon/stubs ==="
# pubspec.yaml has no dependency_overrides of its own; if it ever gets
# some, repeat them here, because this file replaces them.
cat >"$OVERRIDES" <<YAML
# Written by amazon/build_amazon_apk.sh for one Amazon build, then removed.
dependency_overrides:
  unity_ads_plugin:
    path: amazon/stubs/unity_ads_plugin
  adivery:
    path: amazon/stubs/adivery
  yandex_mobileads:
    path: amazon/stubs/yandex_mobileads
  firebase_core:
    path: amazon/stubs/firebase_core
  firebase_messaging:
    path: amazon/stubs/firebase_messaging
  firebase_crashlytics:
    path: amazon/stubs/firebase_crashlytics
  firebase_analytics:
    path: amazon/stubs/firebase_analytics
  in_app_purchase:
    path: amazon/stubs/in_app_purchase
  in_app_purchase_android:
    path: amazon/stubs/in_app_purchase_android
  mime:
    path: $MIME_COPY
YAML
grep -q '^dependency_overrides:' pubspec.yaml &&
  die "pubspec.yaml now has dependency_overrides; repeat them in this script's overrides."

# ---------------------------------------------------------------------------
# 2. Gradle and manifest: no Google services plugin, no Firebase or GMS ads,
#    no AD_ID, no BILLING.
# ---------------------------------------------------------------------------
echo "=== 2) Gradle: drop the Google services plugin and Firebase or GMS ads deps ==="
for g in "$APP_GRADLE" "$SETTINGS_GRADLE"; do
  grep -vE 'com\.google\.gms\.google-services|firebase-|play-services-ads' "$g" >"$g.amazon" &&
    mv "$g.amazon" "$g"
done
left="$(grep -cE 'com\.google\.gms\.google-services|firebase-|play-services-ads' "$APP_GRADLE" "$SETTINGS_GRADLE" | awk -F: '{s+=$2} END {print s}')"
[ "$left" = 0 ] || die "Gradle still names Google services, Firebase or GMS ads."

echo "=== 2) SupplyChainChannelHandler.kt: drop the Unity and Firebase library names ==="
# Entries such as "libunity.so" to "com.unity3d.player". Without them those
# libraries in other apps are listed by file name only.
grep -vE '" to "com\.(unity3d|google\.firebase)\.' "$SUPPLY_CHAIN_KT" >"$BACKUP/kt.amazon" &&
  cat "$BACKUP/kt.amazon" >"$SUPPLY_CHAIN_KT" || die "could not edit $SUPPLY_CHAIN_KT"
! grep -qE '" to "com\.(unity3d|google\.firebase)\.' "$SUPPLY_CHAIN_KT" ||
  die "$SUPPLY_CHAIN_KT still names Unity or Firebase packages."

echo "=== 2) manifest: drop BILLING, and remove AD_ID, AdServices and BILLING from the merge ==="
grep -v 'com.android.vending.BILLING' "$MANIFEST" >"$MANIFEST.amazon" && mv "$MANIFEST.amazon" "$MANIFEST"
python3 - "$MANIFEST" <<'PY' || die "could not edit the manifest."
import sys
path = sys.argv[1]
text = open(path).read()
removals = "".join(
    f'    <uses-permission android:name="{name}" tools:node="remove" />\n'
    for name in (
        "com.google.android.gms.permission.AD_ID",
        "android.permission.ACCESS_ADSERVICES_AD_ID",
        "android.permission.ACCESS_ADSERVICES_ATTRIBUTION",
        "android.permission.ACCESS_ADSERVICES_TOPICS",
        "com.android.vending.BILLING",
    )
)
marker = "    <application"
if 'xmlns:tools="http://schemas.android.com/tools"' not in text or text.count(marker) != 1:
    sys.exit("manifest layout changed: no tools namespace or no single <application>")
text = text.replace(marker, "    <!-- Amazon build: never merged in from a library. -->\n" + removals + marker)
open(path, "w").write(text)
PY

# ---------------------------------------------------------------------------
# 3. app-ads.txt is an ad sellers' file; Amazon reads it as an ad SDK.
# ---------------------------------------------------------------------------
echo "=== 3) app-ads.txt: remove it wherever it is ==="
rm -f app-ads.txt assets/app-ads.txt android/app/src/main/assets/app-ads.txt
grep -vE '^\s*-\s*(assets/)?app-ads\.txt\s*$' pubspec.yaml >pubspec.yaml.amazon && mv pubspec.yaml.amazon pubspec.yaml

# ---------------------------------------------------------------------------
# 4. Build.
# ---------------------------------------------------------------------------
echo "=== 4) flutter clean + pub get with the stand-ins ==="
flutter clean >/dev/null 2>&1
flutter pub get 2>&1 | tail -3
[ "${PIPESTATUS[0]}" = 0 ] || die "flutter pub get failed with the stand-ins."
if grep -qE '"name":"(unity_ads_plugin|adivery|yandex_mobileads|firebase_[a-z]+|in_app_purchase_android)"' .flutter-plugins-dependencies 2>/dev/null; then
  die "a stubbed plugin is still registered as a native plugin."
fi

echo "=== 4) flutter build apk --release --dart-define=ORB_AMAZON_BUILD=true ${BUILD_NUMBER:+--build-number $BUILD_NUMBER} ==="
BUILD_LOG="$OUT_DIR/build.log"
flutter build apk --release --dart-define=ORB_AMAZON_BUILD=true \
  ${BUILD_NUMBER:+--build-number "$BUILD_NUMBER"} >"$BUILD_LOG" 2>&1
BUILD_STATUS=$?
tail -15 "$BUILD_LOG"
[ "$BUILD_STATUS" = 0 ] || die "the build failed; the full log is $BUILD_LOG"

BUILT=build/app/outputs/flutter-apk/app-release.apk
[ -f "$BUILT" ] || die "the build reported success but there is no $BUILT"
VERSION_NAME="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml | head -1)"
APK="$OUT_DIR/OrbGuard-${VERSION_NAME}-amazon.apk"
cp "$BUILT" "$APK"
echo "=== built $APK ($(wc -c <"$APK" | tr -d ' ') bytes) ==="

# ---------------------------------------------------------------------------
# 5. Check what came out.
# ---------------------------------------------------------------------------
echo "=== 5) verify ==="
python3 "$APP_DIR/amazon/verify_amazon_apk.py" "$APK" --build-tools "$BUILD_TOOLS" ||
  die "the APK failed verification: do not upload it."

echo "AMAZON_BUILD_DONE $APK"
