# Flutter Local Notifications - keep rules for R8/ProGuard
# Fixes: PlatformException(error, TypeToken must be created with a type argument)
# The plugin uses Gson which requires generic type information to be preserved.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Keep the flutter_local_notifications plugin classes
-keep class com.dexterous.** { *; }

# Keep Gson classes
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
