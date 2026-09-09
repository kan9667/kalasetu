# Proguard rules for Flutter release build
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-dontwarn androidx.work.**

# Keep Flutter and Drift SQLite classes
-keep class io.flutter.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class org.sqlite.** { *; }
