# Flutter WebRTC Rules
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-keepattributes *Annotation*, InnerClasses, Signature, Exceptions
-dontwarn org.webrtc.**

# Vosk Flutter (JNA) Rules
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }
-dontwarn com.sun.jna.**

# Audio Session / general plugins
-keep class com.ryanheise.audio_session.** { *; }
-dontwarn com.ryanheise.audio_session.**

# Record plugin
-keep class com.llfbandit.record.** { *; }
-dontwarn com.llfbandit.record.**

# Flutter Overlay Window plugin
-keep class flutter.overlay.window.** { *; }
-dontwarn flutter.overlay.window.**
