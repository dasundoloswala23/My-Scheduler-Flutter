# Flutter embedding and plugins are kept by their own consumer rules.
# These rules cover reflection-based code the shrinker cannot see.

# Firebase / Firestore model mapping uses reflection on field names.
-keepattributes Signature,*Annotation*,EnclosingMethod,InnerClasses
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# flutter_local_notifications: notification actions and boot restoration are
# resolved by class name from the manifest, so they must survive shrinking.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends android.content.BroadcastReceiver

# Gson (used by the notifications plugin) needs generic signatures.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
