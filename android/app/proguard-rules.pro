## Flutter & Firebase ProGuard Rules

# Firebase Auth
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Firestore
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# Keep Firestore model classes (prevents stripping serialization)
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName <fields>;
}

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Core (deferred components / split install)
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# OkHttp / network layer (used by Firebase)
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**

# HomeWidget plugin
-keep class es.antonborri.home_widget.** { *; }

# App Widget Providers (required for requestPinWidget)
-keep class com.example.love_app.LoveWidgetProvider { *; }
-keep class com.example.love_app.DaysCounterWidgetProvider { *; }
-keep class com.example.love_app.TimerWidgetProvider { *; }
-keep class com.example.love_app.PhotoDayWidgetProvider { *; }
-keep class com.example.love_app.MoodWidgetProvider { *; }
-keep class com.example.love_app.RelationshipStatsWidgetProvider { *; }

