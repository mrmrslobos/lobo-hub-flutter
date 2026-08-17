# Flutter embedding (required for release builds).
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase / Google Play services (FCM, Crashlytics, Sign-In).
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# RevenueCat / Play Billing.
-keep class com.revenuecat.purchases.** { *; }
-keep class com.android.billingclient.** { *; }

# Workmanager background tasks.
-keep class androidx.work.** { *; }
-keepclassmembers class * extends androidx.work.Worker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# Gson / JSON reflection (used by some plugins).
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

# OkHttp (transitive).
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep native MainActivity entry point only.
-keep class com.opensolutions.huddle.MainActivity { *; }
