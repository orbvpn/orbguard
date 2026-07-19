# OrbGuard release (R8) keep rules.

# --- Auto-generated missing rules (R8 asked for these) ---
# Optional mbridge mediation classes referenced by Adivery but not bundled.
-dontwarn com.mbridge.msdk.nativex.view.MBMediaView
-dontwarn com.mbridge.msdk.video.bt.module.orglistener.g

# --- Ad SDKs: keep to avoid reflection-based runtime breakage after minify ---
-keep class com.adivery.** { *; }
-dontwarn com.adivery.**
-keep class com.unity3d.** { *; }
-dontwarn com.unity3d.**
-keep class com.yandex.mobile.ads.** { *; }
-dontwarn com.yandex.mobile.ads.**
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
-dontwarn com.mbridge.**
-keep class com.mbridge.** { *; }

# --- Common: keep annotations / native / Play Core (used by Flutter deferred) ---
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-dontwarn com.google.android.play.core.**
