#!/usr/bin/env python3
"""Checks an OrbGuard Amazon Appstore APK before anyone uploads it.

Amazon rejected the sister app OrbVPN nine times. Its scanner flags an
ad-network or Firebase library that is merely present in the APK, reads
ad-network names in the Dart snapshot as the SDKs themselves, and rejects
any purchase path outside Amazon's own. This script looks for each of
those in the finished APK:

  1. classes*.dex: no Unity, Adivery, Yandex Mobile Ads, Google Mobile
     Ads, Firebase or Play Billing package, as a class or as a string.
     Other strings with an ad-network name are listed, not failed.
  2. lib/*/*.so: no native library named after an ad network or Firebase.
  3. The merged manifest (aapt2): no AD_ID, AdServices or BILLING
     permission.
  4. No app-ads.txt anywhere in the APK.
  5. lib/*/libapp.so, byte by byte: no ad-network name. A few English
     words that happen to contain one ("community", "opportunity") are
     allowed and listed.
  6. libapp.so has none of the words of the credits sheet and the pricing
     screen, which kAmazonBuild compiles out.
  7. The signer is not a debug key.

Usage: verify_amazon_apk.py APK --build-tools DIR
Exits 0 when every check passes, 1 otherwise. Prints only public facts
(class counts, permissions, the signing certificate's name and digest).
"""

import argparse
import re
import subprocess
import sys
import zipfile
from collections import Counter

# Package names as dex files store them: "com/unity3d/" inside a type
# descriptor (a class that is present, or code that refers to one), and
# "com.unity3d." in a string (a class name looked up by reflection, or a
# package name the app reads).
FORBIDDEN_PACKAGES = {
    "Unity": "com.unity3d",
    "Adivery": "com.adivery",
    "Yandex Mobile Ads": "com.yandex.mobile.ads",
    "Google Mobile Ads (GMS ads)": "com.google.android.gms.ads",
    "GMS measurement": "com.google.android.gms.measurement",
    "Firebase": "com.google.firebase",
    "Play Billing": "com.android.billingclient",
    "AppLovin": "com.applovin",
    "ironSource": "com.ironsource",
    "Tapsell": "ir.tapsell",
}
FORBIDDEN_CLASSES = {
    label: [(package + ".").encode(), (package.replace(".", "/") + "/").encode()]
    for label, package in FORBIDDEN_PACKAGES.items()
}

# Firebase-named parts that are not Firebase services. ML Kit's on-device
# barcode scanner (mobile_scanner, the QR check) runs on Google's small
# component and encoder libraries, which keep these names as strings after
# R8 renames their classes. No Firebase service, project or network call
# comes with them, and the QR check needs them.
KNOWN_INTERNALS = {
    b"com.google.firebase.components.": "ML Kit runtime, used by the QR scanner",
    b"com.google.firebase.components:": "ML Kit runtime, used by the QR scanner",
    b"com.google.firebase.encoders.": "ML Kit runtime, used by the QR scanner",
}

AD_NAMES = [
    "unity", "adivery", "yandex", "ironsource", "levelplay", "admob",
    "applovin", "tapsell",
]

# English words that contain an ad-network name by accident.
ALLOWED_WORDS = {
    "community", "communities", "opportunity", "opportunities", "immunity",
    "immunities", "impunity", "importunity",
    # dev.fluttercommunity.*: the connectivity, device info, package info,
    # share and workmanager plugins.
    "fluttercommunity",
}

NATIVE_LIB_PATTERN = re.compile(
    r"unity|adivery|yandex|applovin|ironsource|levelplay|tapsell|admob|"
    r"mobileads|firebase|crashlytics",
    re.IGNORECASE,
)

FORBIDDEN_PERMISSIONS = re.compile(r"AD_ID|ADSERVICES|com\.android\.vending\.BILLING")

# Hardware the app can work without. A Fire tablet has no GPS, and a
# required camera or microphone would cut out more devices.
OPTIONAL_HARDWARE = {
    "android.hardware.location",
    "android.hardware.location.gps",
    "android.hardware.location.network",
    "android.hardware.camera",
    "android.hardware.camera.any",
    "android.hardware.microphone",
}

# Words only the credits sheet and the pricing screen use. kAmazonBuild
# leaves both out of the Amazon binary, so none may be there.
COMPILED_OUT = [
    b"Watch ad to earn a scan",
    b"Go unlimited with a plan",
    b"every month. Renews automatically.",
    b"once a year. Renews automatically.",
]


class Report:
    def __init__(self):
        self.failed = False

    def ok(self, message):
        print(f"  ok    {message}")

    def fail(self, message):
        self.failed = True
        print(f"  FAIL  {message}")

    def info(self, message):
        print(f"        {message}")


def check_dex(apk, report):
    print("dex classes")
    dex_names = sorted(n for n in apk.namelist() if re.fullmatch(r"classes\d*\.dex", n))
    if not dex_names:
        report.fail("no classes.dex in the APK")
        return
    totals = Counter()
    known = Counter()
    for name in dex_names:
        data = apk.read(name)
        for label, prefixes in FORBIDDEN_CLASSES.items():
            for prefix in prefixes:
                for m in re.finditer(re.escape(prefix), data):
                    tail = data[m.start():m.start() + 64]
                    part = next((k for k in KNOWN_INTERNALS if tail.startswith(k)), None)
                    if part is None:
                        totals[label] += 1
                        report.info(f"{name}: {context_at(data, m.start(), m.end(), 32)}")
                    else:
                        known[part] += 1
    for label in FORBIDDEN_CLASSES:
        if totals[label]:
            report.fail(f"{label}: {totals[label]} references in {', '.join(dex_names)}")
        else:
            report.ok(f"{label}: none")
    for part, count in sorted(known.items()):
        report.info(f"known, not an SDK: {part.decode()}* x{count} "
                    f"({KNOWN_INTERNALS[part]})")
    # Not a failure: a name in a string is not an SDK. Listed so a person
    # can judge what a reviewer's scanner would see.
    for name in dex_names:
        data = apk.read(name)
        for ad in AD_NAMES:
            for m in re.finditer(re.escape(ad).encode(), data, re.IGNORECASE):
                if allowed_word_at(data, m.start(), m.end()) is None:
                    report.info(f"{name}: string with '{ad}': "
                                f"...{context_at(data, m.start(), m.end(), 24)}...")


def check_native_libs(apk, report):
    print("native libraries")
    libs = sorted(n for n in apk.namelist() if n.startswith("lib/") and n.endswith(".so"))
    bad = [n for n in libs if NATIVE_LIB_PATTERN.search(n.rsplit("/", 1)[-1])]
    for n in bad:
        report.fail(f"ad or Firebase library: {n}")
    if not bad:
        names = sorted({n.rsplit("/", 1)[-1] for n in libs})
        report.ok(f"none named after an ad network or Firebase ({', '.join(names)})")


def check_permissions(apk_path, build_tools, report):
    print("merged manifest permissions (aapt2)")
    out = subprocess.run(
        [f"{build_tools}/aapt2", "dump", "permissions", apk_path],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        report.fail(f"aapt2 dump permissions failed: {out.stderr.strip()}")
        return
    perms = re.findall(r"uses-permission(?:-sdk-23)?: name='([^']+)'", out.stdout)
    bad = [p for p in perms if FORBIDDEN_PERMISSIONS.search(p)]
    for p in bad:
        report.fail(f"permission {p}")
    if not bad:
        report.ok("no AD_ID, AdServices or BILLING permission")
    report.info(f"{len(perms)} permissions: {', '.join(perms)}")


def check_features(apk_path, build_tools, report):
    """No Fire tablet has GPS, and Amazon reads a required GPS (or one a
    location permission implies) as "incompatible with every tablet"."""
    print("required hardware (aapt2)")
    out = subprocess.run(
        [f"{build_tools}/aapt2", "dump", "badging", apk_path],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        report.fail(f"aapt2 dump badging failed: {out.stderr.strip()}")
        return
    required = set(re.findall(r"^\s*uses-(?:implied-)?feature: name='([^']+)'",
                              out.stdout, re.M))
    bad = sorted(f for f in required if f in OPTIONAL_HARDWARE)
    for f in bad:
        report.fail(f"requires {f}, which Fire tablets lack or Amazon checks")
    if not bad:
        report.ok("GPS, location, camera and microphone are all optional")


def check_app_ads(apk, report):
    print("app-ads.txt")
    hits = [n for n in apk.namelist() if "app-ads" in n.lower()]
    for n in hits:
        report.fail(f"{n} is in the APK")
    if not hits:
        report.ok("not in the APK")


def allowed_word_at(data, start, end):
    """The allowed English word that data[start:end] sits inside, if any.

    Looks at the bytes around the hit rather than the whole identifier, so
    "community" is found in "_fetchCommunityIoCs" too.
    """
    reach = max(len(w) for w in ALLOWED_WORDS)
    left = max(0, start - reach)
    window = data[left:end + reach].lower()
    for word in sorted(ALLOWED_WORDS, key=len, reverse=True):
        needle = word.encode()
        at = window.find(needle)
        while at != -1:
            if left + at <= start and left + at + len(needle) >= end:
                return word
            at = window.find(needle, at + 1)
    return None


def context_at(data, start, end, width=40):
    """Printable bytes around a hit, for the report."""
    left, right = max(0, start - width), min(len(data), end + width)
    return "".join(chr(b) if 32 <= b < 127 else "." for b in data[left:right])


def check_libapp(apk, report):
    print("Dart snapshot (libapp.so), byte scan")
    libapps = sorted(n for n in apk.namelist() if n.endswith("/libapp.so"))
    if not libapps:
        report.fail("no libapp.so in the APK")
        return
    for name in libapps:
        data = apk.read(name)
        allowed = Counter()
        hits = []
        for ad in AD_NAMES:
            for m in re.finditer(re.escape(ad).encode(), data, re.IGNORECASE):
                word = allowed_word_at(data, m.start(), m.end())
                if word is not None:
                    allowed[word] += 1
                else:
                    hits.append((ad, context_at(data, m.start(), m.end())))
        if hits:
            for ad, ctx in hits:
                report.fail(f"{name}: '{ad}' in ...{ctx}...")
        else:
            report.ok(f"{name}: no ad-network name ({len(data):,} bytes)")
        if allowed:
            words = ", ".join(f"{w} x{c}" for w, c in sorted(allowed.items()))
            report.info(f"allowed English words: {words}")
        left_in = [m.decode() for m in COMPILED_OUT if m in data]
        for marker in left_in:
            report.fail(f"{name}: still has '{marker}' (the credits sheet or "
                        "pricing screen was not compiled out)")
        if not left_in:
            report.ok(f"{name}: none of the credits sheet or pricing screen words")


def check_signer(apk_path, build_tools, report):
    print("signature")
    out = subprocess.run(
        [f"{build_tools}/apksigner", "verify", "--print-certs", apk_path],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        report.fail(f"apksigner verify failed: {out.stderr.strip() or out.stdout.strip()}")
        return
    dn = re.search(r"Signer #1 certificate DN: (.+)", out.stdout)
    sha = re.search(r"Signer #1 certificate SHA-256 digest: ([0-9a-f]+)", out.stdout)
    dn_text = dn.group(1).strip() if dn else "unknown"
    if "Android Debug" in dn_text:
        report.fail(f"signed with the debug key ({dn_text})")
    else:
        report.ok(f"signed by {dn_text}")
    if sha:
        report.info(f"certificate SHA-256 {sha.group(1)}")


def print_badging(apk_path, build_tools):
    out = subprocess.run(
        [f"{build_tools}/aapt2", "dump", "badging", apk_path],
        capture_output=True, text=True,
    )
    m = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", out.stdout)
    if m:
        print(f"package {m.group(1)}, versionCode {m.group(2)}, versionName {m.group(3)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("apk")
    parser.add_argument("--build-tools", required=True,
                        help="Android SDK build-tools directory (aapt2, apksigner)")
    args = parser.parse_args()

    report = Report()
    print_badging(args.apk, args.build_tools)
    with zipfile.ZipFile(args.apk) as apk:
        check_dex(apk, report)
        check_native_libs(apk, report)
        check_app_ads(apk, report)
        check_libapp(apk, report)
    check_permissions(args.apk, args.build_tools, report)
    check_features(args.apk, args.build_tools, report)
    check_signer(args.apk, args.build_tools, report)

    print("VERIFY FAILED" if report.failed else "VERIFY PASSED")
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())
