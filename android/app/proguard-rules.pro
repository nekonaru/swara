# Conservative keeps for the parts of the app and its plugins that reach the
# framework through reflection or JNI. Everything else is fair game for R8.

# App code: our tiny Kotlin surface (MainActivity, audio effects, widget).
-keep class com.nikodwidharma.offline_music_player.** { *; }

# Flutter engine embedding and JNI bridges.
-keep class io.flutter.** { *; }
-keepclassmembers class io.flutter.** { *; }

# audio_service and just_audio (media session, service binding, JNI).
-keep class com.ryanheise.** { *; }
-keepclassmembers class com.ryanheise.** { *; }

# on_audio_query (MediaStore queries through the platform channel).
-keep class com.on_audio_query.** { *; }
-keep class on_audio_query.** { *; }

# permission_handler (reflection over annotation processors).
-keep class com.baseflow.permissionhandler.** { *; }

# Kotlin metadata needed by reflection-based tooling.
-keep class kotlin.Metadata { *; }
-keepattributes Signature, InnerClasses, EnclosingMethod, AnnotationDefault

-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**

# Flutter's embedding references the Play Core deferred-components API,
# which we never use (our app is a single APK, no split delivery).
-dontwarn com.google.android.play.core.**
