# Keep app's own code
-keep class com.smartalbum.smart_album.** { *; }

# Flutter - keep everything
-keep class io.flutter.** { *; }

# Keep all Flutter plugins (widely-used packages)
-keep class com.baseflow.** { *; }
-keep class com.tekartik.** { *; }
-keep class com.fluttercandies.** { *; }
-keep class com.dexterous.** { *; }
-keep class dev.fluttercommunity.** { *; }
-keep class vn.hunghd.** { *; }

# JSON (used in MethodChannel serialization)
-keep class org.json.** { *; }

# SQLite native
-keep class org.sqlite.** { *; }

# Android core components
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# Keep attributes needed by reflection
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes InnerClasses
-keepattributes Signature
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations

# Play Core (referenced by Flutter embedding, not actually used)
-dontwarn com.google.android.play.core.**
